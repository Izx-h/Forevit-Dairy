# Forevit Dairy — Implementation Plan

## Goal and scope

Deliver the private, invite-only Forevit Dairy research and project workspace described in the supplied system and deployment specification. Support 10–30 members on desktop and mobile browsers, with an installable PWA. Preserve the complete feature set: project dashboard and meeting brief; project-scoped membership and roles; samples, laboratory tests, exact procedure versions, measurements, result revisions and reviews; research documents with metadata, tags, versions and authorized search; immutable formulation versions, ingredients and linked trials; accountable tasks, submissions, reviews and comments; meetings, minutes, decisions and linked follow-up work; evidence-grounded AI chat, document analysis, experiment/formulation comparison and draft reports; canonical in-app notifications; and consent-based WhatsApp delivery and verified callbacks.

Source data remains authoritative. Approved scientific records and document versions are retained; corrections are new, attributed revisions. AI suggestions do not approve experiments, alter source records, or certify food safety. Example lab measurements must not be presented as processing or safety guidance. No production research data, user uploads, real credentials, or generated secrets go in the repository.

## Implementation approach

- **Web application:** Next.js App Router with TypeScript, Tailwind CSS and shadcn/ui components, plus server-side route handlers under `/api/v1`. Build a responsive workspace shell, project switcher, role-aware navigation, searchable module views, structured record forms, review queues, timelines, and dashboard summaries derived from actual records. Keep interface permissions as affordances only; server handlers and database policies enforce access.
- **Identity and authorization:** Supabase Auth for verified, invite-only accounts. Resolve a user's organization and project memberships on the server; enforce the Platform Owner, Project Lead, Secretary, Researcher, and Viewer capabilities with project-scoped roles. Do not add public sign-up. Provide visible signed-out, access-denied, loading, and empty states.
- **Data and files:** Supabase PostgreSQL is the external relational system specified by the user; use versioned SQL migrations, UUID keys, UTC timestamps, foreign keys, scoped uniqueness, indexes, checks, and Row Level Security on client-reachable tables. Use private Supabase Storage buckets and short-lived signed access after authorization. Preserve metadata, checksums, immutable document versions and linked source locations. Use PostgreSQL full-text search plus `pgvector` retrieval with authorization filters; vector similarity is not an access check.
- **Research workflows:** Model samples → tests → assignments/procedures → result revisions → measurements/reviews; formulations → immutable versions → ingredients/trials; tasks → assignees → submissions → reviews/comments; meetings → attendees/minutes/decisions/tasks. Use explicit state transitions, append-only review/audit history, correction reasons, and transactional audit/notification creation.
- **AI and asynchronous work:** Add job and citation contracts for ingestion, text extraction/OCR status, chunking, embeddings, AI analysis/comparison and report drafting. The Python worker is a separate deployable under `workers/processing`, consuming a durable queue with bounded retries, idempotency and visible error states. DeepSeek calls remain server/worker-only and receive only authorized, relevant excerpts. Store model/prompt metadata and citations; reports remain drafts until an authorized human reviews and publishes them.
- **Notifications:** Create canonical in-app notifications from business events. Track WhatsApp consent, preference, delivery attempts, provider identifiers and status separately. Include signature verification and idempotent webhook handling. WhatsApp content stays minimal and avoids confidential result/document details.
- **PWA and privacy:** Provide an application-owned manifest, branded icons and installable responsive experience. Avoid caching private records or authenticated API responses in a service worker. Use safe response headers and cookie settings compatible with HTTPS Preview; browser-facing URLs remain relative.
- **Configuration and operations:** Commit `.env.example` with names and explanations only. Keep Supabase service-role, DeepSeek, WhatsApp and queue credentials in protected server-side configuration. Document separate development/staging/production resources, migrations, backups/restore verification, monitoring, retention, worker deployment and operational ownership. The preview can show configuration-needed states until the owner supplies provider settings; never fake an authenticated member or seed real research data.

## Design

Three alternatives (probabilities drawn from the low tail, each below 0.10):

1. **Field Notes Modernism — 0.0999 (selected):** an editorial research workspace balancing tactile field-note warmth with rigorous data density.
2. **Clinical Precision — 0.0706:** a restrained, high-contrast institutional console optimized for review queues and measurement tables.
3. **Laboratory Archive — 0.0379:** a quiet archival interface emphasizing provenance, version history and documentary context.

### Selected direction: Field Notes Modernism

- **Design movement:** Contemporary field-journal editorial design translated into a disciplined research instrument.
- **Core principles:** make provenance visible; separate source facts from interpretation; use dense data only where it improves decisions; make review and revision states unmistakable.
- **Color philosophy:** warm mineral paper backgrounds and ink-like charcoal reduce the feel of a generic SaaS console; deep tea green signals trusted workspace actions; muted amber calls attention to review or due states without implying scientific meaning. Signature brand color: deep tea green `#145447`.
- **Layout paradigm:** persistent narrow navigation rail on desktop, project context in a compact header, and broad record-oriented work areas. Dashboards use a slim metrics band and asymmetric activity/review columns rather than a centered card grid. On mobile, collapse navigation and prioritize the current project and next action.
- **Signature elements:** a compact provenance strip (author, version, timestamp); specimen/version chips with monospace identifiers; a vertical activity/revision trail on record detail pages.
- **Interaction philosophy:** explicit save/submission/review steps, clear irreversible-vs-revisable distinctions, inline validation, calm confirmation, and no hidden state transitions.
- **Animation:** restrained opacity/position transitions for panels and state changes; no decorative looping motion; respect reduced-motion preferences.
- **Typography:** Geist Sans for interface and long-form reading, Geist Mono for sample codes, units, version IDs and timestamps. Use a clear hierarchy with tabular numeric alignment in measurement tables.
- **Brand essence:** “The accountable research workspace for Forevit Dairy’s camel-milk processing group.” Personality: grounded, meticulous, collaborative.
- **Brand voice:** concise and evidence-oriented. Examples: “Every result has a source.” “Review the latest work without losing its history.”
- **Wordmark and mark:** lowercase “forevit” wordmark with a small geometric droplet nested in an open-book/sample-vessel outline; use as an inline vector mark, not generic stock art.

## Project structure

```text
app/
  (auth)/                 sign-in, invite acceptance, account recovery
  (workspace)/            authenticated dashboard and module routes
  api/v1/                 versioned REST route handlers and webhooks
components/                navigation, tables, forms, status, provenance, review UI
features/
  dashboard/ documents/ laboratory/ formulations/ tasks/ meetings/
  notifications/ ai/ members/ projects/
lib/
  auth/ database/ permissions/ validation/ audit/ storage/ jobs/
supabase/
  migrations/ seed.sql    schema, RLS, indexes, functions, non-sensitive demo data
workers/processing/
  src/ ingestion/ extraction/ embeddings/ ai/ notifications/ reports/
  tests/
packages/
  types/ schemas/         shared contracts and validation
public/                    manifest, application icons, route manifest
scripts/                   migration and operational helpers
 docs/                      architecture, API, data dictionary, operations, AI safeguards
```

## Delivery workflow

1. Review and approve this plan, including the selected design direction and external Supabase/DeepSeek/WhatsApp architecture.
2. Create `TODO.md` from the specification’s distinct product outcomes before implementation; keep each item's acceptance clauses explicit and preserve open work accurately.
3. Implement the web shell and domain workflows, SQL migrations/RLS, REST contracts, worker scaffolding, security documentation and PWA assets in small coherent batches. Use only non-sensitive demo fixtures, clearly labeled as examples.
4. Run configured TypeScript diagnostics, lint/build and focused schema/API/worker tests; resolve confirmed issues. Start the Preview only after meaningful UI exists and verify the route manifest.
5. Review the implementation against the specification with a read-only validation pass. Request external provider secrets only when needed through protected input; do not paste or commit them.
6. Fetch and integrate the target repository state, commit the intended files, and push source code to `Izx-h/Forevit-Dairy` on `main` after checks. Repository visibility is public by the user's explicit choice. Exclude `.env*` values, uploads and records; preserve the separate Manus checkpoint workflow as required by the project host.

## Boundaries and unresolved runtime inputs

This implementation does not authorize a production release, create real member accounts, or claim that third-party integrations are live without their separately configured credentials and verified endpoints. No external Supabase, DeepSeek, WhatsApp, or queue secrets have been supplied. The product specification does not prescribe a project timeline, milestones, duration, or progress tracker, so none will be added.
