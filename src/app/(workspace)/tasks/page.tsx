import { ClipboardList, History } from "lucide-react";
import { CreateRecordForm } from "@/components/workspace/create-record-form";
import { EmptyState, SectionHeading } from "@/components/ui/empty-state";
import { Card } from "@/components/ui/primitives";
import { RecordTable } from "@/components/workspace/record-table";
import { requireWorkspace } from "@/lib/auth/session";
import { getOverviewRows } from "@/lib/data/queries";

export default async function TasksPage() {
  const member = await requireWorkspace();
  const rows = await getOverviewRows("tasks", member.projects.map((project) => project.id));
  return <div className="space-y-7"><SectionHeading eyebrow="Accountability" title="Tasks" description="Assignments, due dates, submissions and reviews remain distinct. Overdue state is derived from the due date and current task status." action={<CreateRecordForm kind="task" projectId={member.projects[0]?.id} />} /><div className="grid gap-4 md:grid-cols-2"><Card className="p-4"><div className="flex items-center gap-2 text-xs font-semibold text-ink"><ClipboardList size={15} className="text-pine-700" />Workflow states</div><p className="mt-2 text-[11px] leading-5 text-muted">Not started → in progress → submitted → under review → approved or changes requested.</p></Card><Card className="p-4"><div className="flex items-center gap-2 text-xs font-semibold text-ink"><History size={15} className="text-pine-700" />Complete history</div><p className="mt-2 text-[11px] leading-5 text-muted">Assignments, status transitions, submissions, review comments and timestamps are retained.</p></Card></div>{rows.length ? <RecordTable rows={rows} emptyTitle="" emptyDescription="" /> : <Card><EmptyState icon={ClipboardList} title="No tasks in your scope" description="Create a task for a project. Add assignees, submit work separately from approval, and preserve the review history." /></Card>}</div>;
}
