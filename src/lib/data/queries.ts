import "server-only";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { ActivityItem, DashboardMetrics, MeetingItem, RecordRow, TaskItem, WorkspaceProject } from "@/lib/domain";

export interface DashboardData {
  metrics: DashboardMetrics;
  activities: ActivityItem[];
  tasks: TaskItem[];
  meetings: MeetingItem[];
  projects: WorkspaceProject[];
}

export async function getDashboardData(projects: WorkspaceProject[], userId: string): Promise<DashboardData | null> {
  const supabase = await createSupabaseServerClient();
  if (!supabase) return null;
  const projectIds = projects.map((project) => project.id);
  if (projectIds.length === 0) return null;

  const [openTasks, reviewTasks, labReviews, recentDocuments, unreadNotifications, activityResult, taskResult, meetingResult] = await Promise.all([
    supabase.from("tasks").select("id", { count: "exact", head: true }).in("project_id", projectIds).in("status", ["not_started", "in_progress", "changes_requested"]),
    supabase.from("tasks").select("id", { count: "exact", head: true }).in("project_id", projectIds).in("status", ["submitted", "under_review"]),
    supabase.from("lab_tests").select("id", { count: "exact", head: true }).in("project_id", projectIds).in("status", ["submitted", "under_review"]),
    supabase.from("documents").select("id", { count: "exact", head: true }).in("project_id", projectIds).gte("created_at", new Date(Date.now() - 30 * 86400000).toISOString()),
    supabase.from("notifications").select("id", { count: "exact", head: true }).eq("recipient_id", userId).is("read_at", null),
    supabase.from("activity_logs").select("id, action, entity_type, occurred_at, project_id").in("project_id", projectIds).order("occurred_at", { ascending: false }).limit(6),
    supabase.from("tasks").select("id, title, status, priority, due_at, project_id, updated_at").in("project_id", projectIds).not("status", "eq", "approved").order("updated_at", { ascending: false }).limit(5),
    supabase.from("meetings").select("id, title, starts_at, location_or_link").in("project_id", projectIds).gte("starts_at", new Date().toISOString()).order("starts_at", { ascending: true }).limit(4)
  ]);

  const activities = (activityResult.data ?? []).map((item) => ({
    id: item.id,
    action: item.action,
    entityType: item.entity_type,
    createdAt: item.occurred_at,
    projectId: item.project_id
  }));
  const tasks = (taskResult.data ?? []).map((item) => ({
    id: item.id,
    title: item.title,
    status: item.status,
    priority: item.priority,
    dueAt: item.due_at,
    projectId: item.project_id,
    updatedAt: item.updated_at
  })) as TaskItem[];
  const meetings = (meetingResult.data ?? []).map((item) => ({
    id: item.id,
    title: item.title,
    meetingAt: item.starts_at,
    locationOrLink: item.location_or_link
  }));

  return {
    metrics: {
      openTasks: openTasks.count ?? 0,
      workForReview: reviewTasks.count ?? 0,
      labResultsForReview: labReviews.count ?? 0,
      recentDocuments: recentDocuments.count ?? 0,
      unreadNotifications: unreadNotifications.count ?? 0
    },
    activities: activities as ActivityItem[],
    tasks,
    meetings,
    projects
  };
}

function normalizeOverviewRows(rows: readonly unknown[]): RecordRow[] {
  return rows.map((value) => {
    const row = value as Record<string, unknown>;
    return {
      id: String(row.id),
      title: String(row.title ?? row.name ?? row.test_name ?? row.sample_code ?? row.product_name ?? "Untitled record"),
      status: typeof row.status === "string" ? row.status : null,
      category: typeof row.category === "string" ? row.category : typeof row.sample_type === "string" ? row.sample_type : null,
      subtitle: typeof row.description === "string" ? row.description : typeof row.objective === "string" ? row.objective : typeof row.body === "string" ? row.body : null,
      updatedAt: typeof row.updated_at === "string" ? row.updated_at : typeof row.created_at === "string" ? row.created_at : typeof row.starts_at === "string" ? row.starts_at : null
    };
  });
}

export async function getOverviewRows(kind: "tasks" | "samples" | "lab_tests" | "documents" | "formulations" | "meetings" | "notifications", projectIds: string[], userId?: string): Promise<RecordRow[]> {
  const supabase = await createSupabaseServerClient();
  if (!supabase || (projectIds.length === 0 && kind !== "notifications")) return [];
  if (kind === "notifications" && !userId) return [];

  let rows: readonly unknown[] = [];
  if (kind === "tasks") {
    const { data, error } = await supabase.from("tasks").select("id, title, status, priority, description, created_at, updated_at").in("project_id", projectIds).order("updated_at", { ascending: false }).limit(30);
    if (error || !data) return [];
    rows = data;
  } else if (kind === "samples") {
    const { data, error } = await supabase.from("samples").select("id, sample_code, sample_type, source_description, created_at").in("project_id", projectIds).order("created_at", { ascending: false }).limit(30);
    if (error || !data) return [];
    rows = data;
  } else if (kind === "lab_tests") {
    const { data, error } = await supabase.from("lab_tests").select("id, title, objective, status, planned_at, created_at").in("project_id", projectIds).order("created_at", { ascending: false }).limit(30);
    if (error || !data) return [];
    rows = data;
  } else if (kind === "documents") {
    const { data, error } = await supabase.from("documents").select("id, title, category, description, created_at").in("project_id", projectIds).order("created_at", { ascending: false }).limit(30);
    if (error || !data) return [];
    rows = data;
  } else if (kind === "formulations") {
    const { data, error } = await supabase.from("formulations").select("id, name, description, updated_at, created_at").in("project_id", projectIds).order("updated_at", { ascending: false }).limit(30);
    if (error || !data) return [];
    rows = data;
  } else if (kind === "meetings") {
    const { data, error } = await supabase.from("meetings").select("id, title, starts_at, agenda, created_at").in("project_id", projectIds).order("starts_at", { ascending: true }).limit(30);
    if (error || !data) return [];
    rows = data;
  } else {
    const { data, error } = await supabase.from("notifications").select("id, title, body, event_type, created_at, read_at").eq("recipient_id", userId as string).order("created_at", { ascending: false }).limit(30);
    if (error || !data) return [];
    rows = data;
  }
  return normalizeOverviewRows(rows);
}
