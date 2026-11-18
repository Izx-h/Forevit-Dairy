import Link from "next/link";
import { ArrowRight, Bell, CalendarClock, CheckCheck, ClipboardList, FileText, FlaskConical, Inbox, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge, Card, CardHeader, CardTitle } from "@/components/ui/primitives";
import { EmptyState, SectionHeading } from "@/components/ui/empty-state";
import { MetricCard } from "@/components/workspace/metric-card";
import { requireWorkspace } from "@/lib/auth/session";
import { getDashboardData } from "@/lib/data/queries";
import { formatDateTime, formatShortDate, humanize } from "@/lib/format";

export default async function DashboardPage() {
  const member = await requireWorkspace();
  const data = await getDashboardData(member.projects, member.id);
  const firstName = member.fullName.split(" ")[0] || "there";

  return <div className="space-y-8">
    <SectionHeading eyebrow="Workspace overview" title={`Good to see you, ${firstName}.`} description="A clear view of the work in motion, the records that need attention, and what is coming next." action={<Button asChild variant="secondary"><Link href="/meetings"><CalendarClock size={16} />Prepare a meeting brief</Link></Button>} />

    {!data && member.projects.length === 0 ? <Card><EmptyState icon={Inbox} title="No active project membership" description="Your account is signed in, but no project is currently available to you. Ask a project administrator to add you to a project." /></Card> : <>
      {data && <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        <MetricCard label="Open tasks" value={data.metrics.openTasks} detail="Not started or underway" icon={ClipboardList} href="/tasks" />
        <MetricCard label="Work to review" value={data.metrics.workForReview} detail="Submitted or under review" icon={CheckCheck} href="/tasks" />
        <MetricCard label="Lab reviews" value={data.metrics.labResultsForReview} detail="Result revisions awaiting review" icon={FlaskConical} href="/laboratory" />
        <MetricCard label="New knowledge" value={data.metrics.recentDocuments} detail="Documents added in the last 30 days" icon={FileText} href="/documents" />
        <MetricCard label="Unread notices" value={data.metrics.unreadNotifications} detail="In-app notifications" icon={Bell} href="/notifications" />
      </div>}

      <div className="grid gap-5 xl:grid-cols-[1.25fr_.75fr]">
        <Card className="overflow-hidden">
          <CardHeader className="flex-row items-center justify-between border-b border-line px-5 py-4 sm:px-6"><div><CardTitle>Work in motion</CardTitle><p className="mt-1 text-xs text-muted">Recent tasks from your authorized projects</p></div><Button asChild variant="ghost" size="sm"><Link href="/tasks">All tasks <ArrowRight size={14} /></Link></Button></CardHeader>
          {(data?.tasks.length ?? 0) === 0 ? <EmptyState icon={ClipboardList} title="No tasks to show" description="Tasks assigned to your project memberships will appear here." /> : <div className="divide-y divide-line/80">{data?.tasks.map((task) => <div key={task.id} className="flex items-center justify-between gap-4 px-5 py-4 sm:px-6"><div className="min-w-0"><p className="truncate text-sm font-medium text-ink">{task.title}</p><p className="mt-1 text-[11px] text-muted">{task.dueAt ? `Due ${formatShortDate(task.dueAt)}` : "No due date"} · {humanize(task.priority)}</p></div><Badge variant={task.status === "submitted" || task.status === "under_review" ? "amber" : task.status === "changes_requested" ? "danger" : "muted"}>{humanize(task.status)}</Badge></div>)}</div>}
        </Card>

        <Card className="overflow-hidden">
          <CardHeader className="flex-row items-center justify-between border-b border-line px-5 py-4 sm:px-6"><div><CardTitle>Meeting brief</CardTitle><p className="mt-1 text-xs text-muted">Upcoming sessions from your projects</p></div><span className="grid h-8 w-8 place-items-center rounded-lg bg-amber-50 text-amber-700"><CalendarClock size={16} /></span></CardHeader>
          {(data?.meetings.length ?? 0) === 0 ? <EmptyState icon={CalendarClock} title="No upcoming meetings" description="Scheduled project meetings will appear here with their agenda and linked decisions." /> : <div className="divide-y divide-line/80">{data?.meetings.map((meeting) => <div key={meeting.id} className="px-5 py-4 sm:px-6"><div className="flex items-start gap-3"><div className="grid min-w-10 place-items-center rounded-lg bg-paper px-2 py-2 text-center"><span className="text-[9px] font-semibold uppercase tracking-wider text-muted">{new Intl.DateTimeFormat("en", { month: "short" }).format(new Date(meeting.meetingAt))}</span><span className="text-sm font-semibold text-ink">{new Intl.DateTimeFormat("en", { day: "2-digit" }).format(new Date(meeting.meetingAt))}</span></div><div className="min-w-0"><p className="text-sm font-medium text-ink">{meeting.title}</p><p className="mt-1 text-[11px] text-muted">{formatDateTime(meeting.meetingAt)}{meeting.locationOrLink ? ` · ${meeting.locationOrLink}` : ""}</p></div></div></div>)}</div>}
          <div className="border-t border-line bg-[#faf9f5] px-5 py-3 sm:px-6"><Link href="/meetings" className="inline-flex items-center gap-1 text-xs font-medium text-pine-700 hover:underline">View meetings <ArrowRight size={13} /></Link></div>
        </Card>
      </div>

      <div className="grid gap-5 xl:grid-cols-[.8fr_1.2fr]">
        <Card className="overflow-hidden">
          <CardHeader className="border-b border-line px-5 py-4 sm:px-6"><CardTitle>Project spaces</CardTitle><p className="mt-1 text-xs text-muted">Your current access scope</p></CardHeader>
          {member.projects.length === 0 ? <EmptyState icon={Inbox} title="No projects yet" description="You are signed in, but no project membership is active." /> : <div className="divide-y divide-line/80">{member.projects.map((project) => <div key={project.id} className="flex items-center justify-between gap-4 px-5 py-4 sm:px-6"><div className="min-w-0"><p className="truncate text-sm font-medium text-ink">{project.name}</p><p className="mt-1 truncate text-xs text-muted">{project.description || "No description provided"}</p></div><Badge variant="muted">{humanize(project.role)}</Badge></div>)}</div>}
        </Card>
        <Card className="overflow-hidden">
          <CardHeader className="flex-row items-center justify-between border-b border-line px-5 py-4 sm:px-6"><div><CardTitle>Recent activity</CardTitle><p className="mt-1 text-xs text-muted">Traceable changes across your projects</p></div><span className="grid h-8 w-8 place-items-center rounded-lg bg-pine-50 text-pine-700"><Sparkles size={16} /></span></CardHeader>
          {(data?.activities.length ?? 0) === 0 ? <EmptyState icon={Sparkles} title="No recent activity" description="Meaningful project changes will appear here with their record type and timestamp." /> : <div className="divide-y divide-line/80">{data?.activities.map((activity) => <div key={activity.id} className="flex items-start gap-3 px-5 py-4 sm:px-6"><span className="mt-1 h-2 w-2 shrink-0 rounded-full bg-pine-500" /><div className="min-w-0 flex-1"><p className="text-xs font-medium text-ink">{humanize(activity.action)} <span className="font-normal text-muted">· {humanize(activity.entityType)}</span></p><p className="mt-1 text-[10px] text-muted">{formatDateTime(activity.createdAt)}</p></div></div>)}</div>}
        </Card>
      </div>
    </>}
  </div>;
}
