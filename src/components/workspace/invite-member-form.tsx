"use client";

import { useState } from "react";
import { MailPlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/primitives";
import { Input } from "@/components/ui/input";

const roles = [
  ["viewer", "Viewer"],
  ["researcher", "Researcher"],
  ["secretary", "Secretary"],
  ["project_lead", "Project Lead"]
] as const;

type ProjectOption = { id: string; name: string };

export function InviteMemberForm({ organizationId, projects }: { organizationId?: string | null; projects: ProjectOption[] }) {
  const [open, setOpen] = useState(false);
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState("");
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const values = Object.fromEntries(new FormData(form).entries());
    const projectId = String(values.project_id ?? "");
    const projectRole = String(values.project_role ?? "");
    setPending(true); setMessage("");
    const response = await fetch("/api/v1/invitations", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ ...values, organization_id: organizationId, project_id: projectId || undefined, project_role: projectId ? projectRole : undefined }) });
    const result = await response.json().catch(() => ({}));
    setPending(false);
    if (!response.ok) { setMessage(result.error ?? "Invitation could not be sent."); return; }
    form.reset(); setMessage("Invitation sent. The invited member will receive a one-time Supabase Auth email.");
  }
  return <div><Button onClick={() => setOpen(!open)} aria-expanded={open} aria-controls="invite-member"><MailPlus size={16} />Invite member</Button>{open && <Card id="invite-member" className="mt-3 w-[min(92vw,440px)] p-5 shadow-soft sm:p-6"><h2 className="text-sm font-semibold text-ink">Invite to the organization</h2><p className="mt-1 text-xs leading-5 text-muted">An organization-only invitation creates no project access. Choose a project explicitly when project membership should be activated on acceptance.</p><form onSubmit={submit} className="mt-4 space-y-4"><label className="block space-y-2"><span className="text-xs font-medium text-ink">Email address</span><Input name="email" type="email" required maxLength={320} autoComplete="email" /></label><label className="block space-y-2"><span className="text-xs font-medium text-ink">Organization role</span><select name="role" className="h-10 w-full rounded-xl border border-line bg-white px-3 text-sm">{roles.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label><label className="block space-y-2"><span className="text-xs font-medium text-ink">Project access (optional)</span><select name="project_id" defaultValue="" className="h-10 w-full rounded-xl border border-line bg-white px-3 text-sm"><option value="">Organization only — no project access</option>{projects.map((project) => <option key={project.id} value={project.id}>{project.name}</option>)}</select></label><label className="block space-y-2"><span className="text-xs font-medium text-ink">Project role</span><select name="project_role" defaultValue="viewer" className="h-10 w-full rounded-xl border border-line bg-white px-3 text-sm">{roles.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>{message && <p role="status" className="rounded-lg bg-paper px-3 py-2 text-xs leading-5 text-muted">{message}</p>}<div className="flex justify-end gap-2"><Button type="button" variant="ghost" onClick={() => setOpen(false)}>Close</Button><Button type="submit" disabled={pending}>{pending ? "Sending…" : "Send invitation"}</Button></div></form></Card>}</div>;
}
