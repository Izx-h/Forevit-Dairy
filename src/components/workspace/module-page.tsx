import { SectionHeading } from "@/components/ui/empty-state";
import { RecordTable } from "@/components/workspace/record-table";
import { CreateRecordForm, type CreateKind } from "@/components/workspace/create-record-form";
import type { RecordRow } from "@/lib/domain";

export function ModulePage({ eyebrow, title, description, rows, emptyTitle, emptyDescription, createKind, projectId }: {
  eyebrow: string;
  title: string;
  description: string;
  rows: RecordRow[];
  emptyTitle: string;
  emptyDescription: string;
  createKind?: CreateKind;
  projectId?: string;
}) {
  return <div className="space-y-7"><SectionHeading eyebrow={eyebrow} title={title} description={description} action={createKind ? <CreateRecordForm kind={createKind} projectId={projectId} /> : undefined} /><RecordTable rows={rows} emptyTitle={emptyTitle} emptyDescription={emptyDescription} /></div>;
}
