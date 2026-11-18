import "server-only";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { NextRequest } from "next/server";
import { z } from "zod";
import { authorizeProject, getActiveOrganization, mayAdminister, resolveApiContext, visibleProjectIds, type ApiContext } from "@/lib/api/auth";
import { apiError, apiResponse, readJson, requestId, rpcUnavailable } from "@/lib/api/http";
import { databaseRole } from "@/lib/domain";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

type RouteContext = { params: Promise<{ segments: string[] }> };
const uuid = z.string().uuid();
const shortText = (max = 160) => z.string().trim().min(1).max(max);
const optionalText = (max = 5000) => z.string().trim().max(max).optional().default("");
const dateTime = z.string().datetime({ offset: true }).nullable().optional();
const roles = ["project_lead", "secretary", "researcher", "viewer"] as const;
const eventTypes = ["task_assigned", "task_submitted", "task_reviewed", "task_approved", "lab_result_submitted", "lab_result_reviewed", "document_added", "formulation_version_added", "meeting_decision_added", "meeting_minutes_added", "report_generated", "report_published", "task_due_reminder", "task_overdue"] as const;
const listSpec = {
  tasks: { table: "tasks", select: "id, project_id, title, description, priority, status, due_at, created_by, created_at, updated_at" },
  samples: { table: "samples", select: "id, project_id, sample_code, sample_type, source_description, collected_at, received_at, storage_conditions, created_by, created_at" },
  labTests: { table: "lab_tests", select: "id, project_id, sample_id, title, objective, status, planned_at, created_by, created_at" },
  documents: { table: "documents", select: "id, project_id, title, description, category, visibility, created_by, status, created_at, updated_at, current_version_id" },
  research: { table: "research_entries", select: "id, project_id, title, body, entry_type, status, source_document_version_id, created_by, created_at, updated_at" },
  formulations: { table: "formulations", select: "id, project_id, name, description, status, created_by, created_at, updated_at" },
  meetings: { table: "meetings", select: "id, project_id, title, starts_at, ends_at, location_or_link, agenda, status, created_by, created_at, updated_at" },
  notifications: { table: "notifications", select: "id, recipient_id, project_id, event_type, source_table, source_id, title, body, created_at, read_at" },
  reports: { table: "ai_reports", select: "id, project_id, ai_job_id, title, period_start, period_end, content_markdown, status, reviewer_id, review_comment, reviewed_at, created_at, updated_at" }
} as const;
type CollectionName = keyof typeof listSpec;

function pathSegments(context: RouteContext) {
  return context.params.then(({ segments }) => segments.map((segment) => decodeURIComponent(segment)));
}

function parseWith<T extends z.ZodTypeAny>(schema: T, input: unknown) {
  const result = schema.safeParse(input);
  return result.success ? { ok: true as const, value: result.data } : { ok: false as const, details: result.error.flatten() };
}

function errorForDb(error: { code?: string; message?: string } | null, id: string) {
  if (rpcUnavailable(error)) return apiError("This operation is unavailable until the required database migration is applied.", 503, id);
  if (error?.code === "55000") return apiError("AI processing is disabled by the administrator.", 503, id);
  if (error?.code === "23505") return apiError("A record with these identifiers already exists.", 409, id);
  if (error?.code === "23503") return apiError("A referenced record is unavailable in this project.", 422, id);
  if (error?.code === "42501") return apiError("Permission denied.", 403, id);
  if (error?.code === "P0002") return apiError("Record not found.", 404, id);
  if (error?.code === "P0001") return apiError("The requested workflow change conflicts with the current record state.", 409, id);
  if (error?.code === "23514" || error?.code === "22023") return apiError("The supplied data does not satisfy the record constraints.", 422, id);
  return apiError("The database operation could not be completed.", 500, id);
}

async function requireProject(context: ApiContext, projectId: string, capability: "read" | "write" | "admin" | "review", id: string) {
  const access = await authorizeProject(context, projectId, capability);
  return access.ok ? access : apiError(access.error, access.status, id);
}

async function listRows(context: ApiContext, name: CollectionName, projectIds: string[], projectId: string | null, limit: number, before: string | null, id: string, userId?: string) {
  if (name === "notifications") {
    let query = context.supabase.from("notifications").select(listSpec.notifications.select).eq("recipient_id", userId ?? context.user.id).order("created_at", { ascending: false });
    if (before) query = query.lt("created_at", before);
    const { data, error } = await query.limit(limit + 1);
    if (error) return { response: errorForDb(error, id) };
    const rows = data ?? [];
    return { response: apiResponse({ items: rows.slice(0, limit), next_cursor: rows.length > limit ? rows[limit - 1]?.created_at : null }, 200, id) };
  }
  if (name === "reports") {
    if (projectIds.length === 0) return { response: apiResponse({ items: [], next_cursor: null }, 200, id) };
    let query = context.supabase.from("ai_reports").select(listSpec.reports.select).in("project_id", projectId ? [projectId] : projectIds).order("created_at", { ascending: false });
    if (before) query = query.lt("created_at", before);
    const { data, error } = await query.limit(limit + 1);
    if (error) return { response: errorForDb(error, id) };
    const rows = data ?? [];
    return { response: apiResponse({ items: rows.slice(0, limit), next_cursor: rows.length > limit ? rows[limit - 1]?.created_at : null }, 200, id) };
  }
  if (projectIds.length === 0) return { response: apiResponse({ items: [], next_cursor: null }, 200, id) };
  const ids = projectId ? [projectId] : projectIds;
  const build = () => {
    switch (name) {
      case "tasks": { let q = context.supabase.from("tasks").select(listSpec.tasks.select).in("project_id", ids).order("created_at", { ascending: false }); if (before) q = q.lt("created_at", before); return q.limit(limit + 1); }
      case "samples": { let q = context.supabase.from("samples").select(listSpec.samples.select).in("project_id", ids).order("created_at", { ascending: false }); if (before) q = q.lt("created_at", before); return q.limit(limit + 1); }
      case "labTests": { let q = context.supabase.from("lab_tests").select(listSpec.labTests.select).in("project_id", ids).order("created_at", { ascending: false }); if (before) q = q.lt("created_at", before); return q.limit(limit + 1); }
      case "documents": { let q = context.supabase.from("documents").select(listSpec.documents.select).in("project_id", ids).order("created_at", { ascending: false }); if (before) q = q.lt("created_at", before); return q.limit(limit + 1); }
      case "research": { let q = context.supabase.from("research_entries").select(listSpec.research.select).in("project_id", ids).order("created_at", { ascending: false }); if (before) q = q.lt("created_at", before); return q.limit(limit + 1); }
      case "formulations": { let q = context.supabase.from("formulations").select(listSpec.formulations.select).in("project_id", ids).order("created_at", { ascending: false }); if (before) q = q.lt("created_at", before); return q.limit(limit + 1); }
      case "meetings": { let q = context.supabase.from("meetings").select(listSpec.meetings.select).in("project_id", ids).order("created_at", { ascending: false }); if (before) q = q.lt("created_at", before); return q.limit(limit + 1); }
      default: return Promise.resolve({ data: [], error: null });
    }
  };
  const { data, error } = await build();
  if (error) return { response: errorForDb(error, id) };
  const rows = data ?? [];
  const createdAt = (row: (typeof rows)[number]) => "created_at" in row ? row.created_at : null;
  return { response: apiResponse({ items: rows.slice(0, limit), next_cursor: rows.length > limit ? createdAt(rows[limit - 1]) : null }, 200, id) };
}

export async function GET(request: NextRequest, route: RouteContext) {
  const id = requestId();
  const segments = await pathSegments(route);
  const path = segments.join("/");
  const auth = await resolveApiContext();
  if (!auth.ok) return apiError(auth.error, auth.status, id);
  const { context } = auth;
  const url = new URL(request.url);

  try {
    if (path === "profile") {
      const { data, error } = await context.supabase.from("profiles").select("id, display_name, phone_e164, locale, platform_owner, created_at, updated_at").eq("id", context.user.id).maybeSingle();
      if (error) return errorForDb(error, id);
      return apiResponse({ id: context.user.id, email: context.user.email, profile: data }, 200, id);
    }
    if (path === "projects") {
      const projectIds = await visibleProjectIds(context);
      if (!projectIds.length) return apiResponse({ items: [] }, 200, id);
      const { data, error } = await context.supabase.from("projects").select("id, organization_id, name, description, status, created_by, created_at, updated_at").in("id", projectIds).order("created_at", { ascending: true });
      if (error) return errorForDb(error, id);
      return apiResponse({ items: data ?? [] }, 200, id);
    }
    if (path === "members") {
      const organization = await getActiveOrganization(context);
      if (!organization) return apiError("Organization membership is required.", 403, id);
      const { data, error } = await context.supabase.rpc("get_organization_directory", { p_organization_id: organization.organization_id });
      if (error) return errorForDb(error, id);
      return apiResponse({ items: data ?? [] }, 200, id);
    }
    if (path === "tasks/summary") {
      const projectIds = await visibleProjectIds(context);
      if (!projectIds.length) return apiResponse({ open: 0, submitted: 0, under_review: 0, approved: 0, overdue: 0 }, 200, id);
      const today = new Date().toISOString();
      const [open, submitted, underReview, approved, overdue] = await Promise.all([
        context.supabase.from("tasks").select("id", { count: "exact", head: true }).in("project_id", projectIds).in("status", ["not_started", "in_progress", "changes_requested"]),
        context.supabase.from("tasks").select("id", { count: "exact", head: true }).in("project_id", projectIds).eq("status", "submitted"),
        context.supabase.from("tasks").select("id", { count: "exact", head: true }).in("project_id", projectIds).eq("status", "under_review"),
        context.supabase.from("tasks").select("id", { count: "exact", head: true }).in("project_id", projectIds).eq("status", "approved"),
        context.supabase.from("tasks").select("id", { count: "exact", head: true }).in("project_id", projectIds).lt("due_at", today).not("status", "eq", "approved")
      ]);
      return apiResponse({ open: open.count ?? 0, submitted: submitted.count ?? 0, under_review: underReview.count ?? 0, approved: approved.count ?? 0, overdue: overdue.count ?? 0 }, 200, id);
    }
    if (path === "notifications") {
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get("limit") ?? 50) || 50));
      const rows = await listRows(context, "notifications", [], null, limit, url.searchParams.get("before"), id);
      return rows.response;
    }
    if (path === "ai/reports") {
      const projectId = url.searchParams.get("project_id");
      if (projectId) { const access = await requireProject(context, projectId, "read", id); if (access instanceof Response) return access; }
      const projectIds = projectId ? [projectId] : await visibleProjectIds(context);
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get("limit") ?? 30) || 30));
      const rows = await listRows(context, "reports", projectIds, projectId, limit, url.searchParams.get("before"), id);
      return rows.response;
    }
    if (path === "search") {
      const term = (url.searchParams.get("q") ?? "").trim().slice(0, 120);
      if (term.length < 2) return apiError("Search text must contain at least two characters.", 422, id);
      const projectId = url.searchParams.get("project_id");
      if (projectId) { const access = await requireProject(context, projectId, "read", id); if (access instanceof Response) return access; }
      const projectIds = projectId ? [projectId] : await visibleProjectIds(context);
      if (!projectIds.length) return apiResponse({ query: term, items: [] }, 200, id);
      const results = await Promise.all(projectIds.map(async (authorizedProjectId) => {
        const { data, error } = await context.supabase.rpc("search_authorized_chunks", { p_user_id: context.user.id, p_project_id: authorizedProjectId, p_query: term, p_limit: 50, p_document_id: null });
        return { projectId: authorizedProjectId, data, error };
      }));
      const failed = results.find((result) => result.error);
      if (failed?.error) return errorForDb(failed.error, id);
      const items: Array<Record<string, unknown> & { project_id: string }> = results.flatMap((result) => ((result.data ?? []) as Array<Record<string, unknown>>).map((row: Record<string, unknown>) => ({ ...row, project_id: result.projectId })));
      items.sort((a, b) => Number(b.rank ?? 0) - Number(a.rank ?? 0));
      items.splice(50);
      return apiResponse({ query: term, items, mode: "authorized_full_text" }, 200, id);
    }
    if (segments[0] === "jobs" && segments[1]) {
      const { data: job, error } = await context.supabase.from("ai_jobs").select("id, project_id, requested_by, job_type, status, model_id, prompt_version, started_at, completed_at, error_code, created_at, result_reference").eq("id", segments[1]).maybeSingle();
      if (error) return errorForDb(error, id);
      if (!job) return apiError("Job not found.", 404, id);
      const access = await requireProject(context, job.project_id, "read", id);
      if (access instanceof Response) return access;
      if (job.requested_by !== context.user.id && !mayAdminister(access.role)) return apiError("Job not found.", 404, id);
      return apiResponse(job, 200, id);
    }
    if (segments.length === 3 && segments[0] === "ai" && segments[1] === "reports") {
      const { data: report, error } = await context.supabase.from("ai_reports").select(listSpec.reports.select).eq("id", segments[2]).maybeSingle();
      if (error) return errorForDb(error, id);
      if (!report) return apiError("Report not found.", 404, id);
      const access = await requireProject(context, report.project_id, "read", id);
      if (access instanceof Response) return access;
      const { data: citations, error: citationError } = await context.supabase.from("ai_citations").select("id, document_version_id, research_entry_id, chunk_id, page_no, section_label, excerpt_hash").eq("ai_report_id", report.id).order("created_at", { ascending: true });
      if (citationError) return errorForDb(citationError, id);
      return apiResponse({ ...report, citations: citations ?? [] }, 200, id);
    }
    if (segments.length === 2 && segments[0] === "projects") {
      const access = await requireProject(context, segments[1], "read", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.from("projects").select("id, organization_id, name, description, status, created_by, created_at, updated_at").eq("id", segments[1]).maybeSingle();
      if (error) return errorForDb(error, id);
      return data ? apiResponse(data, 200, id) : apiError("Project not found.", 404, id);
    }
    if (segments[0] === "documents" && segments[1] && segments[2] === "download") {
      const { data: document, error: documentError } = await context.supabase.from("documents").select("id, project_id, current_version_id").eq("id", segments[1]).maybeSingle();
      if (documentError) return errorForDb(documentError, id);
      if (!document) return apiError("Document not found.", 404, id);
      const access = await requireProject(context, document.project_id, "read", id);
      if (access instanceof Response) return access;
      const versionId = url.searchParams.get("version_id") ?? document.current_version_id;
      if (!versionId) return apiError("Document has no registered version.", 404, id);
      const { data: version, error: versionError } = await context.supabase.from("document_versions").select("storage_bucket, storage_path, file_name").eq("id", versionId).eq("document_id", document.id).maybeSingle();
      if (versionError) return errorForDb(versionError, id);
      if (!version) return apiError("Document version not found.", 404, id);
      const admin = createSupabaseAdminClient();
      if (!admin) return apiError("Private file storage is not configured.", 503, id);
      const { data: signed, error } = await admin.storage.from(version.storage_bucket).createSignedUrl(version.storage_path, 300, { download: version.file_name });
      if (error || !signed) return apiError("A temporary download link could not be issued.", 502, id);
      return apiResponse({ signed_url: signed.signedUrl, expires_in_seconds: 300 }, 200, id);
    }
    if (segments.length === 2 && ["tasks", "documents", "lab", "formulations", "meetings"].includes(segments[0])) {
      const table = segments[0] === "lab" ? "lab_tests" : segments[0];
      const findProjectRecord = async (): Promise<{ data: { project_id: string } | null; error: { code?: string; message?: string } | null }> => {
        switch (table) {
          case "tasks": return context.supabase.from("tasks").select("project_id").eq("id", segments[1]).maybeSingle();
          case "documents": return context.supabase.from("documents").select("project_id").eq("id", segments[1]).maybeSingle();
          case "lab_tests": return context.supabase.from("lab_tests").select("project_id").eq("id", segments[1]).maybeSingle();
          case "formulations": return context.supabase.from("formulations").select("project_id").eq("id", segments[1]).maybeSingle();
          case "meetings": return context.supabase.from("meetings").select("project_id").eq("id", segments[1]).maybeSingle();
          default: return { data: null, error: null };
        }
      };
      const { data, error } = await findProjectRecord();
      if (error) return errorForDb(error, id);
      if (!data) return apiError("Record not found.", 404, id);
      const access = await requireProject(context, data.project_id, "read", id);
      if (access instanceof Response) return access;
      if (table === "documents") {
        const { data: versions, error: versionsError } = await context.supabase.from("document_versions").select("id, version_no, file_name, mime_type, byte_size, sha256_hex, created_by, created_at, change_note").eq("document_id", segments[1]).order("version_no", { ascending: false });
        if (versionsError) return errorForDb(versionsError, id);
        const versionIds = (versions ?? []).map((version) => version.id);
        let jobs: Array<{ id: string; document_version_id: string; job_type: string; status: string; attempts: number; max_attempts: number; next_attempt_at: string; error_code: string | null; created_at: string; updated_at: string }> = [];
        if (access.role !== "viewer" && versionIds.length) {
          const { data: jobRows, error: jobsError } = await context.supabase.from("document_processing_jobs").select("id, document_version_id, job_type, status, attempts, max_attempts, next_attempt_at, error_code, created_at, updated_at").eq("project_id", data.project_id).in("document_version_id", versionIds).order("created_at", { ascending: false });
          if (jobsError) return errorForDb(jobsError, id);
          jobs = jobRows ?? [];
        }
        return apiResponse({ id: segments[1], project_id: data.project_id, versions: (versions ?? []).map((version) => ({ ...version, processing_jobs: jobs.filter((job) => job.document_version_id === version.id) })) }, 200, id);
      }
      return apiResponse(data, 200, id);
    }

    if (segments[0] === "formulations" && segments[1] && segments[2] === "compare") {
      const { data: formulation, error: formulationError } = await context.supabase.from("formulations").select("id, project_id, name").eq("id", segments[1]).maybeSingle();
      if (formulationError) return errorForDb(formulationError, id);
      if (!formulation) return apiError("Formulation not found.", 404, id);
      const access = await requireProject(context, formulation.project_id, "read", id);
      if (access instanceof Response) return access;
      const versionIds = [url.searchParams.get("version_a"), url.searchParams.get("version_b")];
      if (versionIds.some((value) => !value || !uuid.safeParse(value).success) || versionIds[0] === versionIds[1]) return apiError("Two distinct version_a and version_b UUIDs are required.", 422, id);
      const { data: versions, error: versionsError } = await context.supabase.from("formulation_versions").select("id, version_no, status, batch_basis, instructions, change_rationale, supersedes_version_id, created_by, created_at").eq("formulation_id", formulation.id).in("id", versionIds as string[]).order("version_no", { ascending: true });
      if (versionsError) return errorForDb(versionsError, id);
      if ((versions ?? []).length !== 2) return apiError("One or both versions are not available in this formulation.", 404, id);
      const { data: ingredients, error: ingredientError } = await context.supabase.from("formulation_ingredients").select("formulation_version_id, ingredient_name, quantity, unit, interpretation_basis, sequence_no, notes").in("formulation_version_id", versionIds as string[]).order("sequence_no", { ascending: true });
      if (ingredientError) return errorForDb(ingredientError, id);
      return apiResponse({ formulation_id: formulation.id, versions: versions.map((version) => ({ ...version, ingredients: (ingredients ?? []).filter((item) => item.formulation_version_id === version.id) })) }, 200, id);
    }
    if (segments[0] === "meetings" && segments[1] && segments[2] === "brief") {
      const { data: meeting, error: meetingError } = await context.supabase.from("meetings").select("id, project_id, title, starts_at, ends_at, agenda, location_or_link").eq("id", segments[1]).maybeSingle();
      if (meetingError) return errorForDb(meetingError, id);
      if (!meeting) return apiError("Meeting not found.", 404, id);
      const access = await requireProject(context, meeting.project_id, "read", id);
      if (access instanceof Response) return access;
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get("limit") ?? 40) || 40));
      const status = url.searchParams.get("status");
      const memberId = url.searchParams.get("member_id");
      if (memberId && !uuid.safeParse(memberId).success) return apiError("member_id must be a UUID.", 422, id);
      const [taskResult, labResult, documentResult, decisionResult] = await Promise.all([
        context.supabase.from("tasks").select("id, title, status, priority, due_at, updated_at").eq("project_id", meeting.project_id).order("updated_at", { ascending: false }).limit(limit),
        context.supabase.from("lab_tests").select("id, title, status, planned_at, updated_at").eq("project_id", meeting.project_id).in("status", ["submitted", "under_review", "changes_requested"]).order("updated_at", { ascending: false }).limit(limit),
        context.supabase.from("documents").select("id, title, category, status, created_at").eq("project_id", meeting.project_id).order("created_at", { ascending: false }).limit(limit),
        context.supabase.from("meeting_decisions").select("id, decision_text, status, responsible_user_id, follow_up_task_id, created_at").eq("project_id", meeting.project_id).order("created_at", { ascending: false }).limit(limit)
      ]);
      const failed = [taskResult, labResult, documentResult, decisionResult].find((result) => result.error);
      if (failed?.error) return errorForDb(failed.error, id);
      let tasks = taskResult.data ?? [];
      if (status) tasks = tasks.filter((task) => task.status === status);
      if (memberId) {
        const { data: assignments, error: assignmentError } = await context.supabase.from("task_assignees").select("task_id").eq("project_id", meeting.project_id).eq("user_id", memberId).is("ended_at", null);
        if (assignmentError) return errorForDb(assignmentError, id);
        const assignedIds = new Set((assignments ?? []).map((assignment) => assignment.task_id));
        tasks = tasks.filter((task) => assignedIds.has(task.id));
      }
      return apiResponse({ meeting, filters: { status: status ?? null, member_id: memberId }, tasks, lab_reviews: labResult.data ?? [], recent_documents: documentResult.data ?? [], decisions: decisionResult.data ?? [] }, 200, id);
    }
    const collectionByPath: Record<string, CollectionName> = { tasks: "tasks", "lab/samples": "samples", "lab/tests": "labTests", documents: "documents", research: "research", formulations: "formulations", meetings: "meetings", "ai/reports": "reports" };
    const collection = collectionByPath[path];
    if (collection) {
      const projectId = url.searchParams.get("project_id");
      if (projectId) { const access = await requireProject(context, projectId, "read", id); if (access instanceof Response) return access; }
      const projectIds = projectId ? [projectId] : await visibleProjectIds(context);
      const limit = Math.min(100, Math.max(1, Number(url.searchParams.get("limit") ?? 30) || 30));
      const rows = await listRows(context, collection, projectIds, projectId, limit, url.searchParams.get("before"), id);
      return rows.response;
    }
    return apiError("API route not found.", 404, id);
  } catch {
    return apiError("The request could not be completed.", 500, id);
  }
}

export async function POST(request: NextRequest, route: RouteContext) {
  const id = requestId();
  const segments = await pathSegments(route);
  const path = segments.join("/");
  const auth = await resolveApiContext();
  if (!auth.ok) return apiError(auth.error, auth.status, id);
  const { context } = auth;
  const parsedBody = await readJson(request);
  if (!parsedBody.ok) return apiError(parsedBody.error, parsedBody.status, id);
  const body = parsedBody.value;

  try {
    if (path === "projects") {
      const parsed = parseWith(z.object({ name: shortText(120), description: optionalText(2000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const organization = await getActiveOrganization(context);
      if (!organization || !mayAdminister(organization.role)) return apiError("Project administration permission required.", 403, id);
      const { data, error } = await context.supabase.rpc("create_project_with_audit", { p_organization_id: organization.organization_id, p_name: parsed.value.name, p_description: parsed.value.description });
      if (error) return errorForDb(error, id);
      return apiResponse({ id: data, name: parsed.value.name }, 201, id);
    }
    if (path === "invitations") {
      const parsed = parseWith(z.object({ email: z.string().trim().email().max(320), role: z.enum(roles), organization_id: uuid.optional(), project_id: uuid.optional(), project_role: z.enum(["project_lead", "secretary", "researcher", "viewer"]).optional() }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const organization = await getActiveOrganization(context);
      if (!organization || !mayAdminister(organization.role) || (parsed.value.organization_id && parsed.value.organization_id !== organization.organization_id)) return apiError("Organization administrator permission required.", 403, id);
      if (parsed.value.project_id) {
        const access = await requireProject(context, parsed.value.project_id, "admin", id);
        if (access instanceof Response) return access;
        if (access.organizationId !== organization.organization_id) return apiError("Project does not belong to this organization.", 403, id);
      }
      const admin = createSupabaseAdminClient();
      const appBaseUrl = process.env.APP_BASE_URL;
      if (!admin || !appBaseUrl) return apiError("Invitation delivery is not configured.", 503, id);
      const rawToken = randomBytes(32).toString("hex");
      let redirectTo: string;
      try { const base = new URL(appBaseUrl); if (base.protocol !== "https:" && base.hostname !== "localhost") throw new Error(); const callback = new URL("/auth/callback", base); callback.searchParams.set("next", "/invite/accept"); callback.searchParams.set("invite_token", rawToken); redirectTo = callback.toString(); } catch { return apiError("The configured application URL is invalid.", 503, id); }
      const tokenHash = createHash("sha256").update(rawToken).digest("hex");
      const { data: invitationId, error: invitationError } = await context.supabase.rpc("create_invitation_with_audit", { p_organization_id: organization.organization_id, p_email: parsed.value.email.toLowerCase(), p_role: databaseRole(parsed.value.role), p_project_id: parsed.value.project_id ?? null, p_project_role: parsed.value.project_id ? databaseRole(parsed.value.project_role ?? parsed.value.role) : null, p_token_hash_hex: tokenHash });
      if (invitationError) return errorForDb(invitationError, id);
      const { error: inviteError } = await admin.auth.admin.inviteUserByEmail(parsed.value.email.toLowerCase(), { redirectTo });
      if (inviteError) {
        await admin.from("invitations").delete().eq("id", invitationId);
        return apiError("Invitation email could not be sent.", 502, id);
      }
      return apiResponse({ invitation_id: invitationId, status: "invited" }, 201, id);
    }
    if (path === "tasks") {
      const parsed = parseWith(z.object({ project_id: uuid, title: shortText(160), description: optionalText(5000), priority: z.enum(["low", "normal", "high", "urgent"]).default("normal"), due_at: dateTime, assignee_ids: z.array(uuid).max(30).default([]) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const access = await requireProject(context, parsed.value.project_id, "write", id);
      if (access instanceof Response) return access;
      const assigneeIds = parsed.value.assignee_ids.length ? parsed.value.assignee_ids : [context.user.id];
      const { data, error } = await context.supabase.rpc("create_task_with_audit", { p_project_id: parsed.value.project_id, p_title: parsed.value.title, p_description: parsed.value.description, p_priority: parsed.value.priority, p_due_at: parsed.value.due_at ?? null, p_assignee_ids: assigneeIds });
      if (error) return errorForDb(error, id);
      return apiResponse({ id: data }, 201, id);
    }
    if (path === "lab/samples") {
      const parsed = parseWith(z.object({ project_id: uuid, sample_code: shortText(80), sample_type: shortText(120), source_description: optionalText(3000), collected_at: dateTime, received_at: dateTime, storage_conditions: optionalText(1000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const access = await requireProject(context, parsed.value.project_id, "write", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("create_sample_with_audit", { p_project_id: parsed.value.project_id, p_sample_code: parsed.value.sample_code, p_sample_type: parsed.value.sample_type, p_source_description: parsed.value.source_description, p_collected_at: parsed.value.collected_at ?? null, p_received_at: parsed.value.received_at ?? null, p_storage_conditions: parsed.value.storage_conditions });
      if (error) return errorForDb(error, id);
      return apiResponse({ id: data }, 201, id);
    }
    if (path === "lab/tests") {
      const parsed = parseWith(z.object({ project_id: uuid, test_name: shortText(160), objective: optionalText(4000), sample_id: uuid, planned_at: dateTime, assignee_ids: z.array(uuid).max(30).default([]) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const access = await requireProject(context, parsed.value.project_id, "write", id);
      if (access instanceof Response) return access;
      const { data: sample } = await context.supabase.from("samples").select("id").eq("id", parsed.value.sample_id).eq("project_id", parsed.value.project_id).maybeSingle();
      if (!sample) return apiError("Sample not found in this project.", 404, id);
      const assigneeIds = [...new Set([context.user.id, ...parsed.value.assignee_ids])];
      const { data, error } = await context.supabase.rpc("create_lab_test_with_audit", { p_project_id: parsed.value.project_id, p_sample_id: parsed.value.sample_id, p_test_name: parsed.value.test_name, p_objective: parsed.value.objective, p_planned_at: parsed.value.planned_at ?? null, p_assignee_ids: assigneeIds });
      if (error) return errorForDb(error, id);
      return apiResponse({ id: data }, 201, id);
    }
    if (path === "documents") {
      const parsed = parseWith(z.object({ project_id: uuid, title: shortText(200), category: z.enum(["paper", "procedure", "result", "formulation", "technical_report", "minutes", "manual", "presentation", "other"]).default("other"), description: optionalText(5000), visibility: z.enum(["private", "project", "approved"]).default("project") }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const access = await requireProject(context, parsed.value.project_id, "write", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("create_document_with_audit", { p_project_id: parsed.value.project_id, p_title: parsed.value.title, p_description: parsed.value.description, p_category: parsed.value.category, p_visibility: parsed.value.visibility });
      if (error) return errorForDb(error, id);
      return apiResponse({ id: data }, 201, id);
    }
    if (path === "formulations") {
      const parsed = parseWith(z.object({ project_id: uuid, product_name: shortText(160), description: optionalText(3000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const access = await requireProject(context, parsed.value.project_id, "write", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("create_formulation_with_audit", { p_project_id: parsed.value.project_id, p_product_name: parsed.value.product_name, p_description: parsed.value.description });
      if (error) return errorForDb(error, id);
      return apiResponse({ id: data }, 201, id);
    }
    if (path === "meetings") {
      const parsed = parseWith(z.object({ project_id: uuid, title: shortText(200), meeting_at: z.string().datetime({ offset: true }), location_or_link: optionalText(500), agenda: optionalText(5000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const access = await requireProject(context, parsed.value.project_id, "admin", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("create_meeting_with_audit", { p_project_id: parsed.value.project_id, p_title: parsed.value.title, p_meeting_at: parsed.value.meeting_at, p_location_or_link: parsed.value.location_or_link, p_agenda: parsed.value.agenda });
      if (error) return errorForDb(error, id);
      return apiResponse({ id: data }, 201, id);
    }
    if (path === "ai/chat" || path === "ai/analyze-document" || path === "ai/compare" || path === "ai/reports/generate") {
      const schema = path === "ai/chat" ? z.object({ project_id: uuid, question: shortText(4000) }).strict() : path === "ai/analyze-document" ? z.object({ project_id: uuid, document_id: uuid, question: optionalText(2000) }).strict() : path === "ai/compare" ? z.object({ project_id: uuid, record_type: z.enum(["experiment", "formulation"]), record_ids: z.array(uuid).min(2).max(10), question: optionalText(2000) }).strict() : z.object({ project_id: uuid, report_type: z.enum(["activity", "research", "lab_summary"]), period_start: z.string().datetime({ offset: true }), period_end: z.string().datetime({ offset: true }) }).strict();
      const parsed = parseWith(schema, body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const values = parsed.value as Record<string, unknown>;
      const access = await requireProject(context, String(values.project_id), "read", id);
      if (access instanceof Response) return access;
      if (process.env.AI_ENABLED !== "true") return apiError("AI processing is disabled by the administrator.", 503, id);
      if (path === "ai/compare" || path === "ai/reports/generate") return apiError("This AI job type is not enabled until its evidence adapter is implemented and reviewed.", 503, id);
      if (path === "ai/analyze-document") {
        const { data: document } = await context.supabase.from("documents").select("id").eq("id", values.document_id as string).eq("project_id", values.project_id as string).maybeSingle();
        if (!document) return apiError("Document not found in this project.", 404, id);
      }
      const question = path === "ai/chat" ? String(values.question) : String(values.question || "Analyze this document using only its authorized source material.");
      const { data: chunks, error: evidenceError } = await context.supabase.rpc("search_authorized_chunks", { p_user_id: context.user.id, p_project_id: values.project_id, p_query: question, p_limit: 50, p_document_id: path === "ai/analyze-document" ? values.document_id : null });
      if (evidenceError) return errorForDb(evidenceError, id);
      const chunkRows = (chunks ?? []) as Array<{ chunk_id: unknown }>;
      const chunkIds = [...new Set(chunkRows.map((chunk: { chunk_id: unknown }) => chunk.chunk_id).filter((chunkId: unknown): chunkId is string => typeof chunkId === "string"))];
      if (!chunkIds.length) return apiError("No authorized indexed source material matched this request.", 422, id);
      const jobType = path === "ai/chat" ? "chat" : "analysis";
      const inputReference = { chunk_ids: chunkIds, ...(path === "ai/analyze-document" ? { document_id: values.document_id } : {}) };
      const { data: queued, error } = await context.supabase.rpc("queue_ai_request_with_audit", { p_project_id: values.project_id, p_job_type: jobType, p_question: question, p_input_reference: inputReference, p_prompt_version: "forevit-evidence-v1" });
      if (error) return errorForDb(error, id);
      if (!queued || typeof queued !== "object" || !("job_id" in queued) || !("conversation_id" in queued)) return apiError("AI request could not be queued.", 500, id);
      return apiResponse({ job_id: queued.job_id, conversation_id: queued.conversation_id, status: "queued", evidence_count: chunkIds.length }, 202, id);
    }
    if (segments[0] === "tasks" && segments[1] && segments[2] === "submissions") {
      const parsed = parseWith(z.object({ description: optionalText(5000), document_version_ids: z.array(uuid).max(30).default([]) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: task } = await context.supabase.from("tasks").select("project_id").eq("id", segments[1]).maybeSingle();
      if (!task) return apiError("Task not found.", 404, id);
      const access = await requireProject(context, task.project_id, "write", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("submit_task_with_audit", { p_task_id: segments[1], p_description: parsed.value.description, p_document_version_ids: parsed.value.document_version_ids });
      if (error) return errorForDb(error, id);
      return apiResponse({ submission_id: data }, 201, id);
    }
    if (segments[0] === "tasks" && segments[1] && segments[2] === "reviews") {
      const parsed = parseWith(z.object({ submission_id: uuid, decision: z.enum(["approved", "changes_requested"]), comments: optionalText(3000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: task } = await context.supabase.from("tasks").select("project_id").eq("id", segments[1]).maybeSingle();
      if (!task) return apiError("Task not found.", 404, id);
      const access = await requireProject(context, task.project_id, "review", id);
      if (access instanceof Response) return access;
      const { error } = await context.supabase.rpc("review_task_submission", { p_task_id: segments[1], p_submission_id: parsed.value.submission_id, p_decision: parsed.value.decision, p_comments: parsed.value.comments });
      if (error) return errorForDb(error, id);
      return apiResponse({ task_id: segments[1], submission_id: parsed.value.submission_id, decision: parsed.value.decision }, 201, id);
    }
    if (segments[0] === "lab" && segments[1] === "tests" && segments[2] && segments[3] === "procedures") {
      const parsed = parseWith(z.object({ document_version_id: uuid, note: optionalText(1000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: test } = await context.supabase.from("lab_tests").select("project_id").eq("id", segments[2]).maybeSingle();
      if (!test) return apiError("Lab test not found.", 404, id);
      const access = await requireProject(context, test.project_id, "write", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("add_lab_test_procedure", { p_lab_test_id: segments[2], p_document_version_id: parsed.value.document_version_id, p_note: parsed.value.note });
      if (error) return errorForDb(error, id);
      return apiResponse({ procedure_link_id: data }, 201, id);
    }
    if (segments[0] === "lab" && segments[1] === "tests" && segments[2] && segments[3] === "results") {
      const measurement = z.object({ parameter_name: shortText(100), numeric_value: z.number().finite().nullable().optional(), text_value: z.string().trim().max(1000).nullable().optional(), unit: shortText(60), method: shortText(500), notes: optionalText(2000), measured_at: dateTime }).strict().refine((value) => (value.numeric_value !== undefined && value.numeric_value !== null) !== Boolean(value.text_value?.trim()), "Provide exactly one numeric or text value.");
      const parsed = parseWith(z.object({ conditions: z.record(z.unknown()).default({}), equipment: z.array(shortText(200)).max(100).default([]), observations: optionalText(10000), deviations: optionalText(5000), conclusion: optionalText(5000), correction_reason: optionalText(1000), measurements: z.array(measurement).min(1).max(100), document_version_ids: z.array(uuid).max(30).default([]) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: test } = await context.supabase.from("lab_tests").select("project_id").eq("id", segments[2]).maybeSingle();
      if (!test) return apiError("Lab test not found.", 404, id);
      const access = await requireProject(context, test.project_id, "write", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("submit_lab_result_with_audit", { p_lab_test_id: segments[2], p_conditions: parsed.value.conditions, p_equipment: parsed.value.equipment, p_observations: parsed.value.observations, p_deviations: parsed.value.deviations, p_conclusion: parsed.value.conclusion, p_correction_reason: parsed.value.correction_reason, p_measurements: parsed.value.measurements, p_document_version_ids: parsed.value.document_version_ids });
      if (error) return errorForDb(error, id);
      return apiResponse({ result_id: data }, 201, id);
    }
    if (segments[0] === "lab" && segments[1] === "results" && segments[2] && segments[3] === "reviews") {
      const parsed = parseWith(z.object({ decision: z.enum(["approved", "changes_requested"]), comments: optionalText(3000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: result } = await context.supabase.from("lab_results").select("project_id").eq("id", segments[2]).maybeSingle();
      if (!result) return apiError("Lab result not found.", 404, id);
      const access = await requireProject(context, result.project_id, "review", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("review_lab_result", { p_result_id: segments[2], p_decision: parsed.value.decision, p_comments: parsed.value.comments });
      if (error) return errorForDb(error, id);
      return apiResponse({ review_id: data, decision: parsed.value.decision }, 201, id);
    }
    if (segments[0] === "formulations" && segments[1] && segments[2] === "versions") {
      const ingredient = z.object({ ingredient_name: shortText(160), quantity: z.number().finite().nonnegative(), unit: shortText(60), interpretation_basis: shortText(200), notes: optionalText(1000) }).strict();
      const parsed = parseWith(z.object({ batch_basis: optionalText(500), instructions: optionalText(10000), change_rationale: optionalText(3000), ingredients: z.array(ingredient).min(1).max(100) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: formulation } = await context.supabase.from("formulations").select("project_id").eq("id", segments[1]).maybeSingle();
      if (!formulation) return apiError("Formulation not found.", 404, id);
      const access = await requireProject(context, formulation.project_id, "write", id);
      if (access instanceof Response) return access;
      const ingredients = parsed.value.ingredients.map((item: z.infer<typeof ingredient>, index: number) => ({ ...item, sequence_no: index + 1 }));
      const { data, error } = await context.supabase.rpc("create_formulation_version", { p_formulation_id: segments[1], p_batch_basis: parsed.value.batch_basis, p_instructions: parsed.value.instructions, p_change_rationale: parsed.value.change_rationale, p_ingredients: ingredients });
      if (error) return errorForDb(error, id);
      return apiResponse({ version_id: data }, 201, id);
    }
    if (segments[0] === "formulations" && segments[1] && segments[2] === "trials") {
      const parsed = parseWith(z.object({ formulation_version_id: uuid, lab_test_id: uuid, observations: optionalText(5000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: formulation } = await context.supabase.from("formulations").select("project_id").eq("id", segments[1]).maybeSingle();
      if (!formulation) return apiError("Formulation not found.", 404, id);
      const access = await requireProject(context, formulation.project_id, "write", id);
      if (access instanceof Response) return access;
      const { data: version } = await context.supabase.from("formulation_versions").select("id").eq("id", parsed.value.formulation_version_id).eq("formulation_id", segments[1]).maybeSingle();
      if (!version) return apiError("Formulation version not found in this formulation.", 404, id);
      const { data, error } = await context.supabase.rpc("add_formulation_trial", { p_formulation_version_id: parsed.value.formulation_version_id, p_lab_test_id: parsed.value.lab_test_id, p_observations: parsed.value.observations });
      if (error) return errorForDb(error, id);
      return apiResponse({ trial_id: data }, 201, id);
    }
    if (segments[0] === "meetings" && segments[1] && segments[2] === "minutes") {
      const parsed = parseWith(z.object({ document_version_id: uuid }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: meeting } = await context.supabase.from("meetings").select("project_id").eq("id", segments[1]).maybeSingle();
      if (!meeting) return apiError("Meeting not found.", 404, id);
      const access = await requireProject(context, meeting.project_id, "admin", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("add_meeting_minutes", { p_meeting_id: segments[1], p_document_version_id: parsed.value.document_version_id });
      if (error) return errorForDb(error, id);
      return apiResponse({ minutes_id: data }, 201, id);
    }
    if (segments[0] === "meetings" && segments[1] && segments[2] === "decisions") {
      const parsed = parseWith(z.object({ decision_text: shortText(5000), responsible_user_id: uuid.nullable().optional(), follow_up_task_id: uuid.nullable().optional() }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: meeting } = await context.supabase.from("meetings").select("project_id").eq("id", segments[1]).maybeSingle();
      if (!meeting) return apiError("Meeting not found.", 404, id);
      const access = await requireProject(context, meeting.project_id, "admin", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("create_meeting_decision", { p_meeting_id: segments[1], p_decision_text: parsed.value.decision_text, p_responsible_user_id: parsed.value.responsible_user_id ?? null, p_follow_up_task_id: parsed.value.follow_up_task_id ?? null });
      if (error) return errorForDb(error, id);
      return apiResponse({ decision_id: data }, 201, id);
    }
    if (segments[0] === "ai" && segments[1] === "reports" && segments[2] && segments[3] === "review") {
      const parsed = parseWith(z.object({ decision: z.enum(["approved", "changes_requested"]), comments: optionalText(3000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: report } = await context.supabase.from("ai_reports").select("id, project_id").eq("id", segments[2]).maybeSingle();
      if (!report) return apiError("AI report not found.", 404, id);
      const access = await requireProject(context, report.project_id, "review", id);
      if (access instanceof Response) return access;
      const { error } = await context.supabase.rpc("review_ai_report", { p_report_id: report.id, p_decision: parsed.value.decision, p_comments: parsed.value.comments });
      if (error) return errorForDb(error, id);
      return apiResponse({ report_id: report.id, decision: parsed.value.decision }, 200, id);
    }
    if (path === "notification-preferences") {
      const parsed = parseWith(z.object({ event_type: z.enum(eventTypes), channel: z.enum(["in_app", "whatsapp"]), enabled: z.boolean(), project_id: uuid.nullable().optional() }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      if (parsed.value.project_id) { const access = await requireProject(context, parsed.value.project_id, "read", id); if (access instanceof Response) return access; }
      const { data, error } = await context.supabase.rpc("set_notification_preference", { p_event_type: parsed.value.event_type, p_channel: parsed.value.channel, p_enabled: parsed.value.enabled, p_project_id: parsed.value.project_id ?? null });
      if (error) return errorForDb(error, id);
      return apiResponse({ preference_id: data, event_type: parsed.value.event_type, channel: parsed.value.channel, enabled: parsed.value.enabled, project_id: parsed.value.project_id ?? null }, 200, id);
    }
    if (path === "uploads/sign") {
      const parsed = parseWith(z.object({ project_id: uuid, file_name: shortText(255), mime_type: z.enum(["application/pdf", "image/png", "image/jpeg", "text/plain", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/vnd.openxmlformats-officedocument.presentationml.presentation"]), byte_size: z.number().int().positive().max(20 * 1024 * 1024) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const access = await requireProject(context, parsed.value.project_id, "write", id);
      if (access instanceof Response) return access;
      const admin = createSupabaseAdminClient();
      if (!admin) return apiError("Private file storage is not configured.", 503, id);
      const bucket = process.env.SUPABASE_STORAGE_BUCKET ?? "forevit-private";
      const safeName = parsed.value.file_name.normalize("NFKC").replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^\.+/, "").slice(-160) || "upload";
      const objectPath = `${parsed.value.project_id}/${context.user.id}/${randomUUID()}-${safeName}`;
      const { data, error } = await admin.storage.from(bucket).createSignedUploadUrl(objectPath, { upsert: false });
      if (error || !data) return apiError("A signed upload could not be issued.", 502, id);
      return apiResponse({ bucket, path: objectPath, token: data.token, signed_url: data.signedUrl, max_bytes: 20 * 1024 * 1024, expires_in_seconds: 3600 }, 201, id);
    }
    if (path === "uploads/complete" || (segments[0] === "documents" && segments[1] && segments[2] === "versions")) {
      const parsed = parseWith(z.object({ project_id: uuid, document_id: uuid.optional(), path: shortText(700), file_name: shortText(255), mime_type: z.string().max(160), change_note: optionalText(1000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const documentId = segments[0] === "documents" ? segments[1] : parsed.value.document_id;
      if (!documentId || (parsed.value.document_id && parsed.value.document_id !== documentId)) return apiError("Document ID is required and must match the route.", 422, id);
      const access = await requireProject(context, parsed.value.project_id, "write", id);
      if (access instanceof Response) return access;
      if (!parsed.value.path.startsWith(`${parsed.value.project_id}/${context.user.id}/`) || parsed.value.path.includes("..")) return apiError("Upload path is outside the authorized project area.", 403, id);
      const admin = createSupabaseAdminClient();
      if (!admin) return apiError("Private file storage is not configured.", 503, id);
      const bucket = process.env.SUPABASE_STORAGE_BUCKET ?? "forevit-private";
      const { data: document } = await context.supabase.from("documents").select("id").eq("id", documentId).eq("project_id", parsed.value.project_id).maybeSingle();
      if (!document) return apiError("Document not found in this project.", 404, id);
      const { data: file, error: downloadError } = await admin.storage.from(bucket).download(parsed.value.path);
      if (downloadError || !file) return apiError("Uploaded object was not found.", 404, id);
      if (file.size > 20 * 1024 * 1024 || file.size === 0) return apiError("Uploaded file size is not allowed.", 422, id);
      const bytes = Buffer.from(await file.arrayBuffer());
      const expectedMime = parsed.value.mime_type.toLowerCase();
      const allowedMimes = new Set(["application/pdf", "image/png", "image/jpeg", "text/plain", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/vnd.openxmlformats-officedocument.presentationml.presentation"]);
      if (!allowedMimes.has(expectedMime)) return apiError("File type is not allowed.", 422, id);
      const isPdf = bytes.subarray(0, 5).toString("ascii") === "%PDF-";
      const isPng = bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
      const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
      const isZip = bytes.subarray(0, 2).toString("ascii") === "PK";
      if ((expectedMime === "application/pdf" && !isPdf) || (expectedMime === "image/png" && !isPng) || (expectedMime === "image/jpeg" && !isJpeg) || (expectedMime.startsWith("application/vnd.openxmlformats-officedocument") && !isZip)) return apiError("File signature does not match the declared file type.", 422, id);
      const sha256 = createHash("sha256").update(bytes).digest("hex");
      const { data, error } = await context.supabase.rpc("register_document_version", { p_document_id: documentId, p_storage_bucket: bucket, p_storage_path: parsed.value.path, p_file_name: parsed.value.file_name, p_mime_type: expectedMime, p_byte_size: bytes.byteLength, p_sha256_hex: sha256, p_change_note: parsed.value.change_note });
      if (error) return errorForDb(error, id);
      return apiResponse({ version_id: data, sha256, byte_size: bytes.byteLength }, 201, id);
    }
    if (path === "research") {
      const parsed = parseWith(z.object({ project_id: uuid, title: shortText(200), abstract: optionalText(5000), methodology: optionalText(10000), findings: optionalText(10000), source_type: z.enum(["literature", "internal_study", "hypothesis", "other"]).default("other"), document_id: uuid.nullable().optional() }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const access = await requireProject(context, parsed.value.project_id, "write", id);
      if (access instanceof Response) return access;
      const { data, error } = await context.supabase.rpc("create_research_entry_with_audit", { p_project_id: parsed.value.project_id, p_title: parsed.value.title, p_abstract: parsed.value.abstract, p_methodology: parsed.value.methodology, p_findings: parsed.value.findings, p_source_type: parsed.value.source_type, p_document_id: parsed.value.document_id ?? null });
      if (error) return errorForDb(error, id);
      return apiResponse({ id: data }, 201, id);
    }
    if (path === "notifications/consent") {
      const parsed = parseWith(z.object({ channel: z.literal("whatsapp"), consent_status: z.enum(["granted", "revoked"]), source: z.enum(["settings", "written_request", "imported_record"]), phone_e164: z.string().regex(/^\+[1-9][0-9]{7,14}$/).optional(), evidence: optionalText(2000) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data, error } = await context.supabase.rpc("record_notification_consent", { p_channel: parsed.value.channel, p_consent_status: parsed.value.consent_status, p_source: parsed.value.source, p_phone_e164: parsed.value.phone_e164 ?? null, p_evidence: parsed.value.evidence });
      if (error) return errorForDb(error, id);
      return apiResponse({ id: data, consent_status: parsed.value.consent_status }, 201, id);
    }
    return apiError("API route not found.", 404, id);
  } catch {
    return apiError("The request could not be completed.", 500, id);
  }
}

export async function PATCH(request: NextRequest, route: RouteContext) {
  const id = requestId();
  const segments = await pathSegments(route);
  const auth = await resolveApiContext();
  if (!auth.ok) return apiError(auth.error, auth.status, id);
  const context = auth.context;
  let body: unknown = {};
  if (!(segments[0] === "notifications" && segments[1] && segments[2] === "read")) {
    const parsedBody = await readJson(request);
    if (!parsedBody.ok) return apiError(parsedBody.error, parsedBody.status, id);
    body = parsedBody.value;
  }
  try {
    if (segments[0] === "notifications" && segments[1] && segments[2] === "read") {
      const { data, error } = await context.supabase.from("notifications").update({ read_at: new Date().toISOString() }).eq("id", segments[1]).eq("recipient_id", context.user.id).select("id, read_at").maybeSingle();
      if (error) return errorForDb(error, id);
      return data ? apiResponse(data, 200, id) : apiError("Notification not found.", 404, id);
    }
    if (segments[0] === "notification-preferences") {
      const parsed = parseWith(z.object({ event_type: z.enum(eventTypes), channel: z.enum(["in_app", "whatsapp"]), enabled: z.boolean(), project_id: uuid.nullable().optional() }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      if (parsed.value.project_id) { const access = await requireProject(context, parsed.value.project_id, "read", id); if (access instanceof Response) return access; }
      const { data, error } = await context.supabase.rpc("set_notification_preference", { p_event_type: parsed.value.event_type, p_channel: parsed.value.channel, p_enabled: parsed.value.enabled, p_project_id: parsed.value.project_id ?? null });
      if (error) return errorForDb(error, id);
      return apiResponse({ preference_id: data, event_type: parsed.value.event_type, channel: parsed.value.channel, enabled: parsed.value.enabled, project_id: parsed.value.project_id ?? null }, 200, id);
    }
    if (segments[0] === "tasks" && segments[1]) {
      const parsed = parseWith(z.object({ status: z.enum(["in_progress", "submitted", "under_review", "approved", "changes_requested"]).optional(), priority: z.enum(["low", "normal", "high", "urgent"]).optional(), due_at: dateTime, comment: optionalText(2000) }).strict().refine((value) => Object.values(value).some((entry) => entry !== undefined && entry !== ""), "At least one field is required"), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const { data: task } = await context.supabase.from("tasks").select("id, project_id, status").eq("id", segments[1]).maybeSingle();
      if (!task) return apiError("Task not found.", 404, id);
      const privilegedTransition = parsed.value.status === "approved" || parsed.value.status === "changes_requested" || parsed.value.status === "under_review";
      const access = await requireProject(context, task.project_id, privilegedTransition ? "review" : "write", id);
      if (access instanceof Response) return access;
      if (parsed.value.status) {
        const { data, error } = await context.supabase.rpc("transition_task_status", { p_task_id: segments[1], p_new_status: parsed.value.status, p_comment: parsed.value.comment ?? "" });
        if (error) return errorForDb(error, id);
        return apiResponse({ id: segments[1], status: data }, 200, id);
      }
      const { data, error } = await context.supabase.rpc("update_task_with_audit", { p_task_id: segments[1], p_priority: parsed.value.priority ?? null, p_due_at: parsed.value.due_at ?? null });
      if (error) return errorForDb(error, id);
      return apiResponse(data ?? { id: segments[1] }, 200, id);
    }
    if (segments[0] === "members" && segments[1] && segments[2] === "role") {
      const parsed = parseWith(z.object({ role: z.enum(roles), project_id: uuid.optional() }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const organization = await getActiveOrganization(context);
      if (!organization || !mayAdminister(organization.role)) return apiError("Organization administrator permission required.", 403, id);
      const { error } = await context.supabase.rpc("update_member_role_with_audit", { p_organization_id: organization.organization_id, p_user_id: segments[1], p_role: databaseRole(parsed.value.role), p_project_id: parsed.value.project_id ?? null });
      if (error) return errorForDb(error, id);
      return apiResponse({ user_id: segments[1], role: parsed.value.role }, 200, id);
    }
    if (segments[0] === "members" && segments[1] && segments[2] === "status") {
      const parsed = parseWith(z.object({ status: z.enum(["active", "suspended", "removed"]) }).strict(), body);
      if (!parsed.ok) return apiError("Validation failed.", 422, id, parsed.details);
      const organization = await getActiveOrganization(context);
      if (!organization || !mayAdminister(organization.role)) return apiError("Organization administrator permission required.", 403, id);
      const { error } = await context.supabase.rpc("update_member_status_with_audit", { p_organization_id: organization.organization_id, p_user_id: segments[1], p_status: parsed.value.status });
      if (error) return errorForDb(error, id);
      return apiResponse({ user_id: segments[1], status: parsed.value.status }, 200, id);
    }
    return apiError("API route not found.", 404, id);
  } catch {
    return apiError("The request could not be completed.", 500, id);
  }
}
