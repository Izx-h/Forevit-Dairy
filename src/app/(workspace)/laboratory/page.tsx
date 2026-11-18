import { FlaskConical, Microscope } from "lucide-react";
import { CreateRecordForm } from "@/components/workspace/create-record-form";
import { EmptyState, SectionHeading } from "@/components/ui/empty-state";
import { Card } from "@/components/ui/primitives";
import { RecordTable } from "@/components/workspace/record-table";
import { requireWorkspace } from "@/lib/auth/session";
import { getOverviewRows } from "@/lib/data/queries";

export default async function LaboratoryPage() {
  const member = await requireWorkspace();
  const projectIds = member.projects.map((project) => project.id);
  const [samples, tests] = await Promise.all([getOverviewRows("samples", projectIds), getOverviewRows("lab_tests", projectIds)]);
  const projectId = member.projects[0]?.id;
  return <div className="space-y-8"><SectionHeading eyebrow="Research records" title="Laboratory" description="Keep samples, procedures, test assignments, results and review history linked. Record units and methods exactly as entered; this workspace does not provide processing or food-safety guidance." /><section className="space-y-4"><div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h2 className="text-base font-semibold text-ink">Sample register</h2><p className="mt-1 text-xs text-muted">Project-scoped sample identity and provenance</p></div><CreateRecordForm kind="sample" projectId={projectId} /></div><RecordTable rows={samples} emptyTitle="No samples registered" emptyDescription="Register a sample to begin linking planned laboratory work to its provenance." /></section><section className="space-y-4"><div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h2 className="text-base font-semibold text-ink">Laboratory tests</h2><p className="mt-1 text-xs text-muted">Planned and performed work with exact procedure versions</p></div><CreateRecordForm kind="lab-test" projectId={projectId} /></div>{tests.length ? <RecordTable rows={tests} emptyTitle="" emptyDescription="" /> : <Card><EmptyState icon={Microscope} title="No tests planned" description="Create a test linked to a registered sample, objective, assigned researchers and exact procedure version." /></Card>}</section><Card className="border-amber-100 bg-amber-50/60 p-4 sm:p-5"><div className="flex items-start gap-3"><FlaskConical size={17} className="mt-0.5 shrink-0 text-amber-700" /><p className="text-xs leading-5 text-amber-800">Scientific records preserve observations and methods. The platform does not validate experimental values or certify product safety.</p></div></Card></div>;
}
