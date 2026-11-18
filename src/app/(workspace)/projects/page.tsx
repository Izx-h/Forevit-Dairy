import { BriefcaseBusiness } from "lucide-react";
import { CreateProjectForm } from "@/components/workspace/create-project-form";
import { SectionHeading } from "@/components/ui/empty-state";
import { Badge, Card } from "@/components/ui/primitives";
import { EmptyState } from "@/components/ui/empty-state";
import { requireWorkspace } from "@/lib/auth/session";
import { humanize } from "@/lib/format";

export default async function ProjectsPage() {
  const member = await requireWorkspace();
  return <div className="space-y-7"><SectionHeading eyebrow="Research spaces" title="Projects" description="Project-scoped workspaces keep membership, records and approvals within the right research context." action={<CreateProjectForm />} />{member.projects.length === 0 ? <Card><EmptyState icon={BriefcaseBusiness} title="No projects in your scope" description="You do not currently have an active project membership. An organization administrator can add a project or invite you to one." /></Card> : <div className="grid gap-4 lg:grid-cols-2">{member.projects.map((project) => <Card key={project.id} className="p-5 sm:p-6"><div className="flex items-start justify-between gap-4"><div className="min-w-0"><p className="text-[10px] font-semibold uppercase tracking-[0.18em] text-pine-700">Research project</p><h2 className="mt-2 text-lg font-semibold tracking-[-0.03em] text-ink">{project.name}</h2><p className="mt-2 text-sm leading-6 text-muted">{project.description || "No project description has been added."}</p></div><span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-pine-50 text-pine-700"><BriefcaseBusiness size={18} /></span></div><div className="mt-6 flex items-center justify-between border-t border-line pt-4"><Badge variant="muted">{humanize(project.role)}</Badge><Badge variant={project.status === "active" ? "default" : "muted"}>{humanize(project.status)}</Badge></div></Card>)}</div>}</div>;
}
