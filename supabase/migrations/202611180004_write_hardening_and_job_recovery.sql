-- Narrow authenticated write access to audited RPCs, enqueue extraction atomically,
-- and recover worker jobs whose process disappeared while holding a lease.
-- Source artifact only: review and apply manually to an explicitly selected database.
begin;

create or replace function public.create_invitation_with_audit(
  p_organization_id uuid,
  p_email text,
  p_role text,
  p_project_id uuid,
  p_project_role text,
  p_token_hash_hex text
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_actor uuid := auth.uid();
  v_project_role text;
  v_project_org uuid;
  v_invitation uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if not public.has_org_role(p_organization_id, array['Project Lead','Secretary']) then
    raise exception 'organization administrator permission required';
  end if;
  if p_role not in ('Project Lead','Secretary','Researcher','Viewer') then raise exception 'invalid organization role'; end if;
  if p_email is null or length(btrim(p_email)) > 320 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'valid email required'; end if;
  if p_token_hash_hex is null or p_token_hash_hex !~ '^[0-9a-fA-F]{64}$' then raise exception 'valid invitation token digest required'; end if;
  if p_project_id is null then
    if p_project_role is not null then raise exception 'project role requires a project scope'; end if;
    v_project_role := null;
  else
    select organization_id into v_project_org from public.projects where id = p_project_id;
    if not found or v_project_org is distinct from p_organization_id then raise exception 'project must belong to the invited organization'; end if;
    if not public.has_project_role(p_project_id, array['Project Lead','Secretary']) then raise exception 'project administrator permission required'; end if;
    v_project_role := coalesce(p_project_role, p_role);
    if v_project_role not in ('Project Lead','Secretary','Researcher','Viewer') then raise exception 'invalid project role'; end if;
  end if;

  insert into public.invitations(organization_id, project_id, email, role, project_role, token_hash, expires_at, invited_by, created_by, updated_by)
  values(p_organization_id, p_project_id, lower(btrim(p_email))::citext, p_role, v_project_role,
         decode(p_token_hash_hex, 'hex'), now() + interval '7 days', v_actor, v_actor, v_actor)
  returning id into v_invitation;

  insert into public.activity_logs(organization_id, project_id, actor_id, action, entity_type, entity_id, details, created_by)
  values(p_organization_id, p_project_id, v_actor, 'invitation_created', 'invitation', v_invitation,
         jsonb_build_object('role', p_role, 'project_role', v_project_role), v_actor);
  return v_invitation;
end;
$$;

create or replace function public.queue_ai_request_with_audit(
  p_project_id uuid,
  p_job_type text,
  p_question text,
  p_input_reference jsonb,
  p_prompt_version text
)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_actor uuid := auth.uid();
  v_question text := btrim(coalesce(p_question, ''));
  v_conversation uuid;
  v_job uuid;
  v_org uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if not exists (select 1 from public.platform_ai_settings where singleton and ai_enabled) then
    raise exception 'AI processing is disabled at the database level' using errcode = '55000';
  end if;
  if p_job_type not in ('chat','analysis') then raise exception 'unsupported AI job type'; end if;
  if length(v_question) = 0 or length(v_question) > 12000 then raise exception 'AI request text is invalid'; end if;
  if jsonb_typeof(coalesce(p_input_reference, '{}'::jsonb)) <> 'object' or octet_length(coalesce(p_input_reference, '{}'::jsonb)::text) > 80000 then raise exception 'AI evidence reference is invalid'; end if;
  if jsonb_typeof(coalesce(p_input_reference, '{}'::jsonb)) <> 'object' or octet_length(coalesce(p_input_reference, '{}'::jsonb)::text) > 80000 then raise exception 'AI evidence reference is invalid'; end if;
  if length(btrim(coalesce(p_prompt_version,''))) = 0 or length(p_prompt_version) > 120 then raise exception 'AI prompt version is invalid'; end if;
  if not public.has_project_role(p_project_id, array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for AI processing in this project'; end if;
  select organization_id into v_org from public.projects where id = p_project_id;
  if not found then raise exception 'project not found'; end if;

  insert into public.ai_conversations(project_id, title, status, created_by, updated_by)
  values(p_project_id, left(v_question,180), 'active', v_actor, v_actor)
  returning id into v_conversation;
  insert into public.ai_messages(project_id, conversation_id, sequence_no, role, content, created_by)
  values(p_project_id, v_conversation, 1, 'user', v_question, v_actor);
  insert into public.ai_jobs(project_id, idempotency_key, job_type, status, input_reference, prompt_version, requested_by, created_by, updated_by)
  values(p_project_id, gen_random_uuid()::text, p_job_type, 'queued',
         coalesce(p_input_reference, '{}'::jsonb) || jsonb_build_object('question',v_question,'conversation_id',v_conversation,'_requester_id',v_actor),
         p_prompt_version, v_actor, v_actor, v_actor)
  returning id into v_job;
  insert into public.activity_logs(organization_id, project_id, actor_id, action, entity_type, entity_id, details, created_by)
  values(v_org, p_project_id, v_actor, 'ai_job_queued', 'ai_job', v_job,
         jsonb_build_object('job_type',p_job_type,'conversation_id',v_conversation), v_actor);
  return jsonb_build_object('job_id',v_job,'conversation_id',v_conversation,'status','queued');
end;
$$;

revoke all on function public.create_invitation_with_audit(uuid,text,text,uuid,text,text) from public, anon;
revoke all on function public.queue_ai_request_with_audit(uuid,text,text,jsonb,text) from public, anon;
grant execute on function public.create_invitation_with_audit(uuid,text,text,uuid,text,text) to authenticated;
grant execute on function public.queue_ai_request_with_audit(uuid,text,text,jsonb,text) to authenticated;

-- Defense in depth: authenticated callers cannot bypass the API AI_ENABLED gate by invoking
-- the RPC directly. Only trusted database administration can change this private setting.
create table public.platform_ai_settings (
  singleton boolean primary key default true check (singleton),
  ai_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.platform_ai_settings enable row level security;
insert into public.platform_ai_settings(singleton, ai_enabled) values (true, false);
revoke all on public.platform_ai_settings from public, anon, authenticated;
revoke all on public.platform_ai_settings from service_role;

-- A fresh token on every claim fences an expired worker from later status updates.
alter table public.document_processing_jobs add column lease_token uuid;
alter table public.ai_jobs add column lease_token uuid;
alter table public.document_chunks add column processing_job_id uuid;
alter table public.document_chunks add column processing_lease_token uuid;
alter table public.ai_messages add column processing_lease_token uuid;
alter table public.ai_reports add column processing_lease_token uuid;
alter table public.ai_citations add column processing_lease_token uuid;
-- A newly registered immutable version always gets exactly one extraction job in the same
-- transaction, whether registration happens through the application RPC or trusted service code.
create or replace function public.enqueue_document_extraction_for_version()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_actor uuid := coalesce(auth.uid(), new.created_by);
begin
  if v_actor is null then raise exception 'processing requester required'; end if;
  insert into public.document_processing_jobs(project_id, document_version_id, job_type, status, idempotency_key, requested_by, created_by, updated_by)
  values(new.project_id, new.id, 'extract', 'queued', 'extract:' || new.id::text, v_actor, v_actor, v_actor)
  on conflict (project_id, idempotency_key) do nothing;
  return new;
end;
$$;
revoke all on function public.enqueue_document_extraction_for_version() from public, anon, authenticated;
create trigger document_versions_enqueue_extraction
  after insert on public.document_versions
  for each row execute function public.enqueue_document_extraction_for_version();

create index document_processing_jobs_processing_lease_idx
  on public.document_processing_jobs(locked_at, created_at) where status = 'processing';
create index ai_jobs_processing_lease_idx
  on public.ai_jobs(locked_at, created_at) where status = 'processing';
create unique index ai_messages_job_assistant_unique
  on public.ai_messages(ai_job_id) where ai_job_id is not null and role = 'assistant';
create unique index ai_reports_job_unique
  on public.ai_reports(ai_job_id) where ai_job_id is not null;
create unique index ai_citations_job_chunk_unique
  on public.ai_citations(ai_job_id, chunk_id) where ai_job_id is not null and chunk_id is not null;
create unique index ai_citations_job_research_unique
  on public.ai_citations(ai_job_id, research_entry_id) where ai_job_id is not null and research_entry_id is not null;
create unique index ai_citations_report_chunk_unique
  on public.ai_citations(ai_report_id, chunk_id) where ai_report_id is not null and chunk_id is not null;
create unique index ai_citations_report_research_unique
  on public.ai_citations(ai_report_id, research_entry_id) where ai_report_id is not null and research_entry_id is not null;
create or replace function public.claim_document_processing_job(p_worker_id uuid)
returns setof public.document_processing_jobs language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required'; end if;
  update public.document_processing_jobs
     set status='failed', locked_by=null, locked_at=null, error_code='lease_expired',
         lease_token=null, error_message='Worker lease expired after the final allowed attempt.', next_attempt_at=now()
   where status='processing' and attempts >= max_attempts and locked_at < now()-interval '30 minutes';
  return query
    with candidate as (
      select id from public.document_processing_jobs
       where ((status in ('queued','failed') and attempts < max_attempts and next_attempt_at <= now())
          or (status='processing' and attempts < max_attempts and locked_at < now()-interval '30 minutes'))
       order by case when status='processing' then locked_at else next_attempt_at end, created_at
       for update skip locked limit 1
    )
    update public.document_processing_jobs j
       set status='processing', attempts=j.attempts+1, locked_by=p_worker_id, locked_at=now(),
           lease_token=gen_random_uuid(), error_code=null, error_message=null, next_attempt_at=now()
      from candidate c where j.id=c.id returning j.*;
end;
$$;

create or replace function public.claim_ai_job(p_worker_id uuid)
returns setof public.ai_jobs language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required'; end if;
  if not exists (select 1 from public.platform_ai_settings where singleton and ai_enabled) then return; end if;
  update public.ai_jobs
     set status='failed', locked_by=null, locked_at=null, error_code='lease_expired',
         lease_token=null, error_message='Worker lease expired after the final allowed attempt.', next_attempt_at=now(), completed_at=now()
   where status='processing' and attempts >= max_attempts and locked_at < now()-interval '30 minutes';
  return query
    with candidate as (
      select id from public.ai_jobs
       where ((status in ('queued','failed') and attempts < max_attempts and next_attempt_at <= now())
          or (status='processing' and attempts < max_attempts and locked_at < now()-interval '30 minutes'))
       order by case when status='processing' then locked_at else next_attempt_at end, created_at
       for update skip locked limit 1
    )
    update public.ai_jobs j
       set status='processing', attempts=j.attempts+1, locked_by=p_worker_id, locked_at=now(),
           lease_token=gen_random_uuid(),
           started_at=coalesce(j.started_at,now()), error_code=null, error_message=null,
           completed_at=null, next_attempt_at=now()
      from candidate c where j.id=c.id returning j.*;
end;
$$;
revoke all on function public.claim_document_processing_job(uuid) from public, anon, authenticated;
revoke all on function public.claim_ai_job(uuid) from public, anon, authenticated;
grant execute on function public.claim_document_processing_job(uuid) to service_role;
grant execute on function public.claim_ai_job(uuid) to service_role;

-- Processing metadata is visible only when the parent document/version is visible to the caller.
drop policy if exists document_processing_jobs_read on public.document_processing_jobs;
create policy document_processing_jobs_read on public.document_processing_jobs for select to authenticated
using (exists (
  select 1 from public.document_versions v
  join public.documents d on d.id=v.document_id and d.project_id=v.project_id
  where v.id=document_processing_jobs.document_version_id
    and v.project_id=document_processing_jobs.project_id
    and ((d.visibility <> 'private' and public.can_read_project(d.project_id,d.visibility,d.status='approved'))
      or (d.created_by=auth.uid() and public.has_project_role(d.project_id,array['Project Lead','Secretary','Researcher']))
      or public.has_project_role(d.project_id,array['Project Lead','Secretary']))
));

-- Browser-authenticated writes must use the narrow SECURITY DEFINER workflows above.
-- Keep SELECT policies/grants intact, and allow only the notification read-marker column update.
-- Each side effect locks and renews its job row in the same transaction as the write.
-- A stale worker either commits before a reclaiming claim, or fails after it.
create or replace function public.touch_document_processing_lease(
  p_job_id uuid, p_lease_token uuid, p_project_id uuid, p_document_version_id uuid
) returns void language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  update public.document_processing_jobs
     set locked_at=now()
   where id=p_job_id and project_id=p_project_id
     and document_version_id=p_document_version_id
     and status='processing' and lease_token=p_lease_token;
  if not found then raise exception 'document processing lease lost' using errcode='55000'; end if;
end;
$$;

create or replace function public.guard_document_chunk_lease()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  if new.processing_job_id is null or new.processing_lease_token is null then
    raise exception 'document processing lease required' using errcode='55000';
  end if;
  perform public.touch_document_processing_lease(
    new.processing_job_id, new.processing_lease_token, new.project_id, new.document_version_id
  );
  return new;
end;
$$;
create trigger document_chunks_require_active_lease
  before insert or update on public.document_chunks
  for each row execute function public.guard_document_chunk_lease();

create or replace function public.touch_ai_job_lease(p_job_id uuid, p_lease_token uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  update public.ai_jobs set locked_at=now()
   where id=p_job_id and status='processing' and lease_token=p_lease_token;
  if not found then raise exception 'AI job lease lost' using errcode='55000'; end if;
end;
$$;

create or replace function public.guard_ai_message_lease()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  if new.role='assistant' then
    if new.ai_job_id is null or new.processing_lease_token is null then
      raise exception 'AI job lease required' using errcode='55000';
    end if;
    perform public.touch_ai_job_lease(new.ai_job_id, new.processing_lease_token);
  end if;
  return new;
end;
$$;
create trigger ai_messages_require_active_lease
  before insert on public.ai_messages
  for each row execute function public.guard_ai_message_lease();

create or replace function public.guard_ai_report_lease()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
begin
  if new.ai_job_id is not null then
    if new.processing_lease_token is null then
      raise exception 'AI job lease required' using errcode='55000';
    end if;
    perform public.touch_ai_job_lease(new.ai_job_id, new.processing_lease_token);
  end if;
  return new;
end;
$$;
create trigger ai_reports_require_active_lease
  before insert on public.ai_reports
  for each row execute function public.guard_ai_report_lease();

create or replace function public.guard_ai_citation_lease()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare
  v_job_id uuid := new.ai_job_id;
begin
  if v_job_id is null and new.ai_report_id is not null then
    select ai_job_id into v_job_id from public.ai_reports where id=new.ai_report_id;
  end if;
  if v_job_id is not null then
    if new.processing_lease_token is null then
      raise exception 'AI job lease required' using errcode='55000';
    end if;
    perform public.touch_ai_job_lease(v_job_id, new.processing_lease_token);
  end if;
  return new;
end;
$$;
create trigger ai_citations_require_active_lease
  before insert on public.ai_citations
  for each row execute function public.guard_ai_citation_lease();

revoke all on function public.touch_document_processing_lease(uuid,uuid,uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function public.guard_document_chunk_lease() from public, anon, authenticated, service_role;
revoke all on function public.touch_ai_job_lease(uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function public.guard_ai_message_lease() from public, anon, authenticated, service_role;
revoke all on function public.guard_ai_report_lease() from public, anon, authenticated, service_role;
revoke all on function public.guard_ai_citation_lease() from public, anon, authenticated, service_role;

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
  ] loop
    execute format('revoke insert, update, delete on table public.%I from anon, authenticated', t);
  end loop;
end;
$$;
revoke insert (id,display_name,phone_e164,locale,created_by,updated_by) on public.profiles from authenticated;
revoke update (display_name,phone_e164,locale,updated_by) on public.profiles from authenticated;
revoke update (title,description,priority,due_at,updated_by) on public.tasks from authenticated;
revoke update (enabled,updated_by) on public.notification_preferences from authenticated;
revoke update (read_at) on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

commit;
