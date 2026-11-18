import { Users } from "lucide-react";
import { InviteMemberForm } from "@/components/workspace/invite-member-form";
import { EmptyState, SectionHeading } from "@/components/ui/empty-state";
import { Badge, Card } from "@/components/ui/primitives";
import { canManageProject, requireWorkspace } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { humanize } from "@/lib/format";

export default async function MembersPage() {
  const member = await requireWorkspace();
  const supabase = await createSupabaseServerClient();
  let rows: { user_id: string; role: string; status: string; full_name: string | null; email: string | null }[] = [];
  if (supabase && member.organizationId) {
    const { data } = await supabase.rpc("get_organization_directory", { p_organization_id: member.organizationId });
    rows = (data ?? []).map((row: { user_id: string; role: string; status: string; display_name: string | null; email: string | null }) => ({ user_id: row.user_id, role: row.role, status: row.status, full_name: row.display_name, email: row.email }));
  }
  const canInvite = canManageProject(member.role);
  const manageableProjects = member.projects.filter((project) => canManageProject(project.role)).map(({ id, name }) => ({ id, name }));
  return <div className="space-y-7"><SectionHeading eyebrow="Access & accountability" title="Members" description="Organization membership establishes role; project membership narrows access to the research spaces a member is authorized to view." action={canInvite ? <InviteMemberForm organizationId={member.organizationId} projects={manageableProjects} /> : undefined} />{rows.length === 0 ? <Card><EmptyState icon={Users} title="No member directory available" description="Member profiles are visible only within your organization scope. Ask an organization administrator to manage invitations." /></Card> : <Card className="overflow-hidden"><div className="overflow-x-auto"><table className="w-full min-w-[540px] text-left"><thead className="bg-[#faf9f5] text-[10px] font-semibold uppercase tracking-[0.15em] text-muted"><tr><th className="px-5 py-3.5 sm:px-6">Member</th><th className="px-4 py-3.5">Role</th><th className="px-4 py-3.5">Status</th><th className="px-5 py-3.5 text-right sm:px-6">Project scope</th></tr></thead><tbody className="divide-y divide-line/80">{rows.map((row) => <tr key={row.user_id}><td className="px-5 py-4 sm:px-6"><p className="text-sm font-medium text-ink">{row.full_name || "Forevit member"}</p><p className="mt-1 text-xs text-muted">{row.email ?? "Email not available"}</p></td><td className="px-4 py-4"><Badge variant="muted">{humanize(row.role)}</Badge></td><td className="px-4 py-4"><Badge variant={row.status === "active" ? "default" : "amber"}>{humanize(row.status)}</Badge></td><td className="px-5 py-4 text-right text-xs text-muted sm:px-6">{member.projects.length} visible project{member.projects.length === 1 ? "" : "s"}</td></tr>)}</tbody></table></div><div className="border-t border-line px-5 py-3 text-[11px] text-muted sm:px-6">Member records are restricted by organization and project policies.</div></Card>}</div>;
}
