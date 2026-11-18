import { FileText, Search } from "lucide-react";
import { CreateRecordForm } from "@/components/workspace/create-record-form";
import { EmptyState, SectionHeading } from "@/components/ui/empty-state";
import { Card } from "@/components/ui/primitives";
import { RecordTable } from "@/components/workspace/record-table";
import { requireWorkspace } from "@/lib/auth/session";
import { getOverviewRows } from "@/lib/data/queries";

export default async function DocumentsPage() {
  const member = await requireWorkspace();
  const rows = await getOverviewRows("documents", member.projects.map((project) => project.id));
  return <div className="space-y-7"><SectionHeading eyebrow="Project knowledge" title="Knowledge library" description="Find papers, procedures, results, formulations, reports, meeting minutes and technical material within your authorized project scope." action={<CreateRecordForm kind="document" projectId={member.projects[0]?.id} />} /><div className="grid gap-4 md:grid-cols-3"><Card className="p-4"><div className="flex items-center gap-2 text-xs font-semibold text-ink"><FileText size={15} className="text-pine-700" />Versioned sources</div><p className="mt-2 text-[11px] leading-5 text-muted">Original file versions remain authoritative; edits create traceable versions.</p></Card><Card className="p-4"><div className="flex items-center gap-2 text-xs font-semibold text-ink"><Search size={15} className="text-pine-700" />Search by metadata</div><p className="mt-2 text-[11px] leading-5 text-muted">Filter by title, category, tags and project association.</p></Card><Card className="p-4"><div className="flex items-center gap-2 text-xs font-semibold text-ink">Permission-filtered retrieval</div><p className="mt-2 text-[11px] leading-5 text-muted">Text chunks and citations inherit project visibility; similarity is never an access check.</p></Card></div>{rows.length ? <RecordTable rows={rows} emptyTitle="" emptyDescription="" /> : <Card><EmptyState icon={FileText} title="No documents in your scope" description="Add document metadata for an authorized project. Private file upload, version checksums and signed links are handled by the server after provider configuration." /></Card>}</div>;
}
