import { z } from "zod";

export const taskCreateSchema = z.object({
  project_id: z.string().uuid(),
  title: z.string().trim().min(1).max(180),
  description: z.string().trim().max(12000).default(""),
  priority: z.enum(["low", "normal", "high", "urgent"]).default("normal"),
  due_at: z.string().datetime().nullable().optional(),
  assignee_ids: z.array(z.string().uuid()).max(30).default([])
});

export const sampleCreateSchema = z.object({
  project_id: z.string().uuid(),
  sample_code: z.string().trim().min(1).max(80),
  sample_type: z.string().trim().min(1).max(120),
  source_description: z.string().trim().max(4000).nullable().optional(),
  collected_at: z.string().datetime().nullable().optional(),
  received_at: z.string().datetime().nullable().optional(),
  storage_conditions: z.string().trim().max(2000).nullable().optional()
});

export const meetingCreateSchema = z.object({
  project_id: z.string().uuid(),
  title: z.string().trim().min(1).max(180),
  meeting_at: z.string().datetime(),
  location_or_link: z.string().trim().max(500).nullable().optional(),
  agenda: z.string().trim().max(12000).nullable().optional()
});

export const documentCreateSchema = z.object({
  project_id: z.string().uuid(),
  title: z.string().trim().min(1).max(240),
  description: z.string().trim().max(8000).nullable().optional(),
  category: z.enum(["research_paper", "procedure", "result", "formulation", "report", "meeting_minutes", "manual", "presentation", "other"]).default("other"),
  visibility: z.enum(["project", "restricted"]).default("project")
});
