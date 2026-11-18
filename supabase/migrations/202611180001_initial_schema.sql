-- Forevit private research workspace schema. This migration creates structure only.
-- Timestamps are timestamptz and defaults use the database's UTC instant.
-- AI-generated content is draft/advisory only; it is never food-safety certification.

begin;

create extension if not exists pgcrypto;
create extension if not exists vector;
create extension if not exists citext;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  new.updated_at := statement_timestamp();
  return new;
end;
$$;

create or replace function public.set_notification_update_actor()
returns trigger language plpgsql set search_path = pg_catalog, auth as $$
begin
  new.updated_at := statement_timestamp();
  new.updated_by := auth.uid();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null check (length(btrim(display_name)) > 0),
  phone_e164 text,
  locale text,
  platform_owner boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict
);
create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

-- Platform-owner elevation is provisioned by trusted administration, not self-service.
create or replace function public.guard_platform_owner()
returns trigger language plpgsql set search_path = pg_catalog, auth as $$
begin
  if new.platform_owner is distinct from old.platform_owner
     and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'platform_owner may only be changed by trusted administration';
  end if;
  return new;
end;
$$;
create trigger profiles_owner_guard before update of platform_owner on public.profiles
for each row execute function public.guard_platform_owner();

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$'),
  status text not null default 'active' check (status in ('active','suspended','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict
);
create trigger organizations_updated_at before update on public.organizations
for each row execute function public.set_updated_at();

create table public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  role text not null check (role in ('Project Lead','Secretary','Researcher','Viewer')),
  status text not null default 'active' check (status in ('invited','active','suspended','removed')),
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (organization_id, user_id),
  unique (id, organization_id)
);
create index organization_members_user_status_idx on public.organization_members(user_id, status, organization_id);
create trigger organization_members_updated_at before update on public.organization_members
for each row execute function public.set_updated_at();

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null check (length(btrim(name)) > 0),
  slug text not null,
  description text,
  status text not null default 'active' check (status in ('active','paused','completed','archived')),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (organization_id, slug),
  unique (id, organization_id)
);
create index projects_organization_status_idx on public.projects(organization_id, status);
create trigger projects_updated_at before update on public.projects
for each row execute function public.set_updated_at();

create table public.project_members (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  role text not null check (role in ('Project Lead','Secretary','Researcher','Viewer')),
  status text not null default 'active' check (status in ('invited','active','suspended','removed')),
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (project_id, user_id),
  unique (id, project_id)
);
create index project_members_user_status_idx on public.project_members(user_id, status, project_id);
create trigger project_members_updated_at before update on public.project_members
for each row execute function public.set_updated_at();

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_id uuid,
  email citext not null,
  role text not null check (role in ('Project Lead','Secretary','Researcher','Viewer')),
  project_role text check (project_role in ('Project Lead','Secretary','Researcher','Viewer')),
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  invited_by uuid not null references auth.users(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete restrict,
  check (octet_length(token_hash) >= 32),
  check (accepted_at is null or accepted_at <= expires_at),
  check (not (accepted_at is not null and revoked_at is not null)),
  check ((project_id is null and project_role is null) or (project_id is not null and project_role is not null)),
  foreign key (project_id, organization_id) references public.projects(id, organization_id) on delete restrict
);
create index invitations_org_expiry_idx on public.invitations(organization_id, expires_at) where accepted_at is null and revoked_at is null;
create trigger invitations_updated_at before update on public.invitations
for each row execute function public.set_updated_at();

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  title text not null check (length(btrim(title)) > 0),
  description text,
  category text not null check (category in ('paper','procedure','result','formulation','technical_report','minutes','manual','presentation','other')),
  visibility text not null default 'project' check (visibility in ('private','project','approved')),
  status text not null default 'draft' check (status in ('draft','in_review','approved','archived')),
  metadata jsonb not null default '{}'::jsonb,
  approved_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (id, project_id),
  check ((status = 'approved') = (approved_at is not null))
);
create index documents_project_status_idx on public.documents(project_id, status, category);
create index documents_title_fts_idx on public.documents using gin (to_tsvector('simple', coalesce(title,'') || ' ' || coalesce(description,'')));
create trigger documents_updated_at before update on public.documents
for each row execute function public.set_updated_at();

create table public.document_versions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  document_id uuid not null,
  version_no integer not null check (version_no > 0),
  file_name text not null check (length(btrim(file_name)) > 0),
  mime_type text not null,
  byte_size bigint not null check (byte_size >= 0),
  storage_bucket text not null,
  storage_path text not null,
  sha256_hex text not null check (sha256_hex ~ '^[0-9a-fA-F]{64}$'),
  change_note text,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (document_id, version_no),
  unique (id, project_id),
  unique (storage_bucket, storage_path),
  foreign key (document_id, project_id) references public.documents(id, project_id) on delete restrict
);
create index document_versions_doc_idx on public.document_versions(project_id, document_id, version_no desc);

create table public.document_tags (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  label text not null check (length(btrim(label)) > 0),
  normalized_label text not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (project_id, normalized_label),
  unique (id, project_id)
);

create table public.document_tag_links (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  document_id uuid not null,
  tag_id uuid not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (document_id, tag_id),
  foreign key (document_id, project_id) references public.documents(id, project_id) on delete restrict,
  foreign key (tag_id, project_id) references public.document_tags(id, project_id) on delete restrict
);

create table public.research_entries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  title text not null check (length(btrim(title)) > 0),
  body text not null,
  entry_type text not null check (entry_type in ('observation','literature_note','hypothesis','protocol_note','other')),
  status text not null default 'draft' check (status in ('draft','in_review','approved','archived')),
  source_document_version_id uuid,
  search_vector tsvector generated always as (to_tsvector('simple', coalesce(title,'') || ' ' || coalesce(body,''))) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (id, project_id),
  foreign key (source_document_version_id, project_id) references public.document_versions(id, project_id) on delete restrict
);
create index research_entries_project_status_idx on public.research_entries(project_id, status, created_at desc);
create index research_entries_fts_idx on public.research_entries using gin(search_vector);
create trigger research_entries_updated_at before update on public.research_entries
for each row execute function public.set_updated_at();

create table public.document_processing_jobs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  document_version_id uuid not null,
  job_type text not null check (job_type in ('extract','ocr','chunk','embed','reindex')),
  status text not null default 'queued' check (status in ('queued','processing','succeeded','failed','cancelled')),
  idempotency_key text not null,
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5 check (max_attempts > 0),
  next_attempt_at timestamptz not null default now(),
  locked_by uuid,
  locked_at timestamptz,
  error_code text,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  requested_by uuid not null references auth.users(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete restrict,
  unique (project_id, idempotency_key),
  foreign key (document_version_id, project_id) references public.document_versions(id, project_id) on delete restrict,
  check ((status = 'processing') = (locked_at is not null and locked_by is not null))
);
create index document_processing_jobs_claim_idx on public.document_processing_jobs(status, next_attempt_at, created_at) where status in ('queued','failed');
create trigger document_processing_jobs_updated_at before update on public.document_processing_jobs
for each row execute function public.set_updated_at();

create table public.document_chunks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  document_version_id uuid not null,
  chunk_no integer not null check (chunk_no >= 0),
  page_no integer check (page_no is null or page_no > 0),
  section_label text,
  content text not null,
  search_vector tsvector generated always as (to_tsvector('simple', coalesce(content,''))) stored,
  -- Unbounded vector permits provider-selected dimensions; vectors can only be compared when dimensions match.
  embedding vector,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (document_version_id, chunk_no),
  unique (id, project_id),
  foreign key (document_version_id, project_id) references public.document_versions(id, project_id) on delete restrict
);
create index document_chunks_project_version_idx on public.document_chunks(project_id, document_version_id, chunk_no);
create index document_chunks_fts_idx on public.document_chunks using gin(search_vector);

create table public.samples (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  sample_code text not null check (length(btrim(sample_code)) > 0),
  sample_type text not null,
  source_description text,
  provenance jsonb not null default '{}'::jsonb,
  collected_at timestamptz,
  received_at timestamptz,
  storage_conditions text,
  status text not null default 'registered' check (status in ('registered','active','approved','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (project_id, sample_code),
  unique (id, project_id)
);
create index samples_project_status_idx on public.samples(project_id, status, created_at desc);
create trigger samples_updated_at before update on public.samples
for each row execute function public.set_updated_at();

create table public.lab_tests (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  sample_id uuid not null,
  title text not null check (length(btrim(title)) > 0),
  objective text,
  status text not null default 'planned' check (status in ('planned','in_progress','submitted','under_review','approved','changes_requested','cancelled')),
  planned_at timestamptz,
  performed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  foreign key (sample_id, project_id) references public.samples(id, project_id) on delete restrict,
  unique (id, project_id)
);
create index lab_tests_project_status_idx on public.lab_tests(project_id, status, planned_at);
create trigger lab_tests_updated_at before update on public.lab_tests
for each row execute function public.set_updated_at();

create table public.lab_assignments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  lab_test_id uuid not null,
  assignee_id uuid not null references public.profiles(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  ended_at timestamptz,
  note text,
  created_by uuid not null references auth.users(id) on delete restrict,
  check (ended_at is null or ended_at >= assigned_at),
  foreign key (lab_test_id, project_id) references public.lab_tests(id, project_id) on delete restrict
);
create unique index lab_assignments_one_active_idx on public.lab_assignments(lab_test_id, assignee_id) where ended_at is null;
create index lab_assignments_assignee_idx on public.lab_assignments(project_id, assignee_id) where ended_at is null;

create table public.lab_test_procedures (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  lab_test_id uuid not null,
  procedure_document_version_id uuid not null,
  linked_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (lab_test_id, procedure_document_version_id),
  foreign key (lab_test_id, project_id) references public.lab_tests(id, project_id) on delete restrict,
  foreign key (procedure_document_version_id, project_id) references public.document_versions(id, project_id) on delete restrict
);

create table public.lab_results (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  lab_test_id uuid not null,
  revision_no integer not null check (revision_no > 0),
  supersedes_result_id uuid,
  status text not null default 'submitted' check (status in ('submitted','under_review','approved','changes_requested','superseded')),
  summary text,
  conditions jsonb not null default '{}'::jsonb,
  equipment jsonb not null default '[]'::jsonb,
  observations text,
  deviations text,
  conclusion text,
  correction_reason text,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (lab_test_id, revision_no),
  unique (id, lab_test_id, project_id),
  unique (id, project_id),
  foreign key (lab_test_id, project_id) references public.lab_tests(id, project_id) on delete restrict,
  foreign key (supersedes_result_id, lab_test_id, project_id) references public.lab_results(id, lab_test_id, project_id) on delete restrict,
  check ((revision_no = 1 and supersedes_result_id is null) or (revision_no > 1 and supersedes_result_id is not null and correction_reason is not null and length(btrim(correction_reason)) > 0))
);
create index lab_results_project_status_idx on public.lab_results(project_id, status, created_at desc);

create table public.lab_measurements (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  result_id uuid not null,
  parameter_name text not null check (length(btrim(parameter_name)) > 0),
  numeric_value numeric,
  text_value text,
  unit text not null check (length(btrim(unit)) > 0),
  method text not null check (length(btrim(method)) > 0),
  notes text,
  measured_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  check ((numeric_value is not null)::integer + (text_value is not null)::integer = 1),
  foreign key (result_id, project_id) references public.lab_results(id, project_id) on delete restrict
);
create index lab_measurements_result_idx on public.lab_measurements(result_id, parameter_name);

create table public.lab_result_documents (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  result_id uuid not null,
  document_version_id uuid not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (result_id, document_version_id),
  foreign key (result_id, project_id) references public.lab_results(id, project_id) on delete restrict,
  foreign key (document_version_id, project_id) references public.document_versions(id, project_id) on delete restrict
);

create table public.lab_reviews (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  result_id uuid not null,
  decision text not null check (decision in ('approved','changes_requested')),
  comments text,
  reviewed_at timestamptz not null default now(),
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  foreign key (result_id, project_id) references public.lab_results(id, project_id) on delete restrict
);
create index lab_reviews_result_time_idx on public.lab_reviews(result_id, reviewed_at desc);

create table public.formulations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  name text not null check (length(btrim(name)) > 0),
  description text,
  status text not null default 'draft' check (status in ('draft','active','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (id, project_id)
);
create index formulations_project_status_idx on public.formulations(project_id, status);
create trigger formulations_updated_at before update on public.formulations
for each row execute function public.set_updated_at();

create table public.formulation_versions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  formulation_id uuid not null,
  version_no integer not null check (version_no > 0),
  status text not null default 'draft' check (status in ('draft','in_review','approved','superseded')),
  batch_basis text,
  instructions text,
  change_rationale text,
  supersedes_version_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (formulation_id, version_no),
  unique (id, formulation_id, project_id),
  unique (id, project_id),
  foreign key (formulation_id, project_id) references public.formulations(id, project_id) on delete restrict,
  foreign key (supersedes_version_id, formulation_id, project_id) references public.formulation_versions(id, formulation_id, project_id) on delete restrict,
  check ((version_no = 1 and supersedes_version_id is null) or (version_no > 1 and supersedes_version_id is not null and change_rationale is not null and length(btrim(change_rationale)) > 0))
);
create index formulation_versions_project_idx on public.formulation_versions(project_id, formulation_id, version_no desc);

create table public.formulation_ingredients (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  formulation_version_id uuid not null,
  ingredient_name text not null check (length(btrim(ingredient_name)) > 0),
  quantity numeric not null check (quantity >= 0),
  unit text not null check (length(btrim(unit)) > 0),
  interpretation_basis text not null check (length(btrim(interpretation_basis)) > 0),
  sequence_no integer not null check (sequence_no > 0),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (formulation_version_id, sequence_no),
  foreign key (formulation_version_id, project_id) references public.formulation_versions(id, project_id) on delete restrict
);

create table public.formulation_trials (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  formulation_version_id uuid not null,
  lab_test_id uuid not null,
  observations text,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (formulation_version_id, lab_test_id),
  foreign key (formulation_version_id, project_id) references public.formulation_versions(id, project_id) on delete restrict,
  foreign key (lab_test_id, project_id) references public.lab_tests(id, project_id) on delete restrict
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  title text not null check (length(btrim(title)) > 0),
  description text,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status text not null default 'not_started' check (status in ('not_started','in_progress','submitted','under_review','approved','changes_requested')),
  due_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (id, project_id)
);
create index tasks_project_state_due_idx on public.tasks(project_id, status, due_at);
create trigger tasks_updated_at before update on public.tasks
for each row execute function public.set_updated_at();

create table public.task_assignees (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  task_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  ended_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  check (ended_at is null or ended_at >= assigned_at),
  foreign key (task_id, project_id) references public.tasks(id, project_id) on delete restrict
);
create unique index task_assignees_one_active_idx on public.task_assignees(task_id, user_id) where ended_at is null;
create index task_assignees_user_idx on public.task_assignees(project_id, user_id) where ended_at is null;

create table public.task_submissions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  task_id uuid not null,
  submission_no integer not null check (submission_no > 0),
  description text,
  submitted_at timestamptz not null default now(),
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (task_id, submission_no),
  unique (id, project_id),
  foreign key (task_id, project_id) references public.tasks(id, project_id) on delete restrict
);

create table public.task_submission_documents (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  submission_id uuid not null,
  document_version_id uuid not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (submission_id, document_version_id),
  foreign key (submission_id, project_id) references public.task_submissions(id, project_id) on delete restrict,
  foreign key (document_version_id, project_id) references public.document_versions(id, project_id) on delete restrict
);

create table public.task_reviews (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  task_id uuid not null,
  submission_id uuid,
  decision text not null check (decision in ('approved','changes_requested')),
  comments text,
  reviewed_at timestamptz not null default now(),
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  foreign key (task_id, project_id) references public.tasks(id, project_id) on delete restrict,
  foreign key (submission_id, project_id) references public.task_submissions(id, project_id) on delete restrict
);
create index task_reviews_task_time_idx on public.task_reviews(task_id, reviewed_at desc);

create table public.task_comments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  task_id uuid not null,
  body text not null check (length(btrim(body)) > 0),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  foreign key (task_id, project_id) references public.tasks(id, project_id) on delete restrict
);
create index task_comments_task_time_idx on public.task_comments(task_id, created_at);

create table public.meetings (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  title text not null check (length(btrim(title)) > 0),
  starts_at timestamptz not null,
  ends_at timestamptz,
  location_or_link text,
  agenda text,
  status text not null default 'scheduled' check (status in ('draft','scheduled','completed','published','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (id, project_id),
  check (ends_at is null or ends_at >= starts_at)
);
create index meetings_project_starts_idx on public.meetings(project_id, starts_at desc);
create trigger meetings_updated_at before update on public.meetings
for each row execute function public.set_updated_at();

create table public.meeting_attendees (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  meeting_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete restrict,
  attendance_status text not null default 'invited' check (attendance_status in ('invited','accepted','declined','attended','absent')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (meeting_id, user_id),
  foreign key (meeting_id, project_id) references public.meetings(id, project_id) on delete restrict
);
create trigger meeting_attendees_updated_at before update on public.meeting_attendees
for each row execute function public.set_updated_at();

create table public.meeting_minutes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  meeting_id uuid not null,
  document_version_id uuid not null,
  submitted_at timestamptz not null default now(),
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (meeting_id, document_version_id),
  foreign key (meeting_id, project_id) references public.meetings(id, project_id) on delete restrict,
  foreign key (document_version_id, project_id) references public.document_versions(id, project_id) on delete restrict
);

create table public.meeting_decisions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  meeting_id uuid not null,
  decision_text text not null check (length(btrim(decision_text)) > 0),
  status text not null default 'draft' check (status in ('draft','approved','superseded')),
  responsible_user_id uuid references public.profiles(id) on delete restrict,
  follow_up_task_id uuid,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  foreign key (meeting_id, project_id) references public.meetings(id, project_id) on delete restrict,
  foreign key (follow_up_task_id, project_id) references public.tasks(id, project_id) on delete restrict
);
create index meeting_decisions_project_status_idx on public.meeting_decisions(project_id, status, decided_at desc);

create table public.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  project_id uuid references public.projects(id) on delete restrict,
  event_type text not null,
  channel text not null check (channel in ('in_app','whatsapp')),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (user_id, project_id, event_type, channel)
);
create index notification_preferences_user_idx on public.notification_preferences(user_id, project_id);
create unique index notification_preferences_global_unique_idx
  on public.notification_preferences(user_id,event_type,channel) where project_id is null;
create trigger notification_preferences_updated_at before update on public.notification_preferences
for each row execute function public.set_updated_at();

create table public.notification_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  channel text not null check (channel in ('whatsapp')),
  action text not null check (action in ('granted','revoked')),
  phone_e164 text,
  evidence text,
  occurred_at timestamptz not null default now(),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict
);
create index notification_consents_current_idx on public.notification_consents(user_id, organization_id, occurred_at desc);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  event_type text not null,
  title text not null check (length(btrim(title)) > 0),
  body text,
  source_table text,
  source_id uuid,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  read_at timestamptz,
  created_by uuid references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete restrict,
  unique (project_id, recipient_id, idempotency_key),
  unique (id, project_id)
);
create index notifications_recipient_unread_idx on public.notifications(recipient_id, created_at desc) where read_at is null;
create trigger notifications_updated_at before update on public.notifications
for each row execute function public.set_notification_update_actor();

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  notification_id uuid not null references public.notifications(id) on delete restrict,
  channel text not null check (channel in ('in_app','whatsapp')),
  status text not null check (status in ('queued','sent','delivered','failed','skipped')),
  attempt_no integer not null check (attempt_no > 0),
  provider_message_id text,
  provider_template_id text,
  last_error text,
  attempted_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete restrict,
  unique (notification_id, channel, attempt_no),
  foreign key (notification_id, project_id) references public.notifications(id, project_id) on delete restrict
);
create index notification_deliveries_project_time_idx on public.notification_deliveries(project_id, attempted_at desc);

create table public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  project_id uuid references public.projects(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  occurred_at timestamptz not null default now(),
  request_id text,
  details jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete restrict
);
create index activity_logs_project_time_idx on public.activity_logs(project_id, occurred_at desc);
create index activity_logs_org_time_idx on public.activity_logs(organization_id, occurred_at desc);

create table public.ai_jobs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  job_type text not null check (job_type in ('ingest','analysis','comparison','report','chat')),
  status text not null default 'queued' check (status in ('queued','processing','succeeded','failed','cancelled')),
  idempotency_key text not null,
  model_id text,
  prompt_version text,
  input_reference jsonb not null default '{}'::jsonb,
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5 check (max_attempts > 0),
  next_attempt_at timestamptz not null default now(),
  locked_by uuid,
  locked_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  error_code text,
  error_message text,
  requested_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete restrict,
  unique (project_id, idempotency_key),
  unique (id, project_id),
  check ((status = 'processing') = (locked_at is not null and locked_by is not null))
);
create index ai_jobs_claim_idx on public.ai_jobs(status, next_attempt_at, created_at) where status in ('queued','failed');
create trigger ai_jobs_updated_at before update on public.ai_jobs
for each row execute function public.set_updated_at();

create table public.ai_reports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  ai_job_id uuid references public.ai_jobs(id) on delete restrict,
  title text not null,
  period_start timestamptz,
  period_end timestamptz,
  content_markdown text not null,
  status text not null default 'draft' check (status in ('draft','under_review','published','changes_requested')),
  reviewer_id uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  check (period_end is null or period_start is null or period_end >= period_start),
  check ((status = 'published') = (reviewer_id is not null and reviewed_at is not null)),
  unique (id, project_id)
);
create index ai_reports_project_status_idx on public.ai_reports(project_id, status, created_at desc);
create trigger ai_reports_updated_at before update on public.ai_reports
for each row execute function public.set_updated_at();

create table public.ai_citations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  ai_job_id uuid references public.ai_jobs(id) on delete restrict,
  ai_report_id uuid references public.ai_reports(id) on delete restrict,
  document_version_id uuid,
  research_entry_id uuid references public.research_entries(id) on delete restrict,
  chunk_id uuid references public.document_chunks(id) on delete restrict,
  page_no integer check (page_no is null or page_no > 0),
  section_label text,
  excerpt_hash text,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  foreign key (document_version_id, project_id) references public.document_versions(id, project_id) on delete restrict,
  foreign key (ai_job_id, project_id) references public.ai_jobs(id, project_id) on delete restrict,
  foreign key (ai_report_id, project_id) references public.ai_reports(id, project_id) on delete restrict,
  foreign key (research_entry_id, project_id) references public.research_entries(id, project_id) on delete restrict,
  foreign key (chunk_id, project_id) references public.document_chunks(id, project_id) on delete restrict,
  check (num_nonnulls(ai_job_id, ai_report_id) = 1),
  check (num_nonnulls(document_version_id, research_entry_id, chunk_id) = 1)
);
create index ai_citations_job_idx on public.ai_citations(ai_job_id);
create index ai_citations_report_idx on public.ai_citations(ai_report_id);

create table public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  title text,
  status text not null default 'active' check (status in ('active','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  unique (id, project_id)
);
create index ai_conversations_project_user_idx on public.ai_conversations(project_id, created_by, updated_at desc);
create trigger ai_conversations_updated_at before update on public.ai_conversations
for each row execute function public.set_updated_at();

create table public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete restrict,
  conversation_id uuid not null,
  sequence_no integer not null check (sequence_no > 0),
  role text not null check (role in ('user','assistant','system')),
  content text not null,
  ai_job_id uuid references public.ai_jobs(id) on delete restrict,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete restrict,
  unique (conversation_id, sequence_no),
  foreign key (conversation_id, project_id) references public.ai_conversations(id, project_id) on delete restrict,
  foreign key (ai_job_id, project_id) references public.ai_jobs(id, project_id) on delete restrict
);
create index ai_messages_conversation_idx on public.ai_messages(conversation_id, sequence_no);

-- Safe SECURITY DEFINER membership helpers avoid recursive policies on membership tables.
create or replace function public.is_platform_owner()
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.platform_owner)
$$;

create or replace function public.has_org_role(p_organization_id uuid, p_roles text[] default null)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
  select public.is_platform_owner() or exists (
    select 1 from public.organization_members m
    where m.organization_id = p_organization_id and m.user_id = auth.uid() and m.status = 'active'
      and (p_roles is null or m.role = any(p_roles))
  )
$$;

create or replace function public.has_project_role(p_project_id uuid, p_roles text[] default null)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
  select public.is_platform_owner() or exists (
    select 1 from public.project_members pm
    join public.projects pr on pr.id = pm.project_id
    join public.organization_members om on om.organization_id = pr.organization_id and om.user_id = pm.user_id
    where pm.project_id = p_project_id and pm.user_id = auth.uid()
      and pm.status = 'active' and om.status = 'active'
      and (p_roles is null or pm.role = any(p_roles))
  )
$$;

create or replace function public.can_read_project(p_project_id uuid, p_visibility text, p_approved boolean)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
  select public.is_platform_owner() or exists (
    select 1 from public.project_members pm
    join public.projects pr on pr.id = pm.project_id
    join public.organization_members om on om.organization_id = pr.organization_id and om.user_id = pm.user_id
    where pm.project_id = p_project_id and pm.user_id = auth.uid()
      and pm.status = 'active' and om.status = 'active'
      and (pm.role <> 'Viewer' or (p_approved and p_visibility = 'approved'))
  )
$$;

create or replace function public.user_has_shared_project(p_user_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
  select public.is_platform_owner() or exists (
    select 1 from public.project_members target
    join public.projects pr on pr.id = target.project_id
    join public.project_members mine on mine.project_id = target.project_id and mine.user_id = auth.uid() and mine.status = 'active'
    join public.organization_members om_target on om_target.organization_id = pr.organization_id and om_target.user_id = target.user_id and om_target.status = 'active'
    join public.organization_members om_mine on om_mine.organization_id = pr.organization_id and om_mine.user_id = auth.uid() and om_mine.status = 'active'
    where target.user_id = p_user_id and target.status = 'active'
  )
$$;

create or replace function public.is_active_task_assignee(p_task_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
  select exists (select 1 from public.task_assignees a where a.task_id = p_task_id and a.user_id = auth.uid() and a.ended_at is null)
$$;

create or replace function public.is_active_lab_assignee(p_test_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
  select exists (select 1 from public.lab_assignments a where a.lab_test_id = p_test_id and a.assignee_id = auth.uid() and a.ended_at is null)
$$;

create or replace function public.lab_result_is_approved(p_result_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public set row_security = off as $$
  select coalesce((select r.decision = 'approved' from public.lab_reviews r
                   where r.result_id = p_result_id order by r.reviewed_at desc, r.id desc limit 1), false)
$$;

-- Shared immutability guard: correction/replacement is represented by a linked new row.
create or replace function public.reject_append_only_mutation()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception '% is append-only; create a linked revision instead', tg_table_name;
end;
$$;

-- Append-only evidence/history tables.
do $$
declare t text;
begin
  foreach t in array array[
    'document_versions','document_tag_links','lab_assignments','lab_test_procedures',
    'lab_results','lab_measurements','lab_result_documents','lab_reviews',
    'formulation_versions','formulation_ingredients','formulation_trials',
    'task_submissions','task_submission_documents','task_reviews','task_comments',
    'meeting_minutes','meeting_decisions','notification_consents','notification_deliveries',
    'activity_logs','ai_citations','ai_messages'
  ] loop
    execute format('create trigger %I_append_only before update or delete on public.%I for each row execute function public.reject_append_only_mutation()', t, t);
  end loop;
end;
$$;

-- Validate the task state machine even for privileged SQL callers.
create or replace function public.guard_task_state_transition()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if new.status is distinct from old.status and not (
    (old.status = 'not_started' and new.status = 'in_progress') or
    (old.status = 'in_progress' and new.status = 'submitted') or
    (old.status = 'submitted' and new.status = 'under_review') or
    (old.status = 'under_review' and new.status in ('approved','changes_requested')) or
    (old.status = 'changes_requested' and new.status in ('in_progress','submitted'))
  ) then
    raise exception 'invalid task status transition: % -> %', old.status, new.status;
  end if;
  return new;
end;
$$;
create trigger tasks_state_guard before update of status on public.tasks
for each row execute function public.guard_task_state_transition();

create or replace function public.log_task_status_change()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  if new.status is distinct from old.status then
    insert into public.activity_logs(project_id, actor_id, action, entity_type, entity_id, details, created_by)
    values (new.project_id, auth.uid(), 'task_status_changed', 'task', new.id,
            jsonb_build_object('from', old.status, 'to', new.status), auth.uid());
  end if;
  return new;
end;
$$;
create trigger tasks_status_audit after update of status on public.tasks
for each row execute function public.log_task_status_change();

-- Members can move their assigned tasks through the work/review flow; reviewers/admins
-- may likewise transition, subject to the same state machine and append-only reviews.
create or replace function public.create_project_with_audit(
  p_organization_id uuid, p_name text, p_description text
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid := auth.uid(); v_project uuid; v_slug text;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if length(btrim(coalesce(p_name,''))) = 0 then raise exception 'project name required'; end if;
  if not public.has_org_role(p_organization_id, array['Project Lead']) then raise exception 'not authorized for organization'; end if;
  v_slug := trim(both '-' from regexp_replace(lower(btrim(p_name)), '[^a-z0-9]+', '-', 'g'));
  if v_slug is null or v_slug = '' then v_slug := 'project'; end if;
  v_slug := left(v_slug, 50) || '-' || left(replace(gen_random_uuid()::text,'-',''),8);
  insert into public.projects(organization_id,name,slug,description,created_by,updated_by)
  values(p_organization_id,btrim(p_name),v_slug,p_description,v_actor,v_actor) returning id into v_project;
  insert into public.project_members(project_id,user_id,role,status,joined_at,created_by,updated_by)
  values(v_project,v_actor,'Project Lead','active',now(),v_actor,v_actor);
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(p_organization_id,v_project,v_actor,'project_created','project',v_project,'{}'::jsonb,v_actor);
  return v_project;
end;
$$;

create or replace function public.create_task_with_audit(
  p_project_id uuid, p_title text, p_description text, p_priority text,
  p_due_at timestamptz, p_assignee_ids uuid[]
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid := auth.uid(); v_task uuid; v_org uuid; v_count integer;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if length(btrim(coalesce(p_title,''))) = 0 then raise exception 'task title required'; end if;
  if not public.has_project_role(p_project_id,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  if p_assignee_ids is null or cardinality(p_assignee_ids)=0 then raise exception 'at least one assignee is required'; end if;
  select count(distinct u.user_id) into v_count
  from unnest(p_assignee_ids) as u(user_id)
  join public.project_members pm on pm.project_id=p_project_id and pm.user_id=u.user_id and pm.status='active'
  join public.projects pr on pr.id=pm.project_id
  join public.organization_members om on om.organization_id=pr.organization_id and om.user_id=pm.user_id and om.status='active'
    and pm.role <> 'Viewer';
  if v_count <> cardinality(p_assignee_ids) then raise exception 'every assignee must be an active project member'; end if;
  select organization_id into v_org from public.projects where id=p_project_id;
  insert into public.tasks(project_id,title,description,priority,due_at,created_by,updated_by)
  values(p_project_id,btrim(p_title),p_description,p_priority,p_due_at,v_actor,v_actor) returning id into v_task;
  insert into public.task_assignees(project_id,task_id,user_id,created_by)
  select p_project_id,v_task,u.user_id,v_actor from unnest(p_assignee_ids) as u(user_id);
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,p_project_id,v_actor,'task_created','task',v_task,
         jsonb_build_object('assignee_count',cardinality(p_assignee_ids)),v_actor);
  return v_task;
end;
$$;

create or replace function public.create_sample_with_audit(
  p_project_id uuid, p_sample_code text, p_sample_type text, p_source_description text,
  p_collected_at timestamptz, p_received_at timestamptz, p_storage_conditions text
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid := auth.uid(); v_sample uuid; v_org uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if not public.has_project_role(p_project_id,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  select organization_id into v_org from public.projects where id=p_project_id;
  insert into public.samples(project_id,sample_code,sample_type,source_description,collected_at,received_at,storage_conditions,created_by,updated_by)
  values(p_project_id,btrim(p_sample_code),btrim(p_sample_type),p_source_description,p_collected_at,p_received_at,p_storage_conditions,v_actor,v_actor)
  returning id into v_sample;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,p_project_id,v_actor,'sample_registered','sample',v_sample,'{}'::jsonb,v_actor);
  return v_sample;
end;
$$;

create or replace function public.create_meeting_with_audit(
  p_project_id uuid, p_title text, p_meeting_at timestamptz,
  p_location_or_link text, p_agenda text
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid := auth.uid(); v_meeting uuid; v_org uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if not public.has_project_role(p_project_id,array['Project Lead','Secretary']) then raise exception 'not authorized for project'; end if;
  select organization_id into v_org from public.projects where id=p_project_id;
  insert into public.meetings(project_id,title,starts_at,location_or_link,agenda,status,created_by,updated_by)
  values(p_project_id,btrim(p_title),p_meeting_at,p_location_or_link,p_agenda,'scheduled',v_actor,v_actor)
  returning id into v_meeting;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,p_project_id,v_actor,'meeting_created','meeting',v_meeting,'{}'::jsonb,v_actor);
  return v_meeting;
end;
$$;

create or replace function public.create_lab_test_with_audit(
  p_project_id uuid, p_sample_id uuid, p_test_name text, p_objective text, p_planned_at timestamptz
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid := auth.uid(); v_test uuid; v_org uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if not public.has_project_role(p_project_id,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  select organization_id into v_org from public.projects where id=p_project_id;
  insert into public.lab_tests(project_id,sample_id,title,objective,planned_at,created_by,updated_by)
  values(p_project_id,p_sample_id,btrim(p_test_name),p_objective,p_planned_at,v_actor,v_actor) returning id into v_test;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,p_project_id,v_actor,'lab_test_created','lab_test',v_test,'{}'::jsonb,v_actor);
  return v_test;
end;
$$;

create or replace function public.create_formulation_with_audit(
  p_project_id uuid, p_product_name text, p_description text
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid := auth.uid(); v_formulation uuid; v_org uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if not public.has_project_role(p_project_id,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  select organization_id into v_org from public.projects where id=p_project_id;
  insert into public.formulations(project_id,name,description,created_by,updated_by)
  values(p_project_id,btrim(p_product_name),p_description,v_actor,v_actor) returning id into v_formulation;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,p_project_id,v_actor,'formulation_created','formulation',v_formulation,'{}'::jsonb,v_actor);
  return v_formulation;
end;
$$;

create or replace function public.transition_task_status(
  p_task_id uuid, p_new_status text, p_comment text
)
returns void language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid := auth.uid(); v_project uuid; v_task_status text; v_review_id uuid; v_submission uuid;
        v_is_admin boolean; v_is_researcher boolean;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  select project_id,status into v_project,v_task_status from public.tasks where id=p_task_id for update;
  if not found then raise exception 'task not found'; end if;
  v_is_admin := public.has_project_role(v_project,array['Project Lead','Secretary']);
  v_is_researcher := public.has_project_role(v_project,array['Researcher']) and public.is_active_task_assignee(p_task_id);
  if not (v_is_admin or v_is_researcher) then raise exception 'not authorized to transition this task'; end if;
  if p_new_status is not distinct from v_task_status then raise exception 'task already has requested status'; end if;
  if not ((v_task_status='not_started' and p_new_status='in_progress') or
          (v_task_status='in_progress' and p_new_status='submitted') or
          (v_task_status='submitted' and p_new_status='under_review') or
          (v_task_status='under_review' and p_new_status in ('approved','changes_requested')) or
          (v_task_status='changes_requested' and p_new_status in ('in_progress','submitted'))) then
    raise exception 'invalid task status transition';
  end if;
  if p_new_status in ('approved','changes_requested') then
    if not v_is_admin then raise exception 'reviewer role required'; end if;
    select id into v_submission from public.task_submissions where task_id=p_task_id order by submission_no desc limit 1;
    if v_submission is null then raise exception 'a submission is required before review'; end if;
    insert into public.task_reviews(project_id,task_id,submission_id,decision,comments,reviewer_id,created_by)
    values(v_project,p_task_id,v_submission,p_new_status,p_comment,v_actor,v_actor) returning id into v_review_id;
    insert into public.activity_logs(project_id,actor_id,action,entity_type,entity_id,details,created_by)
    values(v_project,v_actor,'task_reviewed','task',p_task_id,jsonb_build_object('decision',p_new_status,'review_id',v_review_id),v_actor);
  elsif p_new_status='under_review' and not v_is_admin then
    raise exception 'reviewer role required';
  elsif p_new_status in ('in_progress','submitted') and not v_is_researcher and not v_is_admin then
    raise exception 'assignee role required';
  end if;
  if p_new_status='submitted' and not exists(select 1 from public.task_submissions s where s.task_id=p_task_id and s.submitted_by=v_actor) then
    raise exception 'submit work before moving task to submitted';
  end if;
  if p_comment is not null and length(btrim(p_comment))>0 and p_new_status not in ('approved','changes_requested') then
    insert into public.task_comments(project_id,task_id,body,created_by) values(v_project,p_task_id,btrim(p_comment),v_actor);
  end if;
  update public.tasks set status=p_new_status,updated_by=v_actor where id=p_task_id;
end;
$$;

-- Compatibility wrapper uses the same authorization/state checks; prefer transition_task_status.
create or replace function public.transition_task(p_task_id uuid, p_new_status text)
returns void language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  perform public.transition_task_status(p_task_id,p_new_status,null);
end;
$$;

create or replace function public.accept_pending_invitation(p_raw_token text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid := auth.uid(); v_email text; v_inv public.invitations%rowtype; v_status text;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if coalesce(auth.jwt()->>'email_verified','false') <> 'true' then raise exception 'verified email required'; end if;
  v_email := auth.jwt()->>'email';
  if v_email is null or length(btrim(coalesce(p_raw_token,'')))=0 then raise exception 'valid invitation and email required'; end if;
  insert into public.profiles(id,display_name,created_by,updated_by)
  values(v_actor,left(coalesce(nullif(btrim(auth.jwt()->'user_metadata'->>'full_name'),''),split_part(v_email,'@',1),'Member'),200),v_actor,v_actor)
  on conflict (id) do nothing;
  select * into v_inv from public.invitations i
   where i.token_hash=digest(convert_to(p_raw_token,'UTF8'),'sha256')
     and i.email=v_email::citext and i.accepted_at is null and i.revoked_at is null and i.expires_at>now()
   for update;
  if not found then raise exception 'invitation unavailable'; end if;
  select status into v_status from public.organization_members where organization_id=v_inv.organization_id and user_id=v_actor for update;
  if v_status='active' then
    null;
  elsif found then
    update public.organization_members set role=v_inv.role,status='active',joined_at=coalesce(joined_at,now()),updated_by=v_actor
     where organization_id=v_inv.organization_id and user_id=v_actor;
  else
    insert into public.organization_members(organization_id,user_id,role,status,joined_at,created_by,updated_by)
    values(v_inv.organization_id,v_actor,v_inv.role,'active',now(),v_actor,v_actor);
  end if;
  if v_inv.project_id is not null then
    select status into v_status from public.project_members where project_id=v_inv.project_id and user_id=v_actor for update;
    if v_status='active' then
      null;
    elsif found then
      update public.project_members set role=v_inv.project_role,status='active',joined_at=coalesce(joined_at,now()),updated_by=v_actor
       where project_id=v_inv.project_id and user_id=v_actor;
    else
      insert into public.project_members(project_id,user_id,role,status,joined_at,created_by,updated_by)
      values(v_inv.project_id,v_actor,v_inv.project_role,'active',now(),v_actor,v_actor);
    end if;
  end if;
  update public.invitations set accepted_at=now(),updated_by=v_actor where id=v_inv.id;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_inv.organization_id,v_inv.project_id,v_actor,'invitation_accepted','invitation',v_inv.id,'{}'::jsonb,v_actor);
  return v_inv.id;
end;
$$;

create or replace function public.claim_document_processing_job(p_worker_id uuid)
returns setof public.document_processing_jobs language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required'; end if;
  return query
    with candidate as (
      select id from public.document_processing_jobs
      where status in ('queued','failed') and attempts < max_attempts and next_attempt_at <= now()
      order by created_at for update skip locked limit 1
    )
    update public.document_processing_jobs j
       set status = 'processing', attempts = j.attempts + 1,
           locked_by = p_worker_id, locked_at = now(), error_code = null, error_message = null
      from candidate c where j.id = c.id returning j.*;
end;
$$;

create or replace function public.claim_ai_job(p_worker_id uuid)
returns setof public.ai_jobs language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required'; end if;
  return query
    with candidate as (
      select id from public.ai_jobs
      where status in ('queued','failed') and attempts < max_attempts and next_attempt_at <= now()
      order by created_at for update skip locked limit 1
    )
    update public.ai_jobs j
       set status = 'processing', attempts = j.attempts + 1,
           locked_by = p_worker_id, locked_at = now(), started_at = coalesce(j.started_at, now()),
           error_code = null, error_message = null
      from candidate c where j.id = c.id returning j.*;
end;
$$;

-- RLS is enabled on every application table. Owner access is platform-level; all other
-- policies require active organization + project membership. Viewer reads are approved-only.
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','organizations','organization_members','projects','project_members','invitations',
    'documents','document_versions','document_tags','document_tag_links','research_entries',
    'document_processing_jobs','document_chunks','samples','lab_tests','lab_assignments',
    'lab_test_procedures','lab_results','lab_measurements','lab_result_documents','lab_reviews',
    'formulations','formulation_versions','formulation_ingredients','formulation_trials',
    'tasks','task_assignees','task_submissions','task_submission_documents','task_reviews','task_comments',
    'meetings','meeting_attendees','meeting_minutes','meeting_decisions','notification_preferences',
    'notification_consents','notifications','notification_deliveries','activity_logs','ai_jobs',
    'ai_reports','ai_citations','ai_conversations','ai_messages'
  ] loop execute format('alter table public.%I enable row level security', t); end loop;
end;
$$;

-- Authenticated application privileges; RLS policies below are the authorization boundary.
grant usage on schema public to authenticated;
grant select, insert on public.profiles, public.organizations, public.organization_members,
  public.projects, public.project_members, public.invitations, public.documents,
  public.document_versions, public.document_tags, public.document_tag_links,
  public.research_entries, public.document_processing_jobs, public.document_chunks,
  public.samples, public.lab_tests, public.lab_assignments, public.lab_test_procedures,
  public.lab_results, public.lab_measurements, public.lab_result_documents, public.lab_reviews,
  public.formulations, public.formulation_versions, public.formulation_ingredients,
  public.formulation_trials, public.tasks, public.task_assignees, public.task_submissions,
  public.task_submission_documents, public.task_reviews, public.task_comments, public.meetings,
  public.meeting_attendees, public.meeting_minutes, public.meeting_decisions,
  public.notification_preferences, public.notification_consents, public.notifications,
  public.notification_deliveries, public.activity_logs, public.ai_jobs, public.ai_reports,
  public.ai_citations, public.ai_conversations, public.ai_messages to authenticated;
grant update on public.organizations, public.organization_members, public.projects,
  public.project_members, public.documents, public.research_entries,
  public.document_processing_jobs, public.samples, public.lab_tests, public.formulations,
  public.meetings, public.meeting_attendees, public.ai_jobs, public.ai_reports,
  public.ai_conversations to authenticated;
revoke update on public.tasks, public.invitations from authenticated;
grant update (title, description, priority, due_at, updated_by) on public.tasks to authenticated;
revoke select on public.invitations from authenticated;
grant select (id, organization_id, project_id, email, role, project_role, expires_at, accepted_at, revoked_at, created_at, updated_at, invited_by, created_by, updated_by) on public.invitations to authenticated;
grant update (display_name, phone_e164, locale, updated_by) on public.profiles to authenticated;
grant update (enabled, updated_by) on public.notification_preferences to authenticated;
revoke all on function public.is_platform_owner() from public, anon;
revoke all on function public.has_org_role(uuid,text[]) from public, anon;
revoke all on function public.has_project_role(uuid,text[]) from public, anon;
revoke all on function public.can_read_project(uuid,text,boolean) from public, anon;
revoke all on function public.user_has_shared_project(uuid) from public, anon;
revoke all on function public.is_active_task_assignee(uuid) from public, anon;
revoke all on function public.is_active_lab_assignee(uuid) from public, anon;
revoke all on function public.lab_result_is_approved(uuid) from public, anon;
revoke all on function public.transition_task(uuid,text) from public, anon;
grant execute on function public.is_platform_owner() to authenticated;
grant execute on function public.has_org_role(uuid,text[]) to authenticated;
grant execute on function public.has_project_role(uuid,text[]) to authenticated;
grant execute on function public.can_read_project(uuid,text,boolean) to authenticated;
grant execute on function public.user_has_shared_project(uuid) to authenticated;
grant execute on function public.is_active_task_assignee(uuid) to authenticated;
grant execute on function public.is_active_lab_assignee(uuid) to authenticated;
grant execute on function public.lab_result_is_approved(uuid) to authenticated;
grant execute on function public.transition_task(uuid,text) to authenticated;
revoke all on function public.create_project_with_audit(uuid,text,text) from public, anon;
revoke all on function public.create_task_with_audit(uuid,text,text,text,timestamptz,uuid[]) from public, anon;
revoke all on function public.create_sample_with_audit(uuid,text,text,text,timestamptz,timestamptz,text) from public, anon;
revoke all on function public.create_meeting_with_audit(uuid,text,timestamptz,text,text) from public, anon;
revoke all on function public.create_lab_test_with_audit(uuid,uuid,text,text,timestamptz) from public, anon;
revoke all on function public.create_formulation_with_audit(uuid,text,text) from public, anon;
revoke all on function public.transition_task_status(uuid,text,text) from public, anon;
revoke all on function public.accept_pending_invitation(text) from public, anon;
grant execute on function public.create_project_with_audit(uuid,text,text) to authenticated;
grant execute on function public.create_task_with_audit(uuid,text,text,text,timestamptz,uuid[]) to authenticated;
grant execute on function public.create_sample_with_audit(uuid,text,text,text,timestamptz,timestamptz,text) to authenticated;
grant execute on function public.create_meeting_with_audit(uuid,text,timestamptz,text,text) to authenticated;
grant execute on function public.create_lab_test_with_audit(uuid,uuid,text,text,timestamptz) to authenticated;
grant execute on function public.create_formulation_with_audit(uuid,text,text) to authenticated;
grant execute on function public.transition_task_status(uuid,text,text) to authenticated;
grant execute on function public.accept_pending_invitation(text) to authenticated;
revoke all on function public.claim_document_processing_job(uuid) from public, anon, authenticated;
revoke all on function public.claim_ai_job(uuid) from public, anon, authenticated;
grant execute on function public.claim_document_processing_job(uuid) to service_role;
grant execute on function public.claim_ai_job(uuid) to service_role;

-- Profiles: self-service only for own profile; teammates' minimal profiles are visible in shared projects.
create policy profiles_read on public.profiles for select to authenticated
using (id = auth.uid() or public.user_has_shared_project(id) or public.is_platform_owner());
create policy profiles_insert_self on public.profiles for insert to authenticated
with check (id = auth.uid() and created_by = auth.uid() and updated_by = auth.uid() and not platform_owner);
create policy profiles_update_self on public.profiles for update to authenticated
using (id = auth.uid() or public.is_platform_owner())
with check ((id = auth.uid() or public.is_platform_owner()) and updated_by = auth.uid());

create policy organizations_read on public.organizations for select to authenticated
using (public.has_org_role(id, null));
create policy organizations_insert on public.organizations for insert to authenticated
with check (public.is_platform_owner() and created_by = auth.uid() and updated_by = auth.uid());
create policy organizations_update on public.organizations for update to authenticated
using (public.is_platform_owner()) with check (public.is_platform_owner() and updated_by = auth.uid());

create policy org_members_read on public.organization_members for select to authenticated
using (public.has_org_role(organization_id, null));
create policy org_members_insert on public.organization_members for insert to authenticated
with check (public.has_org_role(organization_id, array['Project Lead']) and created_by = auth.uid() and updated_by = auth.uid());
create policy org_members_update on public.organization_members for update to authenticated
using (public.has_org_role(organization_id, array['Project Lead']))
with check (public.has_org_role(organization_id, array['Project Lead']) and updated_by = auth.uid());

create policy projects_read on public.projects for select to authenticated
using (public.has_org_role(organization_id, null));
create policy projects_insert on public.projects for insert to authenticated
with check (public.has_org_role(organization_id, array['Project Lead']) and created_by = auth.uid() and updated_by = auth.uid());
create policy projects_update on public.projects for update to authenticated
using (public.has_project_role(id, array['Project Lead','Secretary']))
with check (public.has_project_role(id, array['Project Lead','Secretary']) and updated_by = auth.uid());

create policy project_members_read on public.project_members for select to authenticated
using (public.has_project_role(project_id, null));
create policy project_members_insert on public.project_members for insert to authenticated
with check (public.has_project_role(project_id, array['Project Lead','Secretary']) and created_by = auth.uid() and updated_by = auth.uid());
create policy project_members_update on public.project_members for update to authenticated
using (public.has_project_role(project_id, array['Project Lead','Secretary']))
with check (public.has_project_role(project_id, array['Project Lead','Secretary']) and updated_by = auth.uid());

create policy invitations_read on public.invitations for select to authenticated
using (public.has_org_role(organization_id, array['Project Lead','Secretary']));
create policy invitations_insert on public.invitations for insert to authenticated
with check (public.has_org_role(organization_id, array['Project Lead','Secretary']) and invited_by = auth.uid() and created_by = auth.uid());
create policy invitations_update on public.invitations for update to authenticated
using (public.has_org_role(organization_id, array['Project Lead','Secretary']))
with check (public.has_org_role(organization_id, array['Project Lead','Secretary']) and updated_by=auth.uid());

create policy documents_read on public.documents for select to authenticated
using ((visibility <> 'private' and public.can_read_project(project_id, visibility, status = 'approved'))
       or (created_by = auth.uid() and public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']))
       or public.has_project_role(project_id,array['Project Lead','Secretary']));
create policy documents_insert on public.documents for insert to authenticated
with check (created_by = auth.uid() and updated_by = auth.uid() and
  (public.has_project_role(project_id,array['Project Lead','Secretary']) or
   (public.has_project_role(project_id,array['Researcher']) and status in ('draft','in_review'))));
create policy documents_update on public.documents for update to authenticated
using (public.has_project_role(project_id, array['Project Lead','Secretary']) or (created_by = auth.uid() and status in ('draft','in_review') and public.has_project_role(project_id, array['Researcher'])))
with check (public.has_project_role(project_id, array['Project Lead','Secretary']) or (created_by = auth.uid() and status in ('draft','in_review') and public.has_project_role(project_id, array['Researcher'])));

create policy document_versions_read on public.document_versions for select to authenticated
using (exists (select 1 from public.documents d where d.id = document_id and d.project_id = document_versions.project_id
  and ((d.visibility <> 'private' and public.can_read_project(d.project_id,d.visibility,d.status='approved'))
       or (d.created_by=auth.uid() and public.has_project_role(d.project_id,array['Project Lead','Secretary','Researcher']))
       or public.has_project_role(d.project_id,array['Project Lead','Secretary']))));
create policy document_versions_insert on public.document_versions for insert to authenticated
with check (public.has_project_role(project_id, array['Project Lead','Secretary','Researcher']) and created_by = auth.uid());

create policy document_tags_read on public.document_tags for select to authenticated
using (public.can_read_project(project_id,'project',true));
create policy document_tags_insert on public.document_tags for insert to authenticated
with check (public.has_project_role(project_id, array['Project Lead','Secretary','Researcher']) and created_by = auth.uid());
create policy document_tag_links_read on public.document_tag_links for select to authenticated
using (public.can_read_project(project_id,'project',true));
create policy document_tag_links_insert on public.document_tag_links for insert to authenticated
with check (public.has_project_role(project_id, array['Project Lead','Secretary','Researcher']) and created_by = auth.uid());

create policy research_entries_read on public.research_entries for select to authenticated
using (public.can_read_project(project_id, case when status='approved' then 'approved' else 'project' end, status='approved'));
create policy research_entries_insert on public.research_entries for insert to authenticated
with check (created_by=auth.uid() and updated_by=auth.uid() and
  (public.has_project_role(project_id,array['Project Lead','Secretary']) or
   (public.has_project_role(project_id,array['Researcher']) and status in ('draft','in_review'))));
create policy research_entries_update on public.research_entries for update to authenticated
using (created_by = auth.uid() and status in ('draft','in_review') and public.has_project_role(project_id, array['Researcher']) or public.has_project_role(project_id, array['Project Lead','Secretary']))
with check (updated_by = auth.uid() and (public.has_project_role(project_id, array['Project Lead','Secretary']) or (created_by = auth.uid() and status in ('draft','in_review') and public.has_project_role(project_id, array['Researcher']))));

create policy document_processing_jobs_read on public.document_processing_jobs for select to authenticated
using (public.has_project_role(project_id, array['Project Lead','Secretary','Researcher']));
create policy document_processing_jobs_insert on public.document_processing_jobs for insert to authenticated
with check (public.has_project_role(project_id, array['Project Lead','Secretary','Researcher']) and requested_by = auth.uid() and created_by = auth.uid());
create policy document_chunks_read on public.document_chunks for select to authenticated
using (exists (select 1 from public.document_versions v join public.documents d on d.id=v.document_id
  where v.id=document_version_id and v.project_id=document_chunks.project_id
    and ((d.visibility <> 'private' and public.can_read_project(d.project_id,d.visibility,d.status='approved'))
         or (d.created_by=auth.uid() and public.has_project_role(d.project_id,array['Project Lead','Secretary','Researcher']))
       or public.has_project_role(d.project_id,array['Project Lead','Secretary']))));

create policy samples_read on public.samples for select to authenticated
using (public.can_read_project(project_id, case when status='approved' then 'approved' else 'project' end, status='approved'));
create policy samples_insert on public.samples for insert to authenticated
with check (created_by=auth.uid() and updated_by=auth.uid() and
  (public.has_project_role(project_id,array['Project Lead','Secretary']) or
   (public.has_project_role(project_id,array['Researcher']) and status in ('registered','active'))));
create policy samples_update on public.samples for update to authenticated
using (public.has_project_role(project_id, array['Project Lead','Secretary']) or (created_by=auth.uid() and public.has_project_role(project_id,array['Researcher']) and status in ('registered','active')))
with check (updated_by=auth.uid() and (public.has_project_role(project_id,array['Project Lead','Secretary']) or (created_by=auth.uid() and public.has_project_role(project_id,array['Researcher']) and status in ('registered','active'))));

create policy lab_tests_read on public.lab_tests for select to authenticated
using (public.can_read_project(project_id, case when status='approved' then 'approved' else 'project' end, status='approved') or (public.has_project_role(project_id,array['Researcher']) and public.is_active_lab_assignee(id)));
create policy lab_tests_insert on public.lab_tests for insert to authenticated
with check (created_by=auth.uid() and updated_by=auth.uid() and
  (public.has_project_role(project_id,array['Project Lead','Secretary']) or
   (public.has_project_role(project_id,array['Researcher']) and status='planned')));
create policy lab_tests_update on public.lab_tests for update to authenticated
using (public.has_project_role(project_id,array['Project Lead','Secretary']) or (status <> 'approved' and public.is_active_lab_assignee(id) and public.has_project_role(project_id,array['Researcher'])))
with check (updated_by=auth.uid() and (public.has_project_role(project_id,array['Project Lead','Secretary']) or (status <> 'approved' and public.is_active_lab_assignee(id) and public.has_project_role(project_id,array['Researcher']))));

create policy lab_assignments_read on public.lab_assignments for select to authenticated
using (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']));
create policy lab_assignments_insert on public.lab_assignments for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and created_by=auth.uid());
create policy lab_test_procedures_read on public.lab_test_procedures for select to authenticated
using (public.can_read_project(project_id,'project',true));
create policy lab_test_procedures_insert on public.lab_test_procedures for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']) and created_by=auth.uid());

create policy lab_results_read on public.lab_results for select to authenticated
using (public.can_read_project(project_id,'approved',public.lab_result_is_approved(id))
  or (public.is_active_lab_assignee(lab_test_id) and public.has_project_role(project_id,array['Researcher'])));
create policy lab_results_insert on public.lab_results for insert to authenticated
with check (created_by=auth.uid() and exists(select 1 from public.lab_tests t where t.id=lab_test_id and t.project_id=lab_results.project_id
  and (public.has_project_role(t.project_id,array['Project Lead','Secretary']) or (public.has_project_role(t.project_id,array['Researcher']) and public.is_active_lab_assignee(t.id)))));
create policy lab_measurements_read on public.lab_measurements for select to authenticated
using (exists(select 1 from public.lab_results r join public.lab_tests t on t.id=r.lab_test_id
  where r.id=result_id and r.project_id=lab_measurements.project_id
    and (public.can_read_project(r.project_id,'approved',public.lab_result_is_approved(r.id))
         or (public.has_project_role(r.project_id,array['Researcher']) and public.is_active_lab_assignee(t.id)))));
create policy lab_measurements_insert on public.lab_measurements for insert to authenticated
with check (created_by=auth.uid() and exists(select 1 from public.lab_results r join public.lab_tests t on t.id=r.lab_test_id
  where r.id=result_id and r.project_id=lab_measurements.project_id
    and (public.has_project_role(r.project_id,array['Project Lead','Secretary']) or (public.has_project_role(r.project_id,array['Researcher']) and public.is_active_lab_assignee(t.id)))));
create policy lab_result_documents_read on public.lab_result_documents for select to authenticated
using (exists(select 1 from public.lab_results r join public.lab_tests t on t.id=r.lab_test_id
  where r.id=result_id and r.project_id=lab_result_documents.project_id
    and (public.can_read_project(r.project_id,'approved',public.lab_result_is_approved(r.id))
         or (public.has_project_role(r.project_id,array['Researcher']) and public.is_active_lab_assignee(t.id)))));
create policy lab_result_documents_insert on public.lab_result_documents for insert to authenticated
with check (created_by=auth.uid() and exists(select 1 from public.lab_results r join public.lab_tests t on t.id=r.lab_test_id
  where r.id=result_id and r.project_id=lab_result_documents.project_id
    and (public.has_project_role(r.project_id,array['Project Lead','Secretary']) or (public.has_project_role(r.project_id,array['Researcher']) and public.is_active_lab_assignee(t.id)))));
create policy lab_reviews_read on public.lab_reviews for select to authenticated
using (exists(select 1 from public.lab_results r where r.id=result_id and public.can_read_project(r.project_id,'approved',public.lab_result_is_approved(r.id))));
create policy lab_reviews_insert on public.lab_reviews for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and reviewer_id=auth.uid() and created_by=auth.uid());

create policy formulations_read on public.formulations for select to authenticated
using (public.can_read_project(project_id,case when status='active' then 'approved' else 'project' end,status='active'));
create policy formulations_insert on public.formulations for insert to authenticated
with check (created_by=auth.uid() and updated_by=auth.uid() and
  (public.has_project_role(project_id,array['Project Lead','Secretary']) or
   (public.has_project_role(project_id,array['Researcher']) and status='draft')));
create policy formulations_update on public.formulations for update to authenticated
using (public.has_project_role(project_id,array['Project Lead','Secretary']) or (created_by=auth.uid() and status='draft' and public.has_project_role(project_id,array['Researcher'])))
with check (updated_by=auth.uid() and (public.has_project_role(project_id,array['Project Lead','Secretary']) or (created_by=auth.uid() and status='draft' and public.has_project_role(project_id,array['Researcher']))));
create policy formulation_versions_read on public.formulation_versions for select to authenticated
using (public.can_read_project(project_id,case when status='approved' then 'approved' else 'project' end,status='approved'));
create policy formulation_versions_insert on public.formulation_versions for insert to authenticated
with check (created_by=auth.uid() and (public.has_project_role(project_id,array['Project Lead','Secretary']) or
  (public.has_project_role(project_id,array['Researcher']) and status='draft')));
create policy formulation_ingredients_read on public.formulation_ingredients for select to authenticated
using (exists(select 1 from public.formulation_versions v where v.id=formulation_version_id and public.can_read_project(v.project_id,'approved',v.status='approved')));
create policy formulation_ingredients_insert on public.formulation_ingredients for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']) and created_by=auth.uid());
create policy formulation_trials_read on public.formulation_trials for select to authenticated
using (exists(select 1 from public.formulation_versions v where v.id=formulation_version_id and public.can_read_project(v.project_id,'approved',v.status='approved')));
create policy formulation_trials_insert on public.formulation_trials for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']) and created_by=auth.uid());

create policy tasks_read on public.tasks for select to authenticated
using (public.can_read_project(project_id,case when status='approved' then 'approved' else 'project' end,status='approved'));
create policy tasks_insert on public.tasks for insert to authenticated
with check (status='not_started' and public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']) and created_by=auth.uid() and updated_by=auth.uid());
create policy tasks_update_admin on public.tasks for update to authenticated
using (public.has_project_role(project_id,array['Project Lead','Secretary']))
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and updated_by=auth.uid());
create policy task_assignees_read on public.task_assignees for select to authenticated
using (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']));
create policy task_assignees_insert on public.task_assignees for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and created_by=auth.uid());
create policy task_submissions_read on public.task_submissions for select to authenticated
using (exists(select 1 from public.tasks t where t.id=task_id and public.can_read_project(t.project_id,case when t.status='approved' then 'approved' else 'project' end,t.status='approved')));
create policy task_submissions_insert on public.task_submissions for insert to authenticated
with check (submitted_by=auth.uid() and created_by=auth.uid() and (public.has_project_role(project_id,array['Project Lead','Secretary']) or (public.has_project_role(project_id,array['Researcher']) and public.is_active_task_assignee(task_id))));
create policy task_submission_documents_read on public.task_submission_documents for select to authenticated
using (exists(select 1 from public.task_submissions s join public.tasks t on t.id=s.task_id
  where s.id=submission_id and public.can_read_project(t.project_id,case when t.status='approved' then 'approved' else 'project' end,t.status='approved')));
create policy task_submission_documents_insert on public.task_submission_documents for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']) and created_by=auth.uid());
create policy task_reviews_read on public.task_reviews for select to authenticated
using (exists(select 1 from public.tasks t where t.id=task_id and public.can_read_project(t.project_id,case when t.status='approved' then 'approved' else 'project' end,t.status='approved')));
create policy task_reviews_insert on public.task_reviews for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and reviewer_id=auth.uid() and created_by=auth.uid());
create policy task_comments_read on public.task_comments for select to authenticated
using (exists(select 1 from public.tasks t where t.id=task_id and public.can_read_project(t.project_id,case when t.status='approved' then 'approved' else 'project' end,t.status='approved')));
create policy task_comments_insert on public.task_comments for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']) and created_by=auth.uid());

create policy meetings_read on public.meetings for select to authenticated
using (public.can_read_project(project_id,case when status='published' then 'approved' else 'project' end,status='published'));
create policy meetings_insert on public.meetings for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and created_by=auth.uid() and updated_by=auth.uid());
create policy meetings_update on public.meetings for update to authenticated
using (public.has_project_role(project_id,array['Project Lead','Secretary']))
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and updated_by=auth.uid());
create policy meeting_attendees_read on public.meeting_attendees for select to authenticated
using (exists(select 1 from public.meetings m where m.id=meeting_id and public.can_read_project(m.project_id,case when m.status='published' then 'approved' else 'project' end,m.status='published')));
create policy meeting_attendees_insert on public.meeting_attendees for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and created_by=auth.uid() and updated_by=auth.uid());
create policy meeting_attendees_update on public.meeting_attendees for update to authenticated
using (public.has_project_role(project_id,array['Project Lead','Secretary']))
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and updated_by=auth.uid());
create policy meeting_minutes_read on public.meeting_minutes for select to authenticated
using (exists(select 1 from public.meetings m where m.id=meeting_id and public.can_read_project(m.project_id,case when m.status='published' then 'approved' else 'project' end,m.status='published')));
create policy meeting_minutes_insert on public.meeting_minutes for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and submitted_by=auth.uid() and created_by=auth.uid());
create policy meeting_decisions_read on public.meeting_decisions for select to authenticated
using (public.can_read_project(project_id,case when status='approved' then 'approved' else 'project' end,status='approved'));
create policy meeting_decisions_insert on public.meeting_decisions for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and created_by=auth.uid());

create policy notification_preferences_read on public.notification_preferences for select to authenticated
using (user_id=auth.uid() or public.is_platform_owner());
create policy notification_preferences_insert on public.notification_preferences for insert to authenticated
with check (user_id=auth.uid() and created_by=auth.uid() and updated_by=auth.uid()
  and (project_id is null or public.has_project_role(project_id,null)));
create policy notification_preferences_update on public.notification_preferences for update to authenticated
using (user_id=auth.uid() and (project_id is null or public.has_project_role(project_id,null)))
with check (user_id=auth.uid() and updated_by=auth.uid() and (project_id is null or public.has_project_role(project_id,null)));
create policy notification_consents_read on public.notification_consents for select to authenticated
using (user_id=auth.uid() or public.has_org_role(organization_id,array['Project Lead','Secretary']));
create policy notification_consents_insert on public.notification_consents for insert to authenticated
with check (user_id=auth.uid() and recorded_by=auth.uid() and created_by=auth.uid() and public.has_org_role(organization_id,null));
create policy notifications_read on public.notifications for select to authenticated
using (recipient_id=auth.uid() and public.has_project_role(project_id,null));
create policy notifications_insert on public.notifications for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and created_by=auth.uid());
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy notifications_update_read on public.notifications for update to authenticated
using (recipient_id=auth.uid() and public.has_project_role(project_id,null))
with check (recipient_id=auth.uid() and public.has_project_role(project_id,null) and updated_by=auth.uid());
create policy notification_deliveries_read on public.notification_deliveries for select to authenticated
using (exists(select 1 from public.notifications n where n.id=notification_id and (n.recipient_id=auth.uid() or public.has_project_role(n.project_id,array['Project Lead','Secretary']))));
create policy notification_deliveries_insert on public.notification_deliveries for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary']) and (created_by=auth.uid() or public.is_platform_owner()));

create policy activity_logs_read on public.activity_logs for select to authenticated
using (public.is_platform_owner() or (project_id is not null and public.has_project_role(project_id,array['Project Lead','Secretary'])) or (organization_id is not null and public.has_org_role(organization_id,array['Project Lead'])));
create policy activity_logs_insert on public.activity_logs for insert to authenticated
with check ((project_id is null or public.has_project_role(project_id,array['Project Lead','Secretary'])) and (created_by=auth.uid() or public.is_platform_owner()));

create policy ai_jobs_read on public.ai_jobs for select to authenticated
using (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']));
create policy ai_jobs_insert on public.ai_jobs for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']) and requested_by=auth.uid() and created_by=auth.uid());
create policy ai_reports_read on public.ai_reports for select to authenticated
using (public.can_read_project(project_id,case when status='published' then 'approved' else 'project' end,status='published'));
create policy ai_reports_insert on public.ai_reports for insert to authenticated
with check (status='draft' and reviewer_id is null and reviewed_at is null and
  public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']) and created_by=auth.uid() and updated_by=auth.uid());
create policy ai_reports_update on public.ai_reports for update to authenticated
using (public.has_project_role(project_id,array['Project Lead','Secretary']) or
       (status <> 'published' and public.has_project_role(project_id,array['Researcher'])))
with check (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']) and updated_by=auth.uid() and
  (status <> 'published' or (public.has_project_role(project_id,array['Project Lead','Secretary']) and reviewer_id=auth.uid())));
create policy ai_citations_read on public.ai_citations for select to authenticated
using (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']));
create policy ai_citations_insert on public.ai_citations for insert to authenticated
with check (public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']) and created_by=auth.uid());
create policy ai_conversations_read on public.ai_conversations for select to authenticated
using (created_by=auth.uid() and public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']));
create policy ai_conversations_insert on public.ai_conversations for insert to authenticated
with check (created_by=auth.uid() and updated_by=auth.uid() and public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']));
create policy ai_conversations_update on public.ai_conversations for update to authenticated
using (created_by=auth.uid() and public.has_project_role(project_id,array['Project Lead','Secretary','Researcher']))
with check (created_by=auth.uid() and updated_by=auth.uid());
create policy ai_messages_read on public.ai_messages for select to authenticated
using (exists(select 1 from public.ai_conversations c where c.id=conversation_id and c.created_by=auth.uid() and public.has_project_role(c.project_id,array['Project Lead','Secretary','Researcher'])));
create policy ai_messages_insert on public.ai_messages for insert to authenticated
with check (role='user' and created_by=auth.uid() and exists(select 1 from public.ai_conversations c where c.id=conversation_id and c.created_by=auth.uid() and public.has_project_role(c.project_id,array['Project Lead','Secretary','Researcher'])));

-- Additional safe lookup indexes for relationship joins and project activity.
create index document_tag_links_document_idx on public.document_tag_links(project_id, document_id);
create index lab_test_procedures_test_idx on public.lab_test_procedures(project_id, lab_test_id);
create index lab_results_test_revision_idx on public.lab_results(lab_test_id, revision_no desc);
create index task_submissions_task_idx on public.task_submissions(project_id, task_id, submission_no desc);
create index meetings_attendees_user_idx on public.meeting_attendees(project_id, user_id);
create index ai_messages_job_idx on public.ai_messages(ai_job_id);

commit;
