import "server-only";
import type { User } from "@supabase/supabase-js";
import { normalizeRole } from "@/lib/domain";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type ApiSupabase = NonNullable<Awaited<ReturnType<typeof createSupabaseServerClient>>>;
export type ApiContext = { supabase: ApiSupabase; user: User };
export type ApiAuthResult =
  | { ok: true; context: ApiContext }
  | { ok: false; status: 401 | 503; error: string };
export type ApiAccessResult =
  | { ok: true; role: string; organizationId: string }
  | { ok: false; status: 403 | 404; error: string };

export async function resolveApiContext(): Promise<ApiAuthResult> {
  const supabase = await createSupabaseServerClient();
  if (!supabase) return { ok: false, status: 503, error: "Authentication is not configured." };
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) return { ok: false, status: 401, error: "Authentication required." };
  return { ok: true, context: { supabase, user } };
}

export async function authorizeProject(context: ApiContext, projectId: string, capability: "read" | "write" | "admin" | "review" = "read"): Promise<ApiAccessResult> {
  const { supabase, user } = context;
  const { data: project } = await supabase.from("projects").select("id, organization_id").eq("id", projectId).maybeSingle();
  if (!project) return { ok: false, status: 404, error: "Project not found." };

  const [{ data: projectMember }, { data: organizationMember }, { data: profile }] = await Promise.all([
    supabase.from("project_members").select("role, status").eq("project_id", projectId).eq("user_id", user.id).maybeSingle(),
    supabase.from("organization_members").select("role, status").eq("organization_id", project.organization_id).eq("user_id", user.id).maybeSingle(),
    supabase.from("profiles").select("platform_owner").eq("id", user.id).maybeSingle()
  ]);
  const isProjectMember = projectMember?.status === "active" && organizationMember?.status === "active";
  const isPlatformOwner = profile?.platform_owner === true;
  if (!isProjectMember && !isPlatformOwner) return { ok: false, status: 403, error: "Project access denied." };

  const role = isPlatformOwner ? "platform_owner" : normalizeRole(projectMember?.role);
  const administrators = ["platform_owner", "project_lead", "secretary"];
  const writers = [...administrators, "researcher"];
  if (capability === "admin" && !administrators.includes(role)) return { ok: false, status: 403, error: "Administrator permission required." };
  if (capability === "review" && !administrators.includes(role)) return { ok: false, status: 403, error: "Reviewer permission required." };
  if (capability === "write" && !writers.includes(role)) return { ok: false, status: 403, error: "Write permission required." };
  return { ok: true, role, organizationId: project.organization_id };
}

export async function visibleProjectIds(context: ApiContext): Promise<string[]> {
  const { supabase, user } = context;
  const [{ data: memberships }, { data: profile }] = await Promise.all([
    supabase.from("project_members").select("project_id").eq("user_id", user.id).eq("status", "active"),
    supabase.from("profiles").select("platform_owner").eq("id", user.id).maybeSingle()
  ]);
  const ids = new Set((memberships ?? []).map((row) => row.project_id));
  if (profile?.platform_owner) {
    const { data: ownedProjects } = await supabase.from("projects").select("id");
    for (const project of ownedProjects ?? []) ids.add(project.id);
  }
  return [...ids];
}

export async function getActiveOrganization(context: ApiContext) {
  const { data } = await context.supabase.from("organization_members").select("organization_id, role, status").eq("user_id", context.user.id).eq("status", "active").order("joined_at", { ascending: true }).limit(1).maybeSingle();
  return data ?? null;
}

export function mayAdminister(role: string | null | undefined): boolean {
  const normalized = normalizeRole(role);
  return normalized === "platform_owner" || normalized === "project_lead" || normalized === "secretary";
}

export function mayWrite(role: string | null | undefined): boolean {
  return mayAdminister(role) || normalizeRole(role) === "researcher";
}
