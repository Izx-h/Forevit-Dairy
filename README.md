# Forevit Dairy research workspace

A responsive, invite-only research and project-coordination workspace for laboratory work, samples, private documents, formulation versions, tasks, meetings and accountable review. This repository contains a Next.js/TypeScript/Tailwind application, Supabase PostgreSQL/RLS migrations and a separate Python processing worker. It contains no production research records or real credentials.

## Status

This is a source implementation, not a deployed or production-ready service. The database migrations have **not** been applied to a Supabase project, no production data or provider credentials were supplied, and the app has not been published. AI defaults off behind API/worker `AI_ENABLED` gates and a separate database flag created false in migration 004; see `docs/operations.md`. Current API support queues evidence-grounded chat/document-analysis only; AI comparison/report activity assembly, embeddings, WhatsApp delivery/webhooks, notification dispatch and antivirus scanning remain incomplete. Review `TODO.md` and `docs/operations.md` before any deployment.

## Local development

Requirements: Node.js 22+, pnpm 11.25, and (for the worker) Python 3.11+.

```sh
cp .env.example .env.local
pnpm install --frozen-lockfile
pnpm dev
```

The application can render its signed-in workspace only after a Supabase project is configured. Public signup is not enabled; create a trusted first owner and organization through a separate reviewed provisioning procedure, then invite members. Never use a service-role key in browser code. Run checks with `pnpm typecheck`, `pnpm lint`, `pnpm test`, and `pnpm build`.

Worker development and tests:

```sh
cd workers/processing
python -m pip install -r requirements.txt
PYTHONPATH=src python -m unittest discover -s tests -v
```

See `workers/processing/README.md` for its environment contract and implementation caveats.

## Repository layout

- `src/app/` — App Router pages and versioned REST handler (`/api/v1`).
- `src/components/` — workspace and form components.
- `src/lib/` — Supabase session/admin clients, authorization, domain and data helpers.
- `supabase/migrations/` — structure, RLS, workflow and secure-directory RPCs, and write-hardening/job-recovery migration. Migrations are source artifacts only; apply them only after review against an explicitly selected database.
- `workers/processing/` — Python document extraction/chunking and evidence-grounded AI worker.
- `docs/` — architecture, API, data dictionary and operations/security notes.

## Security and operations

Invite-only access, project-scoped roles and database RLS are intended security boundaries, not a substitute for deployment review. Use a private Supabase Storage bucket; the app issues short-lived signed links only after an authenticated database visibility check. Configure separate development/staging/production resources and store real credentials only in hosting secret stores. Review `docs/operations.md`, test restore procedures, and complete the remaining `TODO.md` outcomes before production use.

The research workspace does not validate food safety, prescribe processing values, or treat AI output as scientific source data. AI answers are advisory and require verification against their cited records.
