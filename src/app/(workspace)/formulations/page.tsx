import { Beaker, GitBranch } from "lucide-react";
import { CreateRecordForm } from "@/components/workspace/create-record-form";
import { EmptyState, SectionHeading } from "@/components/ui/empty-state";
import { Card } from "@/components/ui/primitives";
import { RecordTable } from "@/components/workspace/record-table";
import { requireWorkspace } from "@/lib/auth/session";
import { getOverviewRows } from "@/lib/data/queries";

export default async function FormulationsPage() {
  const member = await requireWorkspace();
  const rows = await getOverviewRows("formulations", member.projects.map((project) => project.id));
  return <div className="space-y-7"><SectionHeading eyebrow="Product concepts" title="Formulations" description="Maintain named product concepts with immutable, numbered versions. Link ingredients to their declared basis and trials to the exact formulation and laboratory test." action={<CreateRecordForm kind="formulation" projectId={member.projects[0]?.id} />} /><Card className="grid gap-4 p-5 md:grid-cols-2 sm:p-6"><div className="flex gap-3"><span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-pine-50 text-pine-700"><Beaker size={17} /></span><div><h2 className="text-sm font-semibold text-ink">Versioned concepts</h2><p className="mt-1 text-xs leading-5 text-muted">A new formulation revision preserves the original version and records the rationale.</p></div></div><div className="flex gap-3"><span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-amber-50 text-amber-700"><GitBranch size={17} /></span><div><h2 className="text-sm font-semibold text-ink">Comparable trials</h2><p className="mt-1 text-xs leading-5 text-muted">Trials connect a specific formulation version to test records and observations.</p></div></div></Card>{rows.length ? <RecordTable rows={rows} emptyTitle="" emptyDescription="" /> : <Card><EmptyState icon={Beaker} title="No formulation concepts yet" description="Create a product concept to begin preserving numbered versions, ingredient quantities, basis and linked trials." /></Card>}</div>;
}
