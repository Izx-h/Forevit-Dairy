import { CalendarDays, ListChecks } from "lucide-react";
import { CreateRecordForm } from "@/components/workspace/create-record-form";
import { EmptyState, SectionHeading } from "@/components/ui/empty-state";
import { Card } from "@/components/ui/primitives";
import { RecordTable } from "@/components/workspace/record-table";
import { requireWorkspace } from "@/lib/auth/session";
import { getOverviewRows } from "@/lib/data/queries";

export default async function MeetingsPage() {
  const member = await requireWorkspace();
  const rows = await getOverviewRows("meetings", member.projects.map((project) => project.id));
  return <div className="space-y-7"><SectionHeading eyebrow="Coordination" title="Meetings & decisions" description="Prepare a project brief from current tasks, lab reviews, knowledge records and decisions. Link each decision to a responsible member and follow-up task." action={<CreateRecordForm kind="meeting" projectId={member.projects[0]?.id} />} /><div className="grid gap-4 md:grid-cols-2"><Card className="p-4"><div className="flex items-center gap-2 text-xs font-semibold text-ink"><CalendarDays size={15} className="text-pine-700" />Meeting record</div><p className="mt-2 text-[11px] leading-5 text-muted">Capture attendees, agenda, location/link and minutes linked to an immutable document version.</p></Card><Card className="p-4"><div className="flex items-center gap-2 text-xs font-semibold text-ink"><ListChecks size={15} className="text-pine-700" />Decisions carry forward</div><p className="mt-2 text-[11px] leading-5 text-muted">Record decision text, responsible member and an optional task created to complete it.</p></Card></div>{rows.length ? <RecordTable rows={rows} emptyTitle="" emptyDescription="" /> : <Card><EmptyState icon={CalendarDays} title="No meetings scheduled" description="Schedule a project meeting and record its attendees, agenda, minutes and decisions." /></Card>}</div>;
}
