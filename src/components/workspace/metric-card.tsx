import type { LucideIcon } from "lucide-react";
import { ArrowUpRight } from "lucide-react";
import { Card } from "@/components/ui/primitives";

export function MetricCard({ label, value, detail, icon: Icon, href }: { label: string; value: number; detail: string; icon: LucideIcon; href: string }) {
  return (
    <Card className="group p-5 transition-transform hover:-translate-y-0.5 sm:p-5">
      <div className="flex items-start justify-between"><span className="grid h-10 w-10 place-items-center rounded-xl bg-pine-50 text-pine-700"><Icon size={18} strokeWidth={1.8} /></span><a href={href} className="rounded-full p-1.5 text-muted opacity-70 transition hover:bg-paper hover:text-pine-700" aria-label={`Open ${label}`}><ArrowUpRight size={15} /></a></div>
      <div className="mt-5 flex items-end justify-between gap-3"><div><p className="text-3xl font-semibold tracking-[-0.06em] text-ink">{value.toLocaleString("en")}</p><p className="mt-1 text-xs font-medium text-muted">{label}</p></div><p className="max-w-[100px] text-right text-[10px] leading-4 text-muted">{detail}</p></div>
    </Card>
  );
}
