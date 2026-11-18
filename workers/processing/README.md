# Forevit processing worker

A small Python background worker that claims document-processing and AI jobs through Supabase REST RPCs. It uses the environment-provided Supabase URL/service-role credential and (optionally) a server-side DeepSeek API key. Missing Supabase configuration stops startup before a client is created. Missing `DEEPSEEK_API_KEY` never triggers a provider request and fails claimed AI jobs with the safe `provider_not_configured` code and bounded retry timing.

## Run and test

From this folder:

```sh
python -m pip install -r requirements.txt
PYTHONPATH=src python -m unittest discover -s tests -v
PYTHONPATH=src python -m forevit_worker.worker
```

## Environment

Required: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`. `WORKER_ID` may be set to a UUID; otherwise a per-process UUID is generated. Optional: `AI_ENABLED` (defaults to `false`), `DEEPSEEK_API_KEY`, `DEEPSEEK_BASE_URL` (defaults to `https://api.deepseek.com`), `DEEPSEEK_MODEL` (defaults to `deepseek-chat`), `DEEPSEEK_MAX_TOKENS` (bounded 128–4096), `WORKER_POLL_SECONDS`, `HTTP_TIMEOUT_SECONDS`, `MAX_FILE_BYTES`, `CHUNK_CHARS`, `CHUNK_OVERLAP`, and `LOG_LEVEL`. Secrets must be provisioned by the runtime secret manager; do not put credentials in this directory, image, source control, or logs.

## Processing behavior

- Claims through `claim_document_processing_job(p_worker_id)` and `claim_ai_job(p_worker_id)`; each claim receives a fresh lease token. Conditional status updates require that token, and migration-004 database triggers lock/renew the parent job row while validating the token in the same transaction as each chunk or AI side-effect write. A recovered stale worker therefore cannot overwrite job state or commit new side effects after the new claim. Expired processing leases are retried after 30 minutes; terminal attempts fail safely. Worker processes should use unique IDs.
- Downloads document versions from private Storage, applies a byte cap and SHA-256 check, extracts TXT/PDF/DOCX/XLSX/PPTX, and writes source-aware chunks carrying job/token metadata, using the schema's `(document_version_id, chunk_no)` uniqueness for idempotent upsert. PDF OCR is optional via Poppler + Tesseract. Embedding jobs fail safely because no embedding provider is configured.
- AI requests are limited to explicit project-scoped chunk/research-entry IDs in `input_reference`; the worker rechecks project IDs, caps excerpts, treats content as untrusted, requires evidence, and stores lease-token-bearing chat answers in `ai_messages`, report drafts in `ai_reports`, and citations in `ai_citations`. It does not rely on `ai_jobs.result_reference`.
- Logs contain job identifiers, event types, stable safe error codes and retryability only; exception bodies, document text, credentials, and provider responses are not logged. SIGTERM/SIGINT stop polling gracefully.

## Boundaries and operational caveats

`AI_ENABLED` must be `true` in both the API and worker environments, and a trusted database administrator must separately enable the private `platform_ai_settings.ai_enabled` flag. The API rejects new AI requests when false; the worker does not claim AI jobs when false, and the database blocks queueing and claim RPCs when its flag is off. Keep all gates disabled unless an administrator approves processing. The current API queues evidence-filtered chat and document-analysis only. API comparison and report-generation routes remain unavailable until their evidence adapters, activity-report assembly, citation handling and review path are implemented. This worker does not implement notification delivery, embeddings, antivirus scanning, general activity-report assembly, or arbitrary SQL/database access. Sequence allocation in chat currently uses read-then-insert; deployments with concurrent same-conversation jobs should add a transactional message-append RPC or sequence allocator. OCR, parsers, and provider availability depend on runtime libraries/system packages and configured secrets. These files are not a claim of production readiness; validate migration compatibility, policies, workload limits, retention, and monitoring in a controlled environment.
