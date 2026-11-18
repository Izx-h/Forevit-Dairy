# Forevit data dictionary

This document describes the initial schema in `supabase/migrations/202611180001_initial_schema.sql`. It defines database structure and policy boundaries only; it does not contain production research records, private member data, credentials, storage objects, or provider configuration. All primary identifiers are UUIDs. Temporal fields use `timestamptz` to represent instants; applications should serialize them as UTC ISO-8601. Mutable business records generally carry `created_by` and `updated_by`; append-only records carry creator/actor attribution and timestamps.

## Identity, organizations, and projects

| Table | Purpose and key relationships |
|---|---|
| `profiles` | Application profile for a Supabase Auth user (`id` references `auth.users`). Includes display/contact metadata. Platform-owner elevation is guarded against self-service changes. |
| `organizations` | Tenant/workspace identity; slug is globally unique. |
| `organization_members` | User membership and organization-level role/status; unique per organization/user. Roles are Project Lead, Secretary, Researcher, and Viewer. |
| `projects` | Project within an organization; organization-scoped slug uniqueness. |
| `project_members` | Active project membership and project-scoped role. Project membership alone does not bypass the requirement for active organization membership. |
| `invitations` | Invite metadata, organization role, optional `project_id`/`project_role`, and expiry. The composite project/organization foreign key prevents cross-organization invitations. Only `token_hash` is stored, never a raw invitation token; acceptance hashes the submitted token and checks the verified Auth email. |

Platform Owner is a platform-level profile flag, not an organization/project membership role. The protected column is only changeable by trusted service-role provisioning; no public registration or first-owner setup is implied by this migration.

## Knowledge repository and processing

| Table | Purpose and key relationships |
|---|---|
| `documents` | Project document identity, descriptive metadata, category, visibility and approval/archive state. |
| `document_versions` | Immutable numbered file metadata; unique per document/version. Records the private bucket/path and SHA-256 hex digest; database rows do not contain file bytes. Composite foreign key keeps the version within its project. |
| `document_tags`, `document_tag_links` | Project-scoped tag vocabulary and document links; composite foreign keys prevent cross-project linking. |
| `research_entries` | Project research notes/observations/literature notes/hypotheses with status and generated full-text search vector; may point to a source document version. |
| `document_processing_jobs` | Durable extraction/OCR/chunk/embed/reindex work with idempotency key, bounded attempt count, retry time, lock metadata, per-claim lease token and error state. |
| `document_chunks` | Derived, project-scoped text slices with page/section metadata, PostgreSQL full-text vector, optional pgvector embedding, and migration-004 processing job/token metadata. A trigger locks and renews the active parent job in the same transaction as each insert/upsert. `embedding` is deliberately unbounded (`vector`, no fixed dimension) because no provider/model dimension was selected. Similarity comparisons require matching dimensions and never grant access. |

Full-text indexes are provided for document titles/descriptions, research entries, and document chunks. Semantic retrieval must apply project/document authorization before returning excerpts or citations. Extracted chunks remain derived artifacts; the original private object and its immutable version are authoritative.

## Samples and laboratory evidence

| Table | Purpose and key relationships |
|---|---|
| `samples` | Project-scoped sample identity, unique sample code within project, provenance, collection/receipt and storage metadata. |
| `lab_tests` | Planned/performed test linked to a sample in the same project; carries a constrained workflow state. |
| `lab_assignments` | Append-only assignment history for test researchers; ended assignments are retained rather than deleted. |
| `lab_test_procedures` | Immutable link from a test to the exact procedure `document_versions` used. |
| `lab_results` | Append-only numbered result revisions tied to a test; later revisions must identify a superseded result and correction reason. Status is constrained. |
| `lab_measurements` | Append-only measurements linked to a result. A check enforces exactly one of `numeric_value` and `text_value`; every measurement includes explicit unit and method. No unit conversion or inference is implied. |
| `lab_result_documents` | Append-only attachment link from result to immutable document version. |
| `lab_reviews` | Append-only approval/change-request decisions with reviewer, timestamp and comments. |

Scientific evidence, result versions, review history, procedure links, measurements, and attachments are not cascade-deleted. Corrections are new linked revisions, with attribution and a reason where the revision model requires one. A reviewer must use authorized workflow operations; the migration does not imply that a scientific result is guidance or certified safe.

## Formulations

| Table | Purpose and key relationships |
|---|---|
| `formulations` | Stable, mutable identity and lifecycle for a formulation. |
| `formulation_versions` | Immutable numbered versions with batch basis, instructions, rationale, and a same-formulation supersedes link for revisions. |
| `formulation_ingredients` | Immutable, ordered ingredient lines tied to a formulation version, with quantity, explicit unit and interpretation basis. |
| `formulation_trials` | Immutable link from exact formulation version to a laboratory test, with observations. |

Changes to a version's ingredients or instructions are represented as a new formulation version; existing versions are not updated or deleted.

## Tasks and collaboration

| Table | Purpose and key relationships |
|---|---|
| `tasks` | Mutable project task with priority, due time and one of `not_started`, `in_progress`, `submitted`, `under_review`, `approved`, `changes_requested`. A trigger rejects invalid state transitions; `transition_task_status` is the authorized state/review RPC for assignees and reviewers/admins. |
| `task_assignees` | Append-only assignment history; ended assignments are retained. |
| `task_submissions`, `task_submission_documents` | Immutable numbered submissions and links to exact document versions. Submission is separate from approval. |
| `task_reviews` | Append-only approval/change-request decisions, optionally tied to a submission. |
| `task_comments` | Append-only task discussion entries. |

A task status transition emits an `activity_logs` record in the same database transaction. The application should coordinate submissions/reviews and the appropriate transitions transactionally. Overdue is derived from due time and state, not stored as an independent state.

## Meetings and decisions

| Table | Purpose and key relationships |
|---|---|
| `meetings` | Project meeting schedule, agenda, location/link, and constrained meeting state. |
| `meeting_attendees` | Scoped meeting/user attendance state. |
| `meeting_minutes` | Immutable link from meeting to a document version containing minutes. |
| `meeting_decisions` | Immutable decision history, optionally responsible person and same-project follow-up task. |

## Notifications and audit

| Table | Purpose and key relationships |
|---|---|
| `notification_preferences` | Mutable user/project/event/channel preferences for in-app or WhatsApp delivery. |
| `notification_consents` | Append-only consent/revocation evidence for WhatsApp, scoped by organization. The latest event governs current consent. |
| `notifications` | Canonical in-app notification per project/recipient/idempotency key, including optional read time. |
| `notification_deliveries` | Append-only delivery-attempt history with channel, attempt number, provider identifiers, status and error metadata. WhatsApp message content should remain minimal and exclude confidential research detail. |
| `activity_logs` | Append-only attributable audit/action history with optional organization/project scope and structured non-secret details. |

Audit logs and consent evidence must not contain tokens, credentials, private file contents, or unnecessary personal data. Service integrations should use idempotency keys and bounded retries.

## AI jobs, reports, and conversations

| Table | Purpose and key relationships |
|---|---|
| `platform_ai_settings` | Single-row, database-owner-controlled AI processing gate; the hardening migration inserts it disabled, and authenticated roles have no table privileges. |
| `ai_jobs` | Scoped asynchronous AI work with job type/state, idempotency, model/prompt metadata, input references, retry/lock fields, per-claim lease token, timestamps and errors. |
| `ai_reports` | Draft-first report content, reporting period, review attribution and publication state. Worker drafts carry a processing lease token; a trigger locks and renews the active job in the same insert transaction. Publication requires reviewer and review time. |
| `ai_citations` | Append-only citation references from exactly one AI job or report to exactly one source kind (document version, research entry or document chunk), with page/section/excerpt-hash metadata. Worker citations carry a processing lease token checked transactionally by a trigger. |
| `ai_conversations`, `ai_messages` | Project-scoped conversation metadata and append-only sequenced user/assistant/system messages. Worker assistant messages carry a lease token checked in the same transaction as the insert. Conversations are limited to their creator and eligible project members by policy. |

**AI output is draft/advisory only.** Reports require human review/publication, and AI must not approve experiments, modify source evidence, autonomously decide project actions, or certify food safety. Retrieval is restricted to authorized source material and citations must be reauthorized before links/excerpts are returned. No AI provider or model is selected by this schema.

## Roles and row-level security

RLS is enabled on every public application table in the migration. `is_platform_owner`, `has_org_role`, `has_project_role`, `can_read_project`, and scoped lookup helpers are `SECURITY DEFINER` functions with fixed search paths and row security disabled for the helper's narrowly scoped membership lookup; this avoids recursive membership-table policies. They derive identity from `auth.uid()` and active membership records, not caller-supplied user IDs.

- **Platform Owner:** platform-level oversight through the protected profile flag; policy helpers grant platform-wide scoped visibility/administration. Trusted service-role provisioning is required for owner elevation.
- **Project Lead:** can administer project membership and most project workflows, review results/tasks, and manage project records.
- **Secretary:** can administer project workflows, meetings, invitations and review queues within project scope; organization-level role checks additionally govern organization/invitation administration.
- **Researcher:** can create permitted research, samples, tests, results, documents, formulations, tasks, submissions/comments, and use AI workspaces. Task state changes are limited to assigned work or reviewer/admin authority.
- **Viewer:** read-only. `can_read_project` requires approved visibility/state; viewers cannot insert or update business records. Resource-specific policies apply the appropriate approved/published state.

All non-owner project reads require both active project membership and active organization membership. Policies are explicit per table and separate reads from writes. Append-only tables have no update/delete policy and an additional mutation-rejecting trigger. RLS is not a substitute for server-side authorization, least-privilege grants, secure RPC design, or rechecking access before signed file URLs are issued.

## Transactional RPCs

Authenticated `SECURITY DEFINER` functions use fixed search paths, turn row security off only within the routine, derive the actor from `auth.uid()`, and perform each record/membership/audit write in one database transaction. The exposed creation functions are `create_project_with_audit`, `create_task_with_audit`, `create_sample_with_audit`, `create_meeting_with_audit`, `create_lab_test_with_audit`, and `create_formulation_with_audit`. They validate project/organization membership and, for task creation, validate every assignee as an active member. `accept_pending_invitation` requires a verified Auth email, hashes the submitted bearer token for lookup, and persists only membership/acceptance state and the token hash.

`transition_task_status(p_task_id, p_new_status, p_comment)` checks the state machine and actor role, writes an append-only review when approving/requesting changes (or a task comment for other transitions), changes task status, and emits audit history in the same transaction. A submitted status requires a submission already associated with that actor. Direct authenticated task-status updates are not granted. `claim_document_processing_job` and `claim_ai_job` atomically claim one eligible item using `FOR UPDATE SKIP LOCKED`; execution is restricted to `service_role`. Migration 004 assigns a fresh lease token per claim and adds write triggers that lock/renew the job row while validating its token for worker side effects.

## Storage, migration, and seed safety

The migration stores only object bucket/path metadata and intentionally does not create a Storage bucket or Storage policies: it does not assume the Supabase `storage` schema is available. Before file operations are enabled, provision a **private** bucket and separately review path parsing and Storage object policies that bind the authenticated user to the organization/project encoded in a validated object path. Parsing must reject malformed paths safely. Never make research files publicly readable. Bucket selection, size/MIME validation, upload authorization, short-lived signed URLs, retention, and backups remain environment/application setup items.

`pgcrypto`, `citext`, and `vector` extensions are requested by the migration. The deployment must confirm that the target PostgreSQL/Supabase environment permits these extensions. No model dimension is asserted for embeddings. The migration contains no project-specific users or records; `supabase/seed.sql` is intentionally comment-only and inserts no records. Apply migrations only to an explicitly selected database after reviewing the target and backing it up as appropriate. No credentials, external calls, deployment, or production data are included here.


## Additive workflow contracts and organization directory

The initial schema is extended by `202611180002_workflow_contracts.sql`. It adds a private `profiles.email` field, a document current-version pointer with a same-document/project guard, `ai_jobs.result_reference`, report review comments and procedure notes. It defines transactional functions for immutable document version registration, research entries, task submissions/reviews, assigned lab tests/results, formulation revisions/trials, meeting minutes/decisions, notification preferences/consent, organization membership updates, report review, and permission-filtered full-text chunk search. The legacy five-argument lab-test creation function is revoked from authenticated users; the six-argument function requires unique, active, non-viewer assignees and the caller among them.

`202611180003_secure_member_directory.sql` adds `get_organization_directory(p_organization_id)`. It returns email only to an authenticated active organization member (or platform owner through the policy helper); application member-directory reads use this RPC. Authenticated roles have no direct SELECT privilege on `profiles.email`. Do not add a direct email join to API or UI code.

The API's signed document download flow first reads the specific document/version through the caller's session and RLS, then creates a 300-second download URL with server credentials. Signed links are bearer capabilities until expiry; keep them out of logs and do not cache them. SQL does not provision Storage buckets or object policies.

## Current implementation boundaries

The AI worker supports explicit `chat`, `analysis`, `comparison`, and `report` job types, but the API queues only evidence-filtered chat and document-analysis jobs, behind `AI_ENABLED=true`. API comparison and report-generation routes remain unavailable because their record-evidence adapters/activity assembly have not been implemented and reviewed. Embeddings, WhatsApp dispatch/webhooks, antivirus scanning and general activity-report assembly remain outstanding. The migrations are static source only and have not been executed against a database.
