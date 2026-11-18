export type OrganizationRole = "platform_owner" | "project_lead" | "secretary" | "researcher" | "viewer";
export type ProjectRole = "project_lead" | "secretary" | "researcher" | "viewer";
export type WorkspaceRole = OrganizationRole | ProjectRole;
export type TaskStatus = "not_started" | "in_progress" | "submitted" | "under_review" | "approved" | "changes_requested";
export type Priority = "low" | "normal" | "high" | "urgent";

export function normalizeRole(value: string | null | undefined): WorkspaceRole {
  const normalized = (value ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (normalized === "platform_owner") return "platform_owner";
  if (normalized === "project_lead") return "project_lead";
  if (normalized === "secretary") return "secretary";
  if (normalized === "researcher") return "researcher";
  return "viewer";
}

export function databaseRole(value: string): "Project Lead" | "Secretary" | "Researcher" | "Viewer" {
  switch (normalizeRole(value)) {
    case "project_lead": return "Project Lead";
    case "secretary": return "Secretary";
    case "researcher": return "Researcher";
    default: return "Viewer";
  }
}

export interface WorkspaceProject {
  id: string;
  name: string;
  description: string | null;
  status: string;
  role: ProjectRole | "platform_owner";
}

export interface WorkspaceMember {
  id: string;
  email: string;
  fullName: string;
  role: WorkspaceRole;
  organizationId: string | null;
  projects: WorkspaceProject[];
}

export interface DashboardMetrics {
  openTasks: number;
  workForReview: number;
  labResultsForReview: number;
  recentDocuments: number;
  unreadNotifications: number;
}

export interface ActivityItem {
  id: string;
  action: string;
  entityType: string;
  createdAt: string;
  projectId: string;
}

export interface TaskItem {
  id: string;
  title: string;
  status: TaskStatus;
  priority: Priority;
  dueAt: string | null;
  projectId: string;
  updatedAt?: string;
}

export interface MeetingItem {
  id: string;
  title: string;
  meetingAt: string;
  locationOrLink: string | null;
}

export interface RecordRow {
  id: string;
  title: string;
  status?: string | null;
  category?: string | null;
  subtitle?: string | null;
  updatedAt?: string | null;
}

export const organizationRoleLabels: Record<OrganizationRole, string> = {
  platform_owner: "Platform Owner",
  project_lead: "Project Lead",
  secretary: "Secretary",
  researcher: "Researcher",
  viewer: "Viewer"
};

export const taskStatusLabels: Record<TaskStatus, string> = {
  not_started: "Not started",
  in_progress: "In progress",
  submitted: "Submitted",
  under_review: "Under review",
  approved: "Approved",
  changes_requested: "Changes requested"
};

export function isReviewableTask(status: string): boolean {
  return status === "submitted" || status === "under_review";
}
