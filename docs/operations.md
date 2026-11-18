# Operations and security runbook

## Current state and safety gates

This repository has not been connected to a production Supabase project, migrations have not been applied, the worker has not been deployed, and the application has not been published. The managed Webdev database is disabled and auto-publish is disabled. Do not enable service credentials or public hosting until each gate below is reviewed. No demo seed records are provided.

## Provisioning sequence (manual, controlled)

1. Create separate Supabase development, staging and production projects. Confirm Postgres extensions (`pgcrypto`, `citext`, `vector`), region, backup plan, Auth settings, private Storage and Realtime policy.
2. Review all SQL in timestamp order (`202611180001_initial_schema.sql` through `202611180004_write_hardening_and_job_recovery.sql`) against the target and current Supabase/PostgreSQL behavior. The fourth migration revokes browser table writes in favor of audited RPCs, transactionally enqueues extraction on document-version registration, scopes job visibility to parent document access, and reclaims jobs after a 30-minute stale lease. Per-claim lease tokens fence state transitions; database triggers also lock and renew the current job in the same transaction as chunk/message/report/citation writes, fencing stale side effects. Jobs that exhausted attempts fail terminally. Run in development first; capture query plans, policy/RPC and stale-worker race tests, and a rollback strategy. No migration is self-applying from this repository.
3. Provision one trusted Platform Owner through a separately controlled service-role operation. Public signup remains off. Create the initial organization/project and invite only verified members. Document governance, ownership and access revocation.
4. Create a **private** bucket named by `SUPABASE_STORAGE_BUCKET` (default `forevit-private`). Review object policies and test cross-project, cross-user, expired-link and path-traversal cases. Confirm download links expire quickly. Storage is not created by SQL migrations.
5. Put server-only values in the host's encrypted secret manager. Build-time browser variables must never contain service/provider credentials. Use HTTPS, secure cookies, trusted `APP_BASE_URL`, rate limiting, security headers and protected logs.
6. Deploy the web server and worker separately. Keep `AI_ENABLED=false` in both runtimes unless approved; the API rejects requests and the worker does not claim AI jobs unless explicitly enabled. The migration also creates `platform_ai_settings.ai_enabled=false`; authenticated roles cannot change it, and a trusted database administrator must separately approve and enable it before the AI queue RPC accepts work. If enabled, provide DeepSeek secrets only to the worker and set queue limits, timeout, retry, retention and monitoring.
7. Configure notifications only after designing a durable transactional outbox, dispatcher, idempotency keys, consent capture, provider templates, signature verification and replay defense. Current WhatsApp delivery is not implemented.
8. Before production, test restore of both database and private objects, access revocation, job backlog recovery, error redaction, capacity limits, staged migration/rollback and incident response. Assign a named technical owner and data-governance owner.

## Environment variable inventory

Use `.env.example` for names only. Relevant values include `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (server/worker only), `APP_BASE_URL`, `AI_ENABLED` (default false), `DEEPSEEK_API_KEY`, `DEEPSEEK_MODEL`, `EMBEDDING_*`, `WHATSAPP_*`, `DATABASE_URL` / `JOB_QUEUE_URL`, and `SUPABASE_STORAGE_BUCKET`. Never commit actual values. Rotate any accidentally exposed key immediately.

## Worker operation

The worker atomically claims `document_processing_jobs` and `ai_jobs`; it uses bounded retry timing, safe error codes, and the SQL lease-recovery path after a 30-minute stale lock. Per-claim tokens fence job state changes, and database triggers make each chunk/message/report/citation write conditional on the active token while locking the job row. Registering a document version enqueues extraction in the same database transaction. AI remains disabled by default at the API and worker environment gates and the private database setting described above. Test with synthetic files and test-only accounts. Extraction supports TXT/PDF/DOCX/XLSX/PPTX; OCR needs Poppler/Tesseract. It checks document checksums and stores page/section chunks. Embeddings, virus scanning, notification delivery and activity-report assembly are not implemented. Monitor worker liveness, queued/failed/terminal jobs, processing duration, Storage and provider errors without logging text or credentials.

## Privacy and retention

Limit external AI inputs to authorized evidence. Uploaded file contents, credentials, tokens and phone numbers must not appear in logs. Define document, prompt, conversation, generated-report and audit retention with the group. AI output is advisory, never a source record, safety certification or autonomous approval.

## Release and recovery

Use reviewed changes from `main`; run typecheck, lint, tests, build and worker tests. Apply database changes before compatible code only after review, with a tested backup and rollback path. The repository push is not a deployment. Keep secrets, research data, private uploads, generated credentials and build output out of Git. Publish/deploy only under separate explicit authorization.
