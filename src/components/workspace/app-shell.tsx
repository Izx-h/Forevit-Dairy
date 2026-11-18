import { Bell, ChevronDown, CircleHelp, Search } from "lucide-react";
import { Brand } from "@/components/brand";
import { SidebarNav, MobileNav, WorkspaceRailNote } from "@/components/workspace/sidebar-nav";
import { signOutAction } from "@/lib/auth/actions";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/primitives";
import type { WorkspaceMember } from "@/lib/domain";

function initials(name: string) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("") || "FD";
}

export function AppShell({ member, children }: { member: WorkspaceMember; children: React.ReactNode }) {
  const activeProject = member.projects[0];
  return (
    <div className="min-h-screen bg-paper">
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-[260px] flex-col border-r border-line bg-[#f8f7f2] px-5 pb-5 pt-6 md:flex">
        <div className="px-1"><Brand /></div>
        <div className="mt-8 rounded-2xl border border-line bg-surface px-3.5 py-3">
          <div className="text-[9px] font-semibold uppercase tracking-[0.18em] text-muted">Current project</div>
          <div className="mt-2 flex items-center justify-between gap-2">
            <div className="min-w-0"><p className="truncate text-sm font-semibold text-ink">{activeProject?.name ?? "No project yet"}</p><p className="mt-0.5 truncate text-[11px] text-muted">{activeProject?.description ?? "Your memberships appear here"}</p></div>
            <ChevronDown size={15} className="shrink-0 text-muted" />
          </div>
        </div>
        <p className="mb-2 mt-8 px-3 text-[9px] font-semibold uppercase tracking-[0.18em] text-muted">Workspace</p>
        <div className="min-h-0 flex-1 overflow-y-auto"><SidebarNav /></div>
        <WorkspaceRailNote />
      </aside>

      <div className="min-h-screen md:pl-[260px]">
        <header className="sticky top-0 z-20 border-b border-line bg-paper/90 backdrop-blur-xl">
          <div className="flex h-[68px] items-center justify-between gap-4 px-4 sm:px-7 lg:px-9">
            <div className="flex min-w-0 items-center gap-3 md:hidden"><Brand compact /><span className="hidden h-5 w-px bg-line sm:block" /><span className="hidden truncate text-xs text-muted sm:block">{activeProject?.name ?? "Workspace"}</span></div>
            <div className="hidden min-w-0 items-center gap-2 text-sm text-muted md:flex"><span className="font-medium text-ink">Forevit workspace</span><span aria-hidden="true">/</span><span className="truncate">{activeProject?.name ?? "Research group"}</span></div>
            <div className="flex items-center gap-2">
              <Button variant="ghost" size="icon" aria-label="Search workspace" className="hidden sm:inline-flex"><Search size={18} /></Button>
              <Button variant="ghost" size="icon" aria-label="Notifications" asChild><a href="/notifications"><Bell size={18} /></a></Button>
              <Button variant="ghost" size="icon" aria-label="Help"><CircleHelp size={18} /></Button>
              <div className="ml-1 flex items-center gap-2 border-l border-line pl-3">
                <div className="grid h-9 w-9 place-items-center rounded-full bg-pine-100 text-xs font-semibold text-pine-800" aria-hidden="true">{initials(member.fullName)}</div>
                <div className="hidden min-w-0 lg:block"><p className="max-w-36 truncate text-xs font-semibold text-ink">{member.fullName}</p><p className="mt-0.5 text-[10px] text-muted">{member.role.replaceAll("_", " ")}</p></div>
                <form action={signOutAction} className="hidden lg:block"><button type="submit" className="rounded-lg px-2 py-1 text-[11px] font-medium text-muted hover:bg-white hover:text-ink">Sign out</button></form>
              </div>
            </div>
          </div>
          {member.projects.length > 1 && <div className="border-t border-line/70 px-4 py-2 md:hidden"><Badge variant="muted">{member.projects.length} projects</Badge></div>}
        </header>
        <main id="main-content" className="mx-auto w-full max-w-[1440px] px-4 pb-24 pt-7 sm:px-7 sm:pt-9 lg:px-10 lg:pt-10 md:pb-12">{children}</main>
      </div>
      <MobileNav />
    </div>
  );
}
