# Forevit Dairy — Delivery outcomes

Status legend: **Open** = not yet delivered; **In progress** = implementation underway; **Complete** = delivered with evidence.

## 1. Invite-only identity, organization, projects, and access control — Open
- Implement Supabase Auth for verified accounts, invitations, sign-in, password recovery and session handling; public sign-up is disabled unless explicitly enabled later.
- Provide the Platform Owner, Project Lead, Secretary, Researcher and Viewer roles. Project membership and permissions are scoped to the organization/project; having an account alone grants no access to a project.
- Support profiles and phone/contact preferences, organization membership/status, project membership/overrides, invitations with hashed tokens and expiry, and revocation/deactivation when a member leaves.
- Enforce permissions in PostgreSQL RLS and server-side handlers, not only by hiding UI controls. Sensitive membership/role changes require authorized roles and create audit events.

## 2. Project dashboard and meeting brief — Open
- Show projects, recent activity, pending and submitted tasks, lab records awaiting review, recently added knowledge, and meeting decisions.
- Derive counts from authorized database records; do not hard-code dashboard totals.
- Filter a meeting brief by project, member, status and reporting period. Assemble it from actual task, review, document, laboratory, meeting and decision records.
- Provide useful loading, empty, error and permission-denied states without leaking inaccessible project data.

## 3. Laboratory and sample lifecycle — Open
- Register project-scoped samples with unique project sample codes, type, source/provenance, collection/receipt dates, storage conditions, creator and timestamps.
- Create tests linked to a sample, objective, status/planned time, creator and assigned researchers. Link the exact procedure document version used.
- Record performed conditions, equipment, observations, deviations, conclusions, attachments and one or more measurements. A measurement stores a named parameter, exactly one of numeric or text value, explicit unit and method, and optional notes; do not silently infer/convert units.
- Submit numbered result revisions; retain approved results and prior reviews append-only. Corrections create attributed, timestamped revisions linked to the superseded result and reason.
- Let authorized reviewers approve a result or request correction, with reviewer, decision, comments and timestamp. Keep procedure/sample/test/result/review/attachment relationships traceable.
- Do not present example pH, temperature or processing-time values as validated processing or food-safety guidance; the system must not certify food safety.

## 4. Knowledge repository and document processing — Open
- Register project documents for papers, procedures, results, formulations, technical reports, minutes, manuals, presentations and other project material with title, description, category, visibility, contributor, upload time, metadata and tags.
- Preserve immutable numbered document versions and file name, MIME type, size, storage bucket/path, checksum, author, timestamp and change note. Store actual files in private object storage, not in database rows or Git.
- Support authorized metadata and full-text search. Provide permission-filtered semantic search with `pgvector`; similarity is never an authorization check.
- Track document processing jobs and extraction/indexing state. Preserve document version, project, page/section and metadata for extracted chunks and citations. Support OCR for scanned files and retain originals as authoritative; extraction artifacts are derived.
- Validate file extension/type/size/checksum and issue short-lived signed upload/download URLs only after authorization. Keep private storage scoped by project/document; surface processing failures to authorized users and support safe retry without duplicate chunks.

## 5. Formulation register and trials — Open
- Keep a stable formulation identity with immutable, numbered formulation versions, status, batch basis, instructions, author, creation time, change rationale and superseded version link.
- Record ingredients with name, quantity, unit, interpretation basis (for example percentage by mass or amount per batch), sequence and notes.
- Link trials to the exact formulation version and laboratory test, with observations, author and timestamp; comparisons must not overwrite prior versions.

## 6. Task accountability and review workflow — Open
- Create project tasks with title, description, priority, optional due date, creator and timestamps; assign one or more members and preserve assignment history.
- Implement the states `not_started`, `in_progress`, `submitted`, `under_review`, `approved`, and `changes_requested` with validated transitions. Derive overdue from due date and state rather than storing it as a status.
- Keep submission distinct from approval: store numbered submissions, submitter, description/time and linked documents; reviewers append an approval or changes-requested decision with comments/time.
- Preserve task status changes, assignments, submissions, reviews and comments in history. Support task discussion, per-person/project task summaries and pending/completed/overdue/submitted views.

## 7. Meetings, decisions, and follow-up — Open
- Store project meeting title, date/time, location/link, agenda, creator and timestamps; associate attendees and attendance status.
- Link submitted minutes to an immutable document version. Store decisions with responsible member and optional task link.
- Generate a meeting brief from current authorized tasks, laboratory reviews, documents and decisions; allow a decision to create or link a follow-up task.

## 8. Evidence-grounded AI assistant and reports — Open
- Allow members to ask questions over accessible project knowledge, analyze documents, compare experiments or formulation versions, and request project activity report drafts for a selected reporting period.
- Retrieve only content the requesting member may access; re-check authorization before returning citations/links. Send only relevant excerpts and minimum necessary context to DeepSeek from server/worker code.
- Require answers to use supplied evidence, cite document/version/page or section/excerpt, distinguish published literature from group observations and hypotheses, identify conflicts/missing evidence, and abstain when support is insufficient.
- Persist AI jobs, requested-by/project scope, job type/status, model identifier, prompt version, start/completion, input reference, conversations/messages, report period/content/status, citations and reviewer metadata. Never store credentials in prompts/logs.
- Reports are drafts for human review; only an authorized reviewer can publish. AI must not approve experiments, change source records, autonomously decide project actions, or certify food safety. Provide an administrator-controlled AI processing disable switch and document retention safeguards.

## 9. In-app notifications and consent-based WhatsApp — Open
- Create canonical in-app notification records for task assignment/submission/review/approval, laboratory submission/review, new research documents/formulation versions, meeting decisions/minutes, enabled due/overdue reminders and AI report generation/publication.
- Store per-event/channel preferences and append-only consent/revocation evidence. WhatsApp delivery is optional and only for opted-in members; in-app notification remains canonical if WhatsApp fails.
- Keep delivery attempts, provider message ID, status, attempt count, last error and timestamps separate from the source event. Use idempotency, bounded retry/backoff and minimal message content; do not send confidential result or document text through WhatsApp.
- Verify WhatsApp callback signatures, reject malformed/replayed events, process callbacks idempotently, record provider/template identifiers and support consent revocation/preferences. Business-initiated messages follow the provider's current template rules.

## 10. Versioned REST API and business rules — Open
- Expose authenticated JSON resource operations under `/api/v1` for profile; invitations/members/role/status; projects; documents/versions; signed uploads; search; research; lab samples/tests/procedures/results/reviews; formulations/versions/compare/trials; tasks/summary/submissions/reviews; meetings/minutes/decisions/brief; notifications/read/preferences; AI chat/analyze/compare/reports; jobs; and WhatsApp callbacks.
- Derive actor identity from a verified Supabase session; never authorize using client-supplied user IDs. Scope every read and write to organization/project membership and document visibility.
- Validate request bodies and state transitions; use pagination, ISO-8601 UTC timestamps, version checks for concurrent changes, and consistent errors: `401` unauthenticated, `403` unauthorized, `404` unavailable, `409` version/state conflict, `422` invalid input. Return a correlation/request ID for traceability.
- Use `202 Accepted` and authorized job resources for long-running work. Rate-limit authentication, search, upload registration and AI operations. Protect against CSRF where relevant, injection, XSS, brute force and abusive upload/search/AI use. Never expose service-role/provider keys, unrestricted storage paths or arbitrary SQL.

## 11. Relational schema, integrity, and audit trail — Open
- Use PostgreSQL UUID primary keys, `timestamptz` UTC timestamps, foreign keys, explicit creator/updater fields for mutable business records, appropriate indexes, checks and scoped unique constraints.
- Include schema for profiles, organizations, organization members, projects, project members, invitations; documents, versions, tags/tag links, research entries, processing jobs, chunks; samples, lab tests/assignments/procedures/results/measurements/result documents/reviews; formulations/versions/ingredients/trials; tasks/assignees/submissions/submission documents/reviews/comments; meetings/attendees/minutes/decisions; notification preferences/consents/notifications/deliveries; activity logs; AI jobs/reports/citations/conversations/messages.
- Preserve approved scientific results, reviews, document versions and audit entries append-only. Corrections create linked revisions with author, timestamp and reason. Use soft archival where retention is needed; avoid cascading deletion of scientific evidence.
- Use constraints/server logic for valid state transitions and transactions for related source/audit/notification writes. Keep idempotency keys for external notifications and background jobs.

## 12. Server, worker, integrations, and deployment documentation — Open
- Keep the Next.js server/API separate from the Python processing worker. Worker responsibilities include ingestion, extraction/OCR, chunking, embeddings, AI jobs, report generation and notification delivery; use durable jobs/queue, visible `queued`/`processing`/`succeeded`/`failed` states, bounded retries/backoff, safe idempotency and graceful shutdown.
- Document the requested Supabase Auth/PostgreSQL/Storage/Realtime/pgvector, DeepSeek server-side API, WhatsApp Business Cloud API and Render worker configuration. Keep real credentials in encrypted environment/secret stores, with only variable names and safe descriptions in `.env.example`.
- Document separate development/staging/production resources and credentials; do not copy production user data into development unless anonymized and authorized. Document reviewed migrations, controlled releases, backward-compatible changes, rollback, HTTPS/domain/health/readiness, monitoring/logging, database backups and restore verification, private-file backups, capacity/storage/job-failure/provider monitoring and operational ownership.
- Do not log secrets, authentication tokens, file contents or unrelated personal data. Make provider data flows, retention and administrator disable controls visible.

## 13. Responsive PWA and interface — Open
- Deliver a mobile-responsive browser workspace for desktop and mobile and an installable PWA; no separate native mobile app is required.
- Provide an application-owned manifest and icons; avoid caching private/authenticated records or API responses in the service worker. Preserve secure, cross-site HTTPS Preview session behavior and do not use absolute URLs derived from internal request hosts.
- Apply the approved Field Notes Modernism design plan with Next.js, TypeScript, Tailwind CSS and shadcn/ui components; provide accessible forms, keyboard/focus behavior, reduced-motion support, legible measurements and explicit scientific provenance/status cues.

## 14. Repository hygiene, documentation, and focused verification — Open
- Keep migrations, shared types/schemas, API contracts and operational documentation in source control. Include `README.md`, architecture, data dictionary, API and operations documents, safe `seed.sql`, `.env.example`, `package.json`, workspace configuration, scripts, and web/worker tests as appropriate.
- Do not commit credentials, production data, private uploads, generated secrets, local environment values or build artifacts. Demo records, if included, must be clearly non-sensitive and must not masquerade as validated scientific guidance.
- Configure TypeScript diagnostics before implementation. Run diagnostics, lint/build and focused schema/API/worker tests; correct actionable findings. Verify the complete `/manus-routes.json` against source routes before Preview use.
- Perform a read-only review against this specification and preserve accurate status on every outcome. Push the intended source commit to the user-selected GitHub repository `Izx-h/Forevit-Dairy` on `main` only after reviewing remote state and checks. The user explicitly approved this repository remaining public; publish source code only, never credentials, research data or uploaded files. Do not publish/deploy the application unless separately requested.
