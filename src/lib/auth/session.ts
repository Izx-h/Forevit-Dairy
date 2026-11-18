import "server-only";
import { redirect } from "next/navigation";
import type { OrganizationRole, WorkspaceMember, WorkspaceProject } from "@/lib/domain";
import { normalizeRole } from "@/lib/domain";
import { createSupabaseServerClient, isSupabaseConfigured } from "@/lib/supabase/server";

export type WorkspaceContext =
  | { status: "not_configured" }
  | { status: "anonymous" }
  | { status: "no_membership"; email: string }
  | { status: "ready"; member: WorkspaceMember };

export async function getWorkspaceContext(): Promise<WorkspaceContext> {
  if (!isSupabaseConfigured()) return { status: "not_configured" };
  const supabase = await createSupabaseServerClient();
  if (!supabase) return { status: "not_configured" };

  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) return { status: "anonymous" };

  const [{ data: profile }, { data: orgRows }, { data: projectRows }] = await Promise.all([
    supabase.from("profiles").select("display_name, platform_owner").eq("id", user.id).maybeSingle(),
    supabase.from("organization_members").select("organization_id, role").eq("user_id", user.id).eq("status", "active").order("joined_at", { ascending: true }),
    supabase.from("project_members").select("project_id, role, projects(id, name, description, status)").eq("user_id", user.id).eq("status", "active")
  ]);

  const organizations = orgRows ?? [];
  const firstOrg = organizations[0] as { organization_id: string; role: string } | undefined;
  const isPlatformOwner = profile?.platform_owner === true;
  const projectRecords: WorkspaceProject[] = (projectRows ?? []).flatMap((row) => {
    const item = row as unknown as { role: string; projects: { id: string; name: string; description: string | null; status: string } | null };
    if (!item.projects) return [];
    const role = normalizeRole(item.role);
    return [{ ...item.projects, role: role === "platform_owner" ? "project_lead" : role }];
  });
  if (isPlatformOwner) {
    const { data: allProjects } = await supabase.from("projects").select("id, name, description, status").order("created_at", { ascending: true });
    const byId = new Map(projectRecords.map((project) => [project.id, project]));
    for (const project of allProjects ?? []) byId.set(project.id, { ...project, role: "platform_owner" });
    projectRecords.splice(0, projectRecords.length, ...byId.values());
  }

  if (!firstOrg && projectRecords.length === 0 && !isPlatformOwner) return { status: "no_membership", email: user.email ?? "" };
  const organizationRole = firstOrg ? normalizeRole(firstOrg.role) : null;
  const role: OrganizationRole | WorkspaceMember["role"] = isPlatformOwner ? "platform_owner" : organizationRole ?? projectRecords[0]?.role ?? "viewer";
  return {
    status: "ready",
    member: {
      id: user.id,
      email: user.email ?? "",
      fullName: profile?.display_name || user.user_metadata?.full_name || user.email || "Member",
      role,
      organizationId: firstOrg?.organization_id ?? null,
      projects: projectRecords
    }
  };
}

export async function requireWorkspace() {
  const context = await getWorkspaceContext();
  if (context.status === "not_configured") redirect("/login?reason=setup");
  if (context.status === "anonymous") redirect("/login");
  if (context.status === "no_membership") redirect("/login?reason=membership");
  return context.member;
}

export function canManageProject(role: string) {
  const normalized = normalizeRole(role);
  return normalized === "platform_owner" || normalized === "project_lead" || normalized === "secretary";
}

export function canReviewResearch(role: string) {
  return canManageProject(role);
}
