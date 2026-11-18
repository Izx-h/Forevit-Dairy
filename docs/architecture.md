# Architecture

## Components and trust boundaries

- **Web UI/API:** Next.js App Router, TypeScript and Tailwind. Authenticated server components and `/api/v1` handlers use the Supabase SSR session. The browser does not receive service-role or provider credentials.
- **Identity/data:** Supabase Auth and PostgreSQL. Migrations define organization/project membership, workflow records, audit history, constraints, SECURITY DEFINER workflow RPCs and row-level security. The app derives the actor from a verified Auth session; project permissions are checked by server handlers and database functions.
- **Private files:** Supabase Storage. The expected bucket is private. Upload registration checks project access, caller-scoped path, size, MIME allowlist, selected file signature and SHA-256. Download links are short-lived and only issued after the session client can read the document version. Bucket policies and provisioning remain deployment responsibilities.
- **Worker:** Python process claims durable document and AI jobs with service credentials. It extracts supported text formats, preserves page/section metadata, chunks content and stores citations. Its service-role access bypasses RLS, so it independently validates project membership, document visibility and explicit evidence IDs. Migration 004 adds per-claim lease tokens and write triggers that lock/renew the parent job in the same transaction as each chunk, assistant-message, report or citation write, preventing stale workers from committing side effects after recovery.
- **Providers:** DeepSeek is worker-side only. WhatsApp credentials are reserved in the environment template but no dispatcher/webhook integration is complete. Embeddings are not configured.

## Current flows

1. Invited user signs in through Supabase Auth. A trusted invitation-acceptance function verifies the JWT email and token digest before granting membership.
2. A signed-in request validates shape and project capability, then reads through user-scoped RLS or invokes a narrow transactional RPC that writes business state and audit history.
3. File uploads use a signed upload URL for a caller/project path; completion downloads and verifies the object before immutable version registration.
4. AI chat/document analysis is disabled unless the API and worker each have `AI_ENABLED=true` and a trusted database administrator explicitly enables `platform_ai_settings.ai_enabled` (the migration creates this flag as false). The database check prevents authenticated clients from bypassing the API gate and directly queueing work. When enabled, the API calls an authorized full-text search function, creates a conversation and user message, and stores only selected chunk IDs plus the requester and destination. The worker rechecks membership, visibility and project ownership before processing; citations reference the selected evidence. No evidence means no job.
5. AI comparisons and activity-report assembly currently return unavailable. Worker support for generic comparison/report job types does not mean the app's evidence assembly, citations or review UI are complete.

## Data integrity

Documents and formulation versions, task submissions/reviews, lab results/measurements/reviews, meeting minutes/decisions and audit events are designed as append-only evidence. Corrections create linked revisions. Status transitions and privilege-sensitive mutations use PostgreSQL functions, not client-side UI state alone. `TODO.md` records outcomes not yet evidenced as complete.

## Deployment state

The Webdev project is configured with an application server on port 3000; managed database is disabled and auto-publish is off. No SQL has been executed, no deployment was made, and no production credentials or external integrations are configured. See `operations.md` for the manual deployment gates.
