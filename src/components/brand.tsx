import Link from "next/link";
import { cn } from "@/lib/utils";

export function BrandMark({ className }: { className?: string }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 40 40" className={cn("h-10 w-10 shrink-0", className)} fill="none">
      <rect x="1" y="1" width="38" height="38" rx="13" fill="#145447" />
      <path d="M12 27.5V13h11.2c4.2 0 6.8 2.1 6.8 5.7 0 2.7-1.6 4.6-4.2 5.3l4.3 3.5h-6.4l-3.6-3.1h-3.1v3.1H12Z" fill="#F5F4EF" />
      <path d="M17 17.4v3.2h5.5c1.5 0 2.2-.5 2.2-1.6 0-1-.7-1.6-2.2-1.6H17Z" fill="#B5D4C6" />
      <path d="M28.8 9.2c2.1 2.5 2.3 4.1.4 5.2-1.5.9-3.4.2-3.4-1.7 0-1.1 1-2.2 3-3.5Z" fill="#C89458" />
    </svg>
  );
}

export function Brand({ compact = false, href = "/dashboard" }: { compact?: boolean; href?: string }) {
  return (
    <Link href={href} className="inline-flex items-center gap-3 rounded-lg" aria-label="Forevit Dairy workspace">
      <BrandMark className={compact ? "h-9 w-9" : "h-10 w-10"} />
      <span className="flex min-w-0 flex-col leading-none">
        <span className={cn("font-semibold tracking-[-0.045em] text-ink", compact ? "text-lg" : "text-[1.3rem]")}>forevit</span>
        {!compact && <span className="mt-1 text-[10px] font-medium uppercase tracking-[0.2em] text-muted">Dairy research</span>}
      </span>
    </Link>
  );
}
