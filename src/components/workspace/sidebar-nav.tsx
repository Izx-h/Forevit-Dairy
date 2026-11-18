"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Activity, Archive, Beaker, Bell, BriefcaseBusiness, CalendarDays, ClipboardList, FlaskConical, FolderOpen, Home, Settings2, Sparkles, Users } from "lucide-react";
import { cn } from "@/lib/utils";

const navigation = [
  { href: "/dashboard", label: "Overview", icon: Home },
  { href: "/projects", label: "Projects", icon: BriefcaseBusiness },
  { href: "/laboratory", label: "Laboratory", icon: FlaskConical },
  { href: "/documents", label: "Knowledge library", icon: FolderOpen },
  { href: "/formulations", label: "Formulations", icon: Beaker },
  { href: "/tasks", label: "Tasks", icon: ClipboardList },
  { href: "/meetings", label: "Meetings", icon: CalendarDays },
  { href: "/ai", label: "Research assistant", icon: Sparkles },
  { href: "/notifications", label: "Notifications", icon: Bell },
  { href: "/members", label: "Members", icon: Users },
  { href: "/settings", label: "Settings", icon: Settings2 }
];

export function SidebarNav() {
  const pathname = usePathname();
  return (
    <nav aria-label="Workspace navigation" className="space-y-1">
      {navigation.map(({ href, label, icon: Icon }) => {
        const active = pathname === href || pathname.startsWith(`${href}/`);
        return (
          <Link key={href} href={href} aria-current={active ? "page" : undefined}
            className={cn("group flex items-center gap-3 rounded-xl px-3 py-2.5 text-[13px] font-medium transition-colors", active ? "bg-pine-50 text-pine-800" : "text-muted hover:bg-white/80 hover:text-ink")}>
            <Icon size={17} strokeWidth={active ? 2 : 1.7} className={cn("shrink-0", active ? "text-pine-700" : "text-muted group-hover:text-ink")} />
            <span>{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}

export function MobileNav() {
  const pathname = usePathname();
  const items = navigation.filter(({ href }) => ["/dashboard", "/laboratory", "/tasks", "/documents", "/meetings"].includes(href));
  return (
    <nav aria-label="Main navigation" className="fixed inset-x-0 bottom-0 z-40 grid grid-cols-5 border-t border-line bg-surface/95 px-2 pb-[env(safe-area-inset-bottom)] pt-2 backdrop-blur-xl md:hidden">
      {items.map(({ href, label, icon: Icon }) => {
        const active = pathname === href || pathname.startsWith(`${href}/`);
        return <Link key={href} href={href} aria-current={active ? "page" : undefined} className={cn("flex flex-col items-center gap-1 rounded-lg py-1.5 text-[10px] font-medium", active ? "text-pine-700" : "text-muted")}><Icon size={18} strokeWidth={active ? 2 : 1.7} /><span>{label}</span></Link>;
      })}
    </nav>
  );
}

export function WorkspaceRailNote() {
  return <div className="rounded-2xl border border-line bg-white/70 p-4"><div className="flex items-center gap-2 text-xs font-semibold text-ink"><Activity size={14} className="text-pine-700" />Research integrity</div><p className="mt-2 text-[11px] leading-5 text-muted">Source records stay linked. Corrections are recorded as new revisions.</p><div className="mt-3 flex items-center gap-2 text-[10px] text-muted"><Archive size={12} />Traceable workspace</div></div>;
}
