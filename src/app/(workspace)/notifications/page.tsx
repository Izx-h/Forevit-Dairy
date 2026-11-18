import { Bell, MessageCircleMore } from "lucide-react";
import { EmptyState, SectionHeading } from "@/components/ui/empty-state";
import { Card } from "@/components/ui/primitives";
import { RecordTable } from "@/components/workspace/record-table";
import { requireWorkspace } from "@/lib/auth/session";
import { getOverviewRows } from "@/lib/data/queries";

export default async function NotificationsPage() {
  const member = await requireWorkspace();
  const rows = await getOverviewRows("notifications", member.projects.map((project) => project.id), member.id);
  return <div className="space-y-7"><SectionHeading eyebrow="Activity alerts" title="Notifications" description="In-app notices are the canonical record. Optional WhatsApp delivery is separate, consent-based and never replaces in-app history." /><Card className="grid gap-4 p-5 md:grid-cols-2 sm:p-6"><div className="flex gap-3"><span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-pine-50 text-pine-700"><Bell size={17} /></span><div><h2 className="text-sm font-semibold text-ink">In-app notifications</h2><p className="mt-1 text-xs leading-5 text-muted">Task, laboratory, document, formulation, meeting and report events appear here.</p></div></div><div className="flex gap-3"><span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-amber-50 text-amber-700"><MessageCircleMore size={17} /></span><div><h2 className="text-sm font-semibold text-ink">WhatsApp is opt-in</h2><p className="mt-1 text-xs leading-5 text-muted">Provider delivery requires recorded consent, event preferences and verified callback configuration.</p></div></div></Card>{rows.length ? <RecordTable rows={rows} emptyTitle="" emptyDescription="" /> : <Card><EmptyState icon={Bell} title="No notifications yet" description="Authorized activity notices will be listed here. Failed optional WhatsApp delivery does not remove an in-app notice." /></Card>}</div>;
}
