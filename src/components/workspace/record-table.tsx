import { FileSearch2 } from "lucide-react";
import { EmptyState } from "@/components/ui/empty-state";
import { Badge, Card } from "@/components/ui/primitives";
import { formatShortDate, humanize } from "@/lib/format";
import type { RecordRow } from "@/lib/domain";

export function RecordTable({ rows, emptyTitle, emptyDescription }: { rows: RecordRow[]; emptyTitle: string; emptyDescription: string }) {
  if (rows.length === 0) return <Card><EmptyState icon={FileSearch2} title={emptyTitle} description={emptyDescription} /></Card>;
  return (
    <Card className="overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[580px] border-collapse text-left">
          <thead className="bg-[#faf9f5] text-[10px] font-semibold uppercase tracking-[0.15em] text-muted">
            <tr><th scope="col" className="px-5 py-3.5 sm:px-6">Record</th><th scope="col" className="px-4 py-3.5">Status</th><th scope="col" className="px-4 py-3.5">Category</th><th scope="col" className="px-5 py-3.5 text-right sm:px-6">Updated</th></tr>
          </thead>
          <tbody className="divide-y divide-line/80">
            {rows.map((row) => <tr key={row.id} className="transition-colors hover:bg-[#fcfbf8]">
              <th scope="row" className="max-w-[360px] px-5 py-4 text-left font-medium sm:px-6"><p className="truncate text-sm text-ink">{row.title}</p>{row.subtitle && <p className="mt-1 max-w-[340px] truncate text-xs font-normal text-muted">{row.subtitle}</p>}</th>
              <td className="px-4 py-4">{row.status ? <Badge variant={row.status === "approved" || row.status === "published" ? "default" : row.status === "changes_requested" || row.status === "overdue" ? "danger" : row.status === "submitted" || row.status === "under_review" ? "amber" : "muted"}>{humanize(row.status)}</Badge> : <span className="text-xs text-muted">—</span>}</td>
              <td className="px-4 py-4 text-xs text-muted">{row.category ? humanize(row.category) : "—"}</td>
              <td className="px-5 py-4 text-right text-xs text-muted sm:px-6">{formatShortDate(row.updatedAt)}</td>
            </tr>)}
          </tbody>
        </table>
      </div>
      <div className="border-t border-line px-5 py-3 text-[11px] text-muted sm:px-6">Showing {rows.length} authorized records</div>
    </Card>
  );
}
