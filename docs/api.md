# REST API reference

All application routes are under `/api/v1`. JSON endpoints require an authenticated Supabase session except any future verified provider webhook. Responses include a request/correlation ID. Actor IDs are derived from the session. Project-specific routes require active organization and project membership and relevant capability. The API uses `401` unauthenticated, `403` forbidden, `404` unavailable, `409` conflicts, `422` invalid input, `503` unavailable integration/migration, and `202` queued work.

## Implemented route families

| Method | Route | Purpose |
|---|---|---|
| GET | `/profile`, `/projects`, `/projects/{id}`, `/members` | Signed-in profile, visible projects and organization directory. Member email is returned only via `get_organization_directory` RPC. |
| POST | `/projects`, `/invitations` | Authorized project creation and invited member creation through audited transactional RPCs. |
| PATCH | `/members/{id}/role`, `/members/{id}/status` | Audited role and membership status changes. |
| GET/POST | `/tasks`, `/tasks/{id}/submissions`, `/tasks/{id}/reviews` | Task listing/creation, submission, review; `GET /tasks/summary` provides authorized counts. `PATCH /tasks/{id}` changes task state/priority/due date. |
| GET/POST | `/lab/samples`, `/lab/tests`, `/lab/tests/{id}/procedures`, `/lab/tests/{id}/results`, `/lab/results/{id}/reviews` | Sample/test workflows, exact procedure version, measured result revisions and review. |
| GET/POST | `/documents`, `/documents/{id}/versions`, `/uploads/sign`, `/uploads/complete` | Document metadata, private upload registration and immutable versions. `GET /documents/{id}` includes per-version processing states only when the caller can access the parent document. Version registration transactionally queues extraction. `GET /documents/{id}/download?version_id=...` returns a 5-minute signed URL after visibility checks. |
| GET/POST | `/research`, `/formulations`, `/formulations/{id}/versions`, `/formulations/{id}/trials` | Research notes, formulation identity/version/ingredient and test-trial links. |
| GET | `/formulations/{id}/compare?version_a=...&version_b=...` | Read-only comparison of two same-formulation versions and their ingredients. |
| GET/POST | `/meetings`, `/meetings/{id}/minutes`, `/meetings/{id}/decisions` | Meeting scheduling, minutes links and decision/follow-up records. `GET /meetings/{id}/brief` aggregates authorized project tasks, review queue, documents and decisions; query supports `status`, `member_id`, and `limit`. |
| GET/PATCH | `/notifications`, `/notifications/{id}/read`, `/notification-preferences` | In-app notification retrieval/read and event/channel preference changes through a consent-aware RPC. |
| POST | `/notifications/consent` | Record append-only WhatsApp grant/revocation evidence (`channel`, `consent_status: granted|revoked`, `source`; grant requires E.164 phone and evidence). |
| GET | `/jobs/{id}`, `/ai/reports`, `/ai/reports/{id}` | Authorized job/report status and citations. |
| POST | `/ai/chat`, `/ai/analyze-document` | Evidence-filtered jobs, only when server and worker `AI_ENABLED=true`, the trusted database AI flag is enabled, and indexed authorized chunks match. A narrow transactional RPC creates the conversation, user message and job; returns `202` with job/conversation IDs. |
| POST | `/ai/reports/{id}/review` | Reviewer decision for an existing draft via the transactional report-review RPC. |

Collection endpoints accept `project_id`, `limit` (capped at 100) and a timestamp `before` cursor. See schemas in `src/app/api/v1/[...segments]/route.ts` for exact fields and bounds.

## Not yet implemented / intentionally unavailable

- AI comparison and report-generation submission return `503`: evidence adapters, report activity assembly, complete citation persistence and user review workflow need implementation/review.
- WhatsApp provider dispatch, verified webhook lifecycle, retry/outbox and delivery reconciliation are not available.
- Cursor pagination is timestamp-based rather than a complete compound-key cursor in all collections; `before` is not a substitute for a stable multi-column cursor under heavy concurrent writes.
- A portion of the broader workflow UI and event-driven notifications remains scaffolded. Do not infer completion from an endpoint table or static page.

`/api/health` is a minimal readiness endpoint. Provider webhooks are not accepted by the authenticated catch-all route.
