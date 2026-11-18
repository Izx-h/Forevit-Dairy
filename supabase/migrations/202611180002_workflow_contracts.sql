-- Forevit workflow contracts and secure transactional RPCs.
-- Source artifact only: no database connection or deployment was performed.
begin;

alter table public.profiles add column email citext;
alter table public.documents add column current_version_id uuid;
alter table public.documents
  add constraint documents_current_version_project_fk
  foreign key (current_version_id, project_id)
  references public.document_versions(id, project_id) on delete restrict;
alter table public.ai_jobs add column result_reference jsonb;
alter table public.ai_reports add column review_comment text;
alter table public.lab_test_procedures add column notes text;

-- Small lookup indexes support the newly added optional references and audit workflows.
create index documents_current_version_idx on public.documents(current_version_id) where current_version_id is not null;
create index ai_jobs_result_reference_gin_idx on public.ai_jobs using gin (result_reference) where result_reference is not null;

-- The initial migration granted table-wide profile reads. Keep that surface unchanged except
-- that the newly added email stays private to trusted server-side workflows.
revoke select on public.profiles from authenticated;
grant select (id,display_name,phone_e164,locale,platform_owner,created_at,updated_at,created_by,updated_by)
  on public.profiles to authenticated;
revoke insert on public.profiles from authenticated;
grant insert (id,display_name,phone_e164,locale,created_by,updated_by)
  on public.profiles to authenticated;

create or replace function public.guard_document_current_version()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public set row_security = off as $$
declare v_doc uuid; v_project uuid;
begin
  if new.current_version_id is not null then
    select document_id,project_id into v_doc,v_project from public.document_versions where id=new.current_version_id;
    if not found or v_doc is distinct from new.id or v_project is distinct from new.project_id then
      raise exception 'current version must belong to this document and project';
    end if;
  end if;
  return new;
end;
$$;
create trigger documents_current_version_guard
before insert or update of current_version_id,project_id on public.documents
for each row execute function public.guard_document_current_version();
revoke all on function public.guard_document_current_version() from public,anon;

-- The five-argument RPC remains in the catalog for compatibility, but may no longer be called
-- by application users. The six-argument contract below is the only authenticated entry point.
revoke all on function public.create_lab_test_with_audit(uuid,uuid,text,text,timestamptz) from public, anon, authenticated;

create or replace function public.accept_pending_invitation(p_raw_token text)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
declare
  v_actor uuid := auth.uid();
  v_email text;
  v_inv public.invitations%rowtype;
  v_status text;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if coalesce(auth.jwt()->>'email_verified','false') <> 'true' then raise exception 'verified email required'; end if;
  v_email := auth.jwt()->>'email';
  if v_email is null or length(btrim(coalesce(p_raw_token,''))) = 0 then
    raise exception 'valid invitation and email required';
  end if;

  -- Only the verified JWT is used to populate/refresh profile.email. Never persist or log
  -- the bearer token; lookup uses only its SHA-256 digest and preserves the invited-email match.
  insert into public.profiles(id,display_name,email,created_by,updated_by)
  values(v_actor,
         left(coalesce(nullif(btrim(auth.jwt()->'user_metadata'->>'full_name'),''),
                       split_part(v_email,'@',1),'Member'),200),
         v_email::citext,v_actor,v_actor)
  on conflict (id) do update
    set email = excluded.email, updated_by = v_actor;

  select * into v_inv
    from public.invitations i
   where i.token_hash = digest(convert_to(p_raw_token,'UTF8'),'sha256')
     and i.email = v_email::citext
     and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()
   for update;
  if not found then raise exception 'invitation unavailable'; end if;

  select status into v_status
    from public.organization_members
   where organization_id=v_inv.organization_id and user_id=v_actor for update;
  if v_status='active' then
    null;
  elsif found then
    update public.organization_members
       set role=v_inv.role,status='active',joined_at=coalesce(joined_at,now()),updated_by=v_actor
     where organization_id=v_inv.organization_id and user_id=v_actor;
  else
    insert into public.organization_members(organization_id,user_id,role,status,joined_at,created_by,updated_by)
    values(v_inv.organization_id,v_actor,v_inv.role,'active',now(),v_actor,v_actor);
  end if;

  if v_inv.project_id is not null then
    select status into v_status from public.project_members
     where project_id=v_inv.project_id and user_id=v_actor for update;
    if v_status='active' then
      null;
    elsif found then
      update public.project_members
         set role=v_inv.project_role,status='active',joined_at=coalesce(joined_at,now()),updated_by=v_actor
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

create or replace function public.create_document_with_audit(
  p_project_id uuid,p_title text,p_description text,p_category text,p_visibility text
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid := auth.uid(); v_doc uuid; v_org uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if length(btrim(coalesce(p_title,'')))=0 then raise exception 'document title required'; end if;
  if p_category not in ('paper','procedure','result','formulation','technical_report','minutes','manual','presentation','other') then raise exception 'invalid document category'; end if;
  if p_visibility not in ('private','project','approved') then raise exception 'invalid document visibility'; end if;
  if not public.has_project_role(p_project_id,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  select organization_id into v_org from public.projects where id=p_project_id;
  if not found then raise exception 'project not found'; end if;
  insert into public.documents(project_id,title,description,category,visibility,status,created_by,updated_by)
  values(p_project_id,btrim(p_title),p_description,p_category,p_visibility,'draft',v_actor,v_actor)
  returning id into v_doc;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,p_project_id,v_actor,'document_created','document',v_doc,
         jsonb_build_object('category',p_category,'visibility',p_visibility),v_actor);
  return v_doc;
end;
$$;

create or replace function public.register_document_version(
  p_document_id uuid,p_storage_bucket text,p_storage_path text,p_file_name text,p_mime_type text,
  p_byte_size bigint,p_sha256_hex text,p_change_note text
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid := auth.uid(); v_project uuid; v_org uuid; v_no integer; v_ver uuid; v_doc_creator uuid; v_doc_status text;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  select d.project_id,p.organization_id,d.created_by,d.status into v_project,v_org,v_doc_creator,v_doc_status
    from public.documents d join public.projects p on p.id=d.project_id
   where d.id=p_document_id for update of d;
  if not found then raise exception 'document not found'; end if;
  if public.has_project_role(v_project,array['Project Lead','Secretary']) then
    null;
  elsif public.has_project_role(v_project,array['Researcher']) and v_doc_creator=v_actor and v_doc_status in ('draft','in_review') then
    null;
  else
    raise exception 'not authorized to update this document';
  end if;
  if length(btrim(coalesce(p_storage_bucket,'')))=0 or length(btrim(coalesce(p_file_name,'')))=0
     or length(btrim(coalesce(p_mime_type,'')))=0 then raise exception 'storage bucket, file name, and MIME type required'; end if;
  if p_byte_size is null or p_byte_size<=0 or p_byte_size>20971520 then raise exception 'file must be between 1 byte and 20 MiB'; end if;
  if p_sha256_hex is null or p_sha256_hex !~ '^[0-9a-fA-F]{64}$' then raise exception 'valid SHA-256 hex digest required'; end if;
  if p_storage_path is null or p_storage_path like '%..%' or
     left(p_storage_path,length(v_project::text||'/'||v_actor::text||'/')) <> v_project::text||'/'||v_actor::text||'/' or
     length(p_storage_path) <= length(v_project::text||'/'||v_actor::text||'/') then
    raise exception 'storage path must be scoped to project and actor and contain no traversal';
  end if;
  select coalesce(max(version_no),0)+1 into v_no from public.document_versions where document_id=p_document_id;
  insert into public.document_versions(project_id,document_id,version_no,file_name,mime_type,byte_size,storage_bucket,storage_path,sha256_hex,change_note,created_by)
  values(v_project,p_document_id,v_no,btrim(p_file_name),btrim(p_mime_type),p_byte_size,btrim(p_storage_bucket),p_storage_path,lower(p_sha256_hex),p_change_note,v_actor)
  returning id into v_ver;
  update public.documents set current_version_id=v_ver,updated_by=v_actor where id=p_document_id;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,v_project,v_actor,'document_version_registered','document',p_document_id,
         jsonb_build_object('version_id',v_ver,'version_no',v_no,'byte_size',p_byte_size),v_actor);
  return v_ver;
end;
$$;

create or replace function public.create_research_entry_with_audit(
  p_project_id uuid,p_title text,p_abstract text,p_methodology text,p_findings text,p_source_type text,p_document_id uuid
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_entry uuid; v_version uuid; v_type text; v_body text; v_org uuid; v_visibility text; v_doc_status text; v_doc_creator uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if length(btrim(coalesce(p_title,'')))=0 then raise exception 'entry title required'; end if;
  if p_source_type not in ('literature','internal_study','hypothesis','other') then raise exception 'invalid source type'; end if;
  if not public.has_project_role(p_project_id,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  v_type := case p_source_type when 'literature' then 'literature_note' when 'internal_study' then 'observation' when 'hypothesis' then 'hypothesis' else 'other' end;
  v_body := concat_ws(E'\n\n',
    case when nullif(btrim(p_abstract),'') is not null then 'Abstract'||E'\n'||btrim(p_abstract) end,
    case when nullif(btrim(p_methodology),'') is not null then 'Methodology'||E'\n'||btrim(p_methodology) end,
    case when nullif(btrim(p_findings),'') is not null then 'Findings'||E'\n'||btrim(p_findings) end);
  if v_body='' then v_body:=btrim(p_title); end if;
  if p_document_id is not null then
    select d.current_version_id,d.visibility,d.status,d.created_by into v_version,v_visibility,v_doc_status,v_doc_creator
      from public.documents d where d.id=p_document_id and d.project_id=p_project_id;
    if not found or v_version is null then raise exception 'source document must have a current version in this project'; end if;
    if not ((v_visibility<>'private' and public.can_read_project(p_project_id,v_visibility,v_doc_status='approved'))
      or (v_doc_creator=v_actor and public.has_project_role(p_project_id,array['Project Lead','Secretary','Researcher']))
      or public.has_project_role(p_project_id,array['Project Lead','Secretary'])) then
      raise exception 'source document is not visible to the caller';
    end if;
  end if;
  select organization_id into v_org from public.projects where id=p_project_id;
  insert into public.research_entries(project_id,title,body,entry_type,source_document_version_id,created_by,updated_by)
  values(p_project_id,btrim(p_title),v_body,v_type,v_version,v_actor,v_actor) returning id into v_entry;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,p_project_id,v_actor,'research_entry_created','research_entry',v_entry,
         jsonb_build_object('source_type',p_source_type,'document_version_id',v_version),v_actor);
  return v_entry;
end;
$$;

create or replace function public.update_task_with_audit(p_task_id uuid,p_priority text,p_due_at timestamptz)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_project uuid; v_org uuid; v_old_priority text; v_old_due timestamptz; v_new_priority text; v_new_due timestamptz;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  select t.project_id,p.organization_id,t.priority,t.due_at into v_project,v_org,v_old_priority,v_old_due
    from public.tasks t join public.projects p on p.id=t.project_id where t.id=p_task_id for update of t;
  if not found then raise exception 'task not found'; end if;
  if not public.has_project_role(v_project,array['Project Lead','Secretary']) then raise exception 'project reviewer role required'; end if;
  v_new_priority:=coalesce(p_priority,v_old_priority); v_new_due:=coalesce(p_due_at,v_old_due);
  if v_new_priority not in ('low','normal','high','urgent') then raise exception 'invalid priority'; end if;
  if v_new_priority is distinct from v_old_priority or v_new_due is distinct from v_old_due then
    update public.tasks set priority=v_new_priority,due_at=v_new_due,updated_by=v_actor where id=p_task_id;
    insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
    values(v_org,v_project,v_actor,'task_updated','task',p_task_id,
           jsonb_build_object('priority_before',v_old_priority,'priority_after',v_new_priority,'due_at_before',v_old_due,'due_at_after',v_new_due),v_actor);
  end if;
  return p_task_id;
end;
$$;

create or replace function public.submit_task_with_audit(p_task_id uuid,p_description text,p_document_version_ids uuid[])
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_project uuid; v_status text; v_no integer; v_submission uuid; v_org uuid; v_count integer;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  select t.project_id,t.status,p.organization_id into v_project,v_status,v_org
    from public.tasks t join public.projects p on p.id=t.project_id where t.id=p_task_id for update of t;
  if not found then raise exception 'task not found'; end if;
  if v_status not in ('in_progress','changes_requested') then raise exception 'task is not in a submittable state'; end if;
  if not ((public.has_project_role(v_project,array['Researcher']) and public.is_active_task_assignee(p_task_id))
          or public.has_project_role(v_project,array['Project Lead','Secretary'])) then raise exception 'active assignee researcher or project admin required'; end if;
  if p_document_version_ids is not null then
    if exists(select 1 from unnest(p_document_version_ids) x(id) where x.id is null) then raise exception 'document version IDs cannot contain null'; end if;
    select count(*) into v_count from unnest(p_document_version_ids) x(id)
      join public.document_versions dv on dv.id=x.id and dv.project_id=v_project;
    if v_count<>cardinality(p_document_version_ids) then raise exception 'all submitted document versions must belong to this project'; end if;
    if (select count(distinct id) from unnest(p_document_version_ids) x(id))<>cardinality(p_document_version_ids) then raise exception 'duplicate document version IDs'; end if;
  end if;
  select coalesce(max(submission_no),0)+1 into v_no from public.task_submissions where task_id=p_task_id;
  insert into public.task_submissions(project_id,task_id,submission_no,description,submitted_by,created_by)
  values(v_project,p_task_id,v_no,p_description,v_actor,v_actor) returning id into v_submission;
  insert into public.task_submission_documents(project_id,submission_id,document_version_id,created_by)
  select v_project,v_submission,x.id,v_actor from unnest(coalesce(p_document_version_ids,'{}'::uuid[])) x(id);
  perform public.transition_task_status(p_task_id,'submitted',null);
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,v_project,v_actor,'task_submission_created','task_submission',v_submission,
         jsonb_build_object('task_id',p_task_id,'submission_no',v_no,'document_count',coalesce(cardinality(p_document_version_ids),0)),v_actor);
  return v_submission;
end;
$$;

create or replace function public.review_task_submission(p_task_id uuid,p_submission_id uuid,p_decision text,p_comments text)
returns void language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_project uuid; v_status text; v_latest uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if p_decision not in ('approved','changes_requested') then raise exception 'invalid review decision'; end if;
  select project_id,status into v_project,v_status from public.tasks where id=p_task_id for update;
  if not found then raise exception 'task not found'; end if;
  if not public.has_project_role(v_project,array['Project Lead','Secretary']) then raise exception 'project reviewer role required'; end if;
  select id into v_latest from public.task_submissions where task_id=p_task_id order by submission_no desc limit 1;
  if v_latest is null or v_latest<>p_submission_id then raise exception 'review must target the latest task submission'; end if;
  if v_status<>'submitted' then raise exception 'task must be submitted before review'; end if;
  -- Existing RPC inserts immutable review history on the final transition and enforces the state machine.
  perform public.transition_task_status(p_task_id,'under_review',null);
  perform public.transition_task_status(p_task_id,p_decision,p_comments);
end;
$$;

create or replace function public.create_lab_test_with_audit(
  p_project_id uuid,p_sample_id uuid,p_test_name text,p_objective text,p_planned_at timestamptz,p_assignee_ids uuid[]
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_test uuid; v_org uuid; v_count integer;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if length(btrim(coalesce(p_test_name,'')))=0 then raise exception 'test name required'; end if;
  if not public.has_project_role(p_project_id,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  if p_assignee_ids is null or cardinality(p_assignee_ids)=0 or not (v_actor=any(p_assignee_ids)) then raise exception 'assign the caller and at least one active project member'; end if;
  if exists(select 1 from unnest(p_assignee_ids) a(id) where a.id is null) then raise exception 'assignee IDs cannot contain null'; end if;
  select count(*) into v_count from unnest(p_assignee_ids) a(id)
    join public.project_members pm on pm.project_id=p_project_id and pm.user_id=a.id and pm.status='active' and pm.role<>'Viewer'
    join public.projects pr on pr.id=pm.project_id
    join public.organization_members om on om.organization_id=pr.organization_id and om.user_id=pm.user_id and om.status='active';
  if v_count<>cardinality(p_assignee_ids) or
     (select count(distinct id) from unnest(p_assignee_ids) a(id))<>cardinality(p_assignee_ids) then
    raise exception 'every assignee must be a unique active non-viewer project member';
  end if;
  select organization_id into v_org from public.projects where id=p_project_id;
  insert into public.lab_tests(project_id,sample_id,title,objective,planned_at,created_by,updated_by)
  values(p_project_id,p_sample_id,btrim(p_test_name),p_objective,p_planned_at,v_actor,v_actor) returning id into v_test;
  insert into public.lab_assignments(project_id,lab_test_id,assignee_id,created_by)
  select p_project_id,v_test,a.id,v_actor from unnest(p_assignee_ids) a(id);
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,p_project_id,v_actor,'lab_test_created','lab_test',v_test,
         jsonb_build_object('assignee_count',cardinality(p_assignee_ids)),v_actor);
  return v_test;
end;
$$;

create or replace function public.add_lab_test_procedure(p_lab_test_id uuid,p_document_version_id uuid,p_note text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_project uuid; v_doc uuid; v_link uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  select project_id into v_project from public.lab_tests where id=p_lab_test_id;
  if not found then raise exception 'lab test not found'; end if;
  if not public.has_project_role(v_project,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  select d.id into v_doc from public.document_versions dv join public.documents d on d.id=dv.document_id and d.project_id=dv.project_id
   where dv.id=p_document_version_id and dv.project_id=v_project and d.category='procedure';
  if not found then raise exception 'procedure version must be an exact version in the same project'; end if;
  insert into public.lab_test_procedures(project_id,lab_test_id,procedure_document_version_id,notes,created_by)
  values(v_project,p_lab_test_id,p_document_version_id,p_note,v_actor) returning id into v_link;
  insert into public.activity_logs(project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_project,v_actor,'lab_procedure_linked','lab_test_procedure',v_link,
         jsonb_build_object('lab_test_id',p_lab_test_id,'document_version_id',p_document_version_id),v_actor);
  return v_link;
end;
$$;

create or replace function public.submit_lab_result_with_audit(
  p_lab_test_id uuid,p_conditions jsonb,p_equipment jsonb,p_observations text,p_deviations text,
  p_conclusion text,p_correction_reason text,p_measurements jsonb,p_document_version_ids uuid[]
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare
  v_actor uuid:=auth.uid(); v_project uuid; v_org uuid; v_status text; v_latest uuid; v_no integer; v_result uuid; v_count integer;
  v_item jsonb; v_num numeric; v_text text; v_idx integer;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  select t.project_id,p.organization_id,t.status into v_project,v_org,v_status
    from public.lab_tests t join public.projects p on p.id=t.project_id where t.id=p_lab_test_id for update of t;
  if not found then raise exception 'lab test not found'; end if;
  if not ((public.has_project_role(v_project,array['Researcher']) and public.is_active_lab_assignee(p_lab_test_id))
          or public.has_project_role(v_project,array['Project Lead','Secretary'])) then raise exception 'active assigned researcher or project admin required'; end if;
  select id,revision_no into v_latest,v_no from public.lab_results where lab_test_id=p_lab_test_id order by revision_no desc limit 1 for update;
  if v_latest is null then
    v_no:=1;
    if p_correction_reason is not null and length(btrim(p_correction_reason))>0 then raise exception 'initial result cannot have a correction reason'; end if;
  else
    if v_status<>'changes_requested' then raise exception 'a correction is allowed only after changes were requested'; end if;
    if length(btrim(coalesce(p_correction_reason,'')))=0 then raise exception 'corrected revision requires a nonempty reason'; end if;
    v_no:=v_no+1;
  end if;
  if p_measurements is not null and jsonb_typeof(p_measurements)<>'array' then raise exception 'measurements must be a JSON array'; end if;
  insert into public.lab_results(project_id,lab_test_id,revision_no,supersedes_result_id,summary,conditions,equipment,observations,deviations,conclusion,correction_reason,created_by)
  values(v_project,p_lab_test_id,v_no,v_latest,nullif(btrim(coalesce(p_conclusion,'')),''),coalesce(p_conditions,'{}'::jsonb),coalesce(p_equipment,'[]'::jsonb),p_observations,p_deviations,p_conclusion,nullif(btrim(p_correction_reason),''),v_actor)
  returning id into v_result;
  if p_measurements is not null then
    v_idx:=0;
    for v_item in select value from jsonb_array_elements(p_measurements) loop
      v_idx:=v_idx+1;
      if jsonb_typeof(v_item)<>'object' then raise exception 'each measurement must be an object'; end if;
      if nullif(btrim(v_item->>'parameter_name'),'') is null or nullif(btrim(v_item->>'unit'),'') is null or nullif(btrim(v_item->>'method'),'') is null then raise exception 'each measurement requires parameter_name, unit, and method'; end if;
      v_num:=null; v_text:=null;
      if v_item ? 'numeric_value' and v_item->'numeric_value'<>'null'::jsonb then
        if jsonb_typeof(v_item->'numeric_value')<>'number' then raise exception 'numeric_value must be JSON numeric'; end if;
        v_num:=(v_item->>'numeric_value')::numeric;
      end if;
      if v_item ? 'text_value' and v_item->'text_value'<>'null'::jsonb then v_text:=v_item->>'text_value'; end if;
      if (v_num is not null)::integer + (v_text is not null)::integer <> 1 then raise exception 'measurement requires exactly one numeric_value or text_value'; end if;
      insert into public.lab_measurements(project_id,result_id,parameter_name,numeric_value,text_value,unit,method,notes,measured_at,created_by)
      values(v_project,v_result,btrim(v_item->>'parameter_name'),v_num,v_text,btrim(v_item->>'unit'),btrim(v_item->>'method'),v_item->>'notes',nullif(v_item->>'measured_at','')::timestamptz,v_actor);
    end loop;
  end if;
  if p_document_version_ids is not null then
    if exists(select 1 from unnest(p_document_version_ids) x(id) where x.id is null) then raise exception 'document version IDs cannot contain null'; end if;
    select count(*) into v_count from unnest(p_document_version_ids) x(id) join public.document_versions dv on dv.id=x.id and dv.project_id=v_project;
    if v_count<>cardinality(p_document_version_ids) or (select count(distinct id) from unnest(p_document_version_ids) x(id))<>cardinality(p_document_version_ids) then raise exception 'result attachments must be unique document versions in this project'; end if;
    insert into public.lab_result_documents(project_id,result_id,document_version_id,created_by)
    select v_project,v_result,x.id,v_actor from unnest(p_document_version_ids) x(id);
  end if;
  update public.lab_tests set status='submitted',updated_by=v_actor where id=p_lab_test_id;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,v_project,v_actor,'lab_result_submitted','lab_result',v_result,
         jsonb_build_object('lab_test_id',p_lab_test_id,'revision_no',v_no,'supersedes_result_id',v_latest,'measurement_count',coalesce(jsonb_array_length(p_measurements),0),'document_count',coalesce(cardinality(p_document_version_ids),0)),v_actor);
  return v_result;
end;
$$;

create or replace function public.review_lab_result(p_result_id uuid,p_decision text,p_comments text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_project uuid; v_test uuid; v_result_status text; v_test_status text; v_review uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if p_decision not in ('approved','changes_requested') then raise exception 'invalid review decision'; end if;
  select r.project_id,r.lab_test_id,r.status,t.status into v_project,v_test,v_result_status,v_test_status
    from public.lab_results r join public.lab_tests t on t.id=r.lab_test_id where r.id=p_result_id for update of t;
  if not found then raise exception 'lab result not found'; end if;
  if not public.has_project_role(v_project,array['Project Lead','Secretary']) then raise exception 'project reviewer role required'; end if;
  if v_test_status not in ('submitted','under_review') then raise exception 'lab test is not awaiting review'; end if;
  if exists(select 1 from public.lab_reviews where result_id=p_result_id) then raise exception 'result already reviewed'; end if;
  insert into public.lab_reviews(project_id,result_id,decision,comments,reviewer_id,created_by)
  values(v_project,p_result_id,p_decision,p_comments,v_actor,v_actor) returning id into v_review;
  update public.lab_tests set status=p_decision,updated_by=v_actor where id=v_test;
  insert into public.activity_logs(project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_project,v_actor,'lab_result_reviewed','lab_result',p_result_id,
         jsonb_build_object('decision',p_decision,'review_id',v_review),v_actor);
  return v_review;
end;
$$;

create or replace function public.create_formulation_version(
  p_formulation_id uuid,p_batch_basis text,p_instructions text,p_change_rationale text,p_ingredients jsonb
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare
  v_actor uuid:=auth.uid(); v_project uuid; v_org uuid; v_no integer; v_previous uuid; v_version uuid;
  v_item jsonb; v_quantity numeric; v_ordinal bigint;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  select f.project_id,p.organization_id into v_project,v_org from public.formulations f join public.projects p on p.id=f.project_id where f.id=p_formulation_id for update of f;
  if not found then raise exception 'formulation not found'; end if;
  if not public.has_project_role(v_project,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  if length(btrim(coalesce(p_change_rationale,'')))=0 then raise exception 'a nonempty change rationale is required for subsequent versions'; end if;
  if p_ingredients is not null and jsonb_typeof(p_ingredients)<>'array' then raise exception 'ingredients must be a JSON array'; end if;
  select id,version_no into v_previous,v_no from public.formulation_versions where formulation_id=p_formulation_id order by version_no desc limit 1;
  if v_previous is null then raise exception 'version 1 must be created atomically by create_formulation_with_audit'; end if;
  v_no:=v_no+1;
  -- Immutable history is preserved; supersedes_version_id carries the revision chain without mutating old rows.
  insert into public.formulation_versions(project_id,formulation_id,version_no,batch_basis,instructions,change_rationale,supersedes_version_id,created_by)
  values(v_project,p_formulation_id,v_no,p_batch_basis,p_instructions,btrim(p_change_rationale),v_previous,v_actor) returning id into v_version;
  if p_ingredients is not null then
    for v_item,v_ordinal in select value,ordinality from jsonb_array_elements(p_ingredients) with ordinality loop
      if jsonb_typeof(v_item)<>'object' or nullif(btrim(v_item->>'ingredient_name'),'') is null or nullif(btrim(v_item->>'unit'),'') is null or nullif(btrim(v_item->>'interpretation_basis'),'') is null then raise exception 'each ingredient requires ingredient_name, unit, and interpretation_basis'; end if;
      if jsonb_typeof(v_item->'quantity')<>'number' then raise exception 'ingredient quantity must be numeric'; end if;
      v_quantity:=(v_item->>'quantity')::numeric;
      if v_quantity<0 then raise exception 'ingredient quantity cannot be negative'; end if;
      insert into public.formulation_ingredients(project_id,formulation_version_id,ingredient_name,quantity,unit,interpretation_basis,sequence_no,notes,created_by)
      values(v_project,v_version,btrim(v_item->>'ingredient_name'),v_quantity,btrim(v_item->>'unit'),btrim(v_item->>'interpretation_basis'),v_ordinal::integer,v_item->>'notes',v_actor);
    end loop;
  end if;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,v_project,v_actor,'formulation_version_created','formulation_version',v_version,
         jsonb_build_object('formulation_id',p_formulation_id,'version_no',v_no,'supersedes_version_id',v_previous),v_actor);
  return v_version;
end;
$$;

create or replace function public.create_formulation_with_audit(p_project_id uuid,p_product_name text,p_description text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_formulation uuid; v_org uuid; v_version uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if length(btrim(coalesce(p_product_name,'')))=0 then raise exception 'formulation name required'; end if;
  if not public.has_project_role(p_project_id,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  select organization_id into v_org from public.projects where id=p_project_id;
  insert into public.formulations(project_id,name,description,created_by,updated_by)
  values(p_project_id,btrim(p_product_name),p_description,v_actor,v_actor) returning id into v_formulation;
  insert into public.formulation_versions(project_id,formulation_id,version_no,status,created_by)
  values(p_project_id,v_formulation,1,'draft',v_actor) returning id into v_version;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,p_project_id,v_actor,'formulation_created','formulation',v_formulation,
         jsonb_build_object('initial_version_id',v_version,'version_no',1),v_actor);
  return v_formulation;
end;
$$;

create or replace function public.add_formulation_trial(p_formulation_version_id uuid,p_lab_test_id uuid,p_observations text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_project uuid; v_test_project uuid; v_trial uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  select project_id into v_project from public.formulation_versions where id=p_formulation_version_id;
  select project_id into v_test_project from public.lab_tests where id=p_lab_test_id;
  if v_project is null or v_test_project is null or v_project<>v_test_project then raise exception 'formulation version and lab test must share a project'; end if;
  if not public.has_project_role(v_project,array['Project Lead','Secretary','Researcher']) then raise exception 'not authorized for project'; end if;
  insert into public.formulation_trials(project_id,formulation_version_id,lab_test_id,observations,created_by)
  values(v_project,p_formulation_version_id,p_lab_test_id,p_observations,v_actor) returning id into v_trial;
  insert into public.activity_logs(project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_project,v_actor,'formulation_trial_added','formulation_trial',v_trial,
         jsonb_build_object('formulation_version_id',p_formulation_version_id,'lab_test_id',p_lab_test_id),v_actor);
  return v_trial;
end;
$$;

create or replace function public.add_meeting_minutes(p_meeting_id uuid,p_document_version_id uuid)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_project uuid; v_status text; v_doc uuid; v_minutes uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  select project_id,status into v_project,v_status from public.meetings where id=p_meeting_id;
  if not found then raise exception 'meeting not found'; end if;
  if not public.has_project_role(v_project,array['Project Lead','Secretary']) then raise exception 'meeting secretary or project lead required'; end if;
  select d.id into v_doc from public.document_versions dv join public.documents d on d.id=dv.document_id and d.project_id=dv.project_id
   where dv.id=p_document_version_id and dv.project_id=v_project and d.category='minutes' and d.visibility<>'private';
  if not found then raise exception 'minutes document version must be in the same project with appropriate scope'; end if;
  insert into public.meeting_minutes(project_id,meeting_id,document_version_id,submitted_by,created_by)
  values(v_project,p_meeting_id,p_document_version_id,v_actor,v_actor) returning id into v_minutes;
  insert into public.activity_logs(project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_project,v_actor,'meeting_minutes_added','meeting_minutes',v_minutes,
         jsonb_build_object('meeting_id',p_meeting_id,'document_version_id',p_document_version_id,'meeting_status',v_status),v_actor);
  return v_minutes;
end;
$$;

create or replace function public.create_meeting_decision(p_meeting_id uuid,p_decision_text text,p_responsible_user_id uuid,p_follow_up_task_id uuid)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_project uuid; v_org uuid; v_decision uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if length(btrim(coalesce(p_decision_text,'')))=0 then raise exception 'decision text required'; end if;
  select m.project_id,p.organization_id into v_project,v_org from public.meetings m join public.projects p on p.id=m.project_id where m.id=p_meeting_id;
  if not found then raise exception 'meeting not found'; end if;
  if not public.has_project_role(v_project,array['Project Lead','Secretary']) then raise exception 'meeting secretary or project lead required'; end if;
  if p_responsible_user_id is not null and not exists(
    select 1 from public.project_members pm join public.projects pr on pr.id=pm.project_id
      join public.organization_members om on om.organization_id=pr.organization_id and om.user_id=pm.user_id
     where pm.project_id=v_project and pm.user_id=p_responsible_user_id and pm.status='active' and om.status='active') then
    raise exception 'responsible user must be an active project member';
  end if;
  if p_follow_up_task_id is not null and not exists(select 1 from public.tasks t where t.id=p_follow_up_task_id and t.project_id=v_project) then raise exception 'follow-up task must belong to the meeting project'; end if;
  insert into public.meeting_decisions(project_id,meeting_id,decision_text,responsible_user_id,follow_up_task_id,created_by)
  values(v_project,p_meeting_id,btrim(p_decision_text),p_responsible_user_id,p_follow_up_task_id,v_actor) returning id into v_decision;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,v_project,v_actor,'meeting_decision_created','meeting_decision',v_decision,
         jsonb_build_object('meeting_id',p_meeting_id,'responsible_user_id',p_responsible_user_id,'follow_up_task_id',p_follow_up_task_id),v_actor);
  return v_decision;
end;
$$;

create or replace function public.set_notification_preference(p_event_type text,p_channel text,p_enabled boolean,p_project_id uuid)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_org uuid; v_latest_action text; v_pref uuid; v_key text;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if length(btrim(coalesce(p_event_type,'')))=0 or p_channel not in ('in_app','whatsapp') or p_enabled is null then raise exception 'valid event type, channel, and enabled flag required'; end if;
  if p_project_id is not null then
    select organization_id into v_org from public.projects where id=p_project_id;
    if not found or not public.has_project_role(p_project_id,null) then raise exception 'active project membership required'; end if;
  end if;
  if p_channel='whatsapp' and p_enabled then
    if p_project_id is not null then
      select action into v_latest_action from public.notification_consents where user_id=v_actor and organization_id=v_org and channel='whatsapp' order by occurred_at desc,id desc limit 1;
    else
      select action into v_latest_action from public.notification_consents where user_id=v_actor and channel='whatsapp' order by occurred_at desc,id desc limit 1;
    end if;
    if v_latest_action is distinct from 'granted' then raise exception 'latest WhatsApp consent must be granted'; end if;
  end if;
  -- Serialize nullable-key upserts; the partial unique index covers project_id IS NULL.
  v_key:=v_actor::text||':'||coalesce(p_project_id::text,'global')||':'||p_event_type||':'||p_channel;
  perform pg_advisory_xact_lock(hashtextextended(v_key,0));
  select id into v_pref from public.notification_preferences
   where user_id=v_actor and project_id is not distinct from p_project_id and event_type=p_event_type and channel=p_channel for update;
  if found then
    update public.notification_preferences set enabled=p_enabled,updated_by=v_actor where id=v_pref;
  else
    insert into public.notification_preferences(user_id,project_id,event_type,channel,enabled,created_by,updated_by)
    values(v_actor,p_project_id,p_event_type,p_channel,p_enabled,v_actor,v_actor) returning id into v_pref;
  end if;
  return v_pref;
end;
$$;

create or replace function public.record_notification_consent(
  p_channel text,p_consent_status text,p_source text,p_phone_e164 text,p_evidence text
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_org uuid; v_count integer; v_action text; v_consent uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if p_channel<>'whatsapp' or p_consent_status not in ('granted','revoked') then raise exception 'invalid consent channel or status'; end if;
  v_action:=p_consent_status;
  select count(distinct om.organization_id) into v_count from public.organization_members om where om.user_id=v_actor and om.status='active';
  if v_count<>1 then raise exception 'consent recording requires exactly one active organization membership'; end if;
  select organization_id into v_org from public.organization_members where user_id=v_actor and status='active';
  if v_action='granted' then
    if p_phone_e164 is null or p_phone_e164 !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'opt-in requires a valid E.164 phone number'; end if;
    if length(btrim(coalesce(p_evidence,'')))=0 then raise exception 'opt-in requires nonempty evidence'; end if;
    update public.profiles set phone_e164=p_phone_e164,updated_by=v_actor where id=v_actor;
  end if;
  insert into public.notification_consents(user_id,organization_id,channel,action,phone_e164,evidence,recorded_by,created_by)
  values(v_actor,v_org,p_channel,v_action,p_phone_e164,
         jsonb_build_object('source',p_source,'evidence',p_evidence)::text,v_actor,v_actor) returning id into v_consent;
  if v_action='revoked' then
    update public.notification_preferences set enabled=false,updated_by=v_actor
     where user_id=v_actor and channel='whatsapp' and (project_id is null or exists(select 1 from public.projects p where p.id=notification_preferences.project_id and p.organization_id=v_org));
  end if;
  return v_consent;
end;
$$;

create or replace function public.update_member_role_with_audit(p_organization_id uuid,p_user_id uuid,p_role text,p_project_id uuid)
returns void language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_role text; v_project_org uuid;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  v_role:=case lower(replace(btrim(coalesce(p_role,'')),' ','_'))
    when 'project_lead' then 'Project Lead' when 'org_lead' then 'Project Lead' when 'secretary' then 'Secretary'
    when 'researcher' then 'Researcher' when 'viewer' then 'Viewer' else null end;
  if v_role is null then raise exception 'invalid member role'; end if;
  if not public.has_org_role(p_organization_id,array['Project Lead','Secretary']) then raise exception 'organization lead or secretary required'; end if;
  if not exists(select 1 from public.organization_members where organization_id=p_organization_id and user_id=p_user_id) then raise exception 'target organization membership required'; end if;
  if p_project_id is null then
    update public.organization_members set role=v_role,updated_by=v_actor where organization_id=p_organization_id and user_id=p_user_id;
    insert into public.activity_logs(organization_id,actor_id,action,entity_type,entity_id,details,created_by)
    select p_organization_id,v_actor,'organization_member_role_changed','organization_member',id,jsonb_build_object('user_id',p_user_id,'role',v_role),v_actor
      from public.organization_members where organization_id=p_organization_id and user_id=p_user_id;
  else
    select organization_id into v_project_org from public.projects where id=p_project_id;
    if v_project_org is distinct from p_organization_id then raise exception 'project must belong to the requested organization'; end if;
    if not exists(select 1 from public.project_members where project_id=p_project_id and user_id=p_user_id) then raise exception 'target project membership required'; end if;
    update public.project_members set role=v_role,updated_by=v_actor where project_id=p_project_id and user_id=p_user_id;
    insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
    select p_organization_id,p_project_id,v_actor,'project_member_role_changed','project_member',id,jsonb_build_object('user_id',p_user_id,'role',v_role),v_actor
      from public.project_members where project_id=p_project_id and user_id=p_user_id;
  end if;
end;
$$;

create or replace function public.update_member_status_with_audit(p_organization_id uuid,p_user_id uuid,p_status text)
returns void language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_status text; v_id uuid; v_project record;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  v_status:=case lower(btrim(coalesce(p_status,''))) when 'revoked' then 'removed' when 'removed' then 'removed' when 'active' then 'active' when 'suspended' then 'suspended' when 'invited' then 'invited' else null end;
  if v_status is null then raise exception 'invalid membership status'; end if;
  if not public.has_org_role(p_organization_id,array['Project Lead','Secretary']) then raise exception 'organization lead or secretary required'; end if;
  update public.organization_members set status=v_status,updated_by=v_actor where organization_id=p_organization_id and user_id=p_user_id returning id into v_id;
  if v_id is null then raise exception 'target organization membership not found'; end if;
  for v_project in select pm.id,pm.project_id from public.project_members pm join public.projects p on p.id=pm.project_id where p.organization_id=p_organization_id and pm.user_id=p_user_id loop
    update public.project_members set status=v_status,updated_by=v_actor where id=v_project.id;
    insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
    values(p_organization_id,v_project.project_id,v_actor,'project_member_status_changed','project_member',v_project.id,jsonb_build_object('user_id',p_user_id,'status',v_status),v_actor);
  end loop;
  insert into public.activity_logs(organization_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(p_organization_id,v_actor,'organization_member_status_changed','organization_member',v_id,jsonb_build_object('user_id',p_user_id,'status',v_status),v_actor);
end;
$$;

create or replace function public.review_ai_report(p_report_id uuid,p_decision text,p_comments text)
returns void language plpgsql security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_actor uuid:=auth.uid(); v_project uuid; v_status text; v_org uuid; v_new_status text;
begin
  if v_actor is null then raise exception 'authenticated user required'; end if;
  if p_decision not in ('approved','changes_requested') then raise exception 'invalid report decision'; end if;
  select r.project_id,r.status,p.organization_id into v_project,v_status,v_org
   from public.ai_reports r join public.projects p on p.id=r.project_id where r.id=p_report_id for update of r;
  if not found then raise exception 'AI report not found'; end if;
  if not public.has_project_role(v_project,array['Project Lead','Secretary']) then raise exception 'project lead or secretary required'; end if;
  if v_status not in ('draft','changes_requested') then raise exception 'report is not in a reviewable workflow state'; end if;
  v_new_status:=case p_decision when 'approved' then 'published' else 'changes_requested' end;
  update public.ai_reports set status=v_new_status,reviewer_id=v_actor,reviewed_at=now(),review_comment=p_comments,updated_by=v_actor where id=p_report_id;
  insert into public.activity_logs(organization_id,project_id,actor_id,action,entity_type,entity_id,details,created_by)
  values(v_org,v_project,v_actor,'ai_report_reviewed','ai_report',p_report_id,
         jsonb_build_object('decision',p_decision,'status',v_new_status),v_actor);
  -- This review controls publication of advisory AI text only; it does not approve scientific results.
end;
$$;

create or replace function public.search_authorized_chunks(
  p_user_id uuid,p_project_id uuid,p_query text,p_limit integer,p_document_id uuid
)
returns table(chunk_id uuid,document_version_id uuid,document_id uuid,title text,page_no integer,section_label text,content text,rank real)
language plpgsql stable security definer
set search_path = pg_catalog, public, auth set row_security = off as $$
declare v_role text; v_limit integer; v_tsquery tsquery; v_service boolean;
begin
  v_service:=coalesce(auth.role(),'')='service_role';
  if p_user_id is null then raise exception 'requesting user required'; end if;
  if not v_service and p_user_id is distinct from auth.uid() then raise exception 'user may search only as self'; end if;
  if length(btrim(coalesce(p_query,'')))=0 then return; end if;
  v_limit:=greatest(1,least(coalesce(p_limit,25),100));
  v_tsquery:=websearch_to_tsquery('simple',p_query);
  select pm.role into v_role from public.project_members pm
    join public.projects pr on pr.id=pm.project_id
    join public.organization_members om on om.organization_id=pr.organization_id and om.user_id=pm.user_id
   where pm.project_id=p_project_id and pm.user_id=p_user_id and pm.status='active' and om.status='active';
  if v_role is null then raise exception 'active project and organization membership required'; end if;
  return query
  select c.id,c.document_version_id,d.id,d.title,c.page_no,c.section_label,c.content,ts_rank_cd(c.search_vector,v_tsquery)::real
    from public.document_chunks c
    join public.document_versions dv on dv.id=c.document_version_id and dv.project_id=c.project_id
    join public.documents d on d.id=dv.document_id and d.project_id=dv.project_id
   where c.project_id=p_project_id and (p_document_id is null or d.id=p_document_id)
     and c.search_vector @@ v_tsquery
     and ((v_role='Viewer' and d.status='approved' and d.visibility='approved')
       or (v_role<>'Viewer' and d.visibility<>'private')
       or (d.created_by=p_user_id and v_role in ('Project Lead','Secretary','Researcher'))
       or v_role in ('Project Lead','Secretary'))
   order by ts_rank_cd(c.search_vector,v_tsquery) desc,c.id
   limit v_limit;
end;
$$;

-- Explicitly remove default PUBLIC/anon execution on every workflow RPC (including replaced RPCs).
revoke all on function public.accept_pending_invitation(text) from public,anon;
revoke all on function public.create_document_with_audit(uuid,text,text,text,text) from public,anon;
revoke all on function public.register_document_version(uuid,text,text,text,text,bigint,text,text) from public,anon;
revoke all on function public.create_research_entry_with_audit(uuid,text,text,text,text,text,uuid) from public,anon;
revoke all on function public.update_task_with_audit(uuid,text,timestamptz) from public,anon;
revoke all on function public.submit_task_with_audit(uuid,text,uuid[]) from public,anon;
revoke all on function public.review_task_submission(uuid,uuid,text,text) from public,anon;
revoke all on function public.create_lab_test_with_audit(uuid,uuid,text,text,timestamptz,uuid[]) from public,anon;
revoke all on function public.add_lab_test_procedure(uuid,uuid,text) from public,anon;
revoke all on function public.submit_lab_result_with_audit(uuid,jsonb,jsonb,text,text,text,text,jsonb,uuid[]) from public,anon;
revoke all on function public.review_lab_result(uuid,text,text) from public,anon;
revoke all on function public.create_formulation_version(uuid,text,text,text,jsonb) from public,anon;
revoke all on function public.create_formulation_with_audit(uuid,text,text) from public,anon;
revoke all on function public.add_formulation_trial(uuid,uuid,text) from public,anon;
revoke all on function public.add_meeting_minutes(uuid,uuid) from public,anon;
revoke all on function public.create_meeting_decision(uuid,text,uuid,uuid) from public,anon;
revoke all on function public.set_notification_preference(text,text,boolean,uuid) from public,anon;
revoke all on function public.record_notification_consent(text,text,text,text,text) from public,anon;
revoke all on function public.update_member_role_with_audit(uuid,uuid,text,uuid) from public,anon;
revoke all on function public.update_member_status_with_audit(uuid,uuid,text) from public,anon;
revoke all on function public.review_ai_report(uuid,text,text) from public,anon;
revoke all on function public.search_authorized_chunks(uuid,uuid,text,integer,uuid) from public,anon;

grant execute on function public.accept_pending_invitation(text) to authenticated;
grant execute on function public.create_document_with_audit(uuid,text,text,text,text) to authenticated;
grant execute on function public.register_document_version(uuid,text,text,text,text,bigint,text,text) to authenticated;
grant execute on function public.create_research_entry_with_audit(uuid,text,text,text,text,text,uuid) to authenticated;
grant execute on function public.update_task_with_audit(uuid,text,timestamptz) to authenticated;
grant execute on function public.submit_task_with_audit(uuid,text,uuid[]) to authenticated;
grant execute on function public.review_task_submission(uuid,uuid,text,text) to authenticated;
grant execute on function public.create_lab_test_with_audit(uuid,uuid,text,text,timestamptz,uuid[]) to authenticated;
grant execute on function public.add_lab_test_procedure(uuid,uuid,text) to authenticated;
grant execute on function public.submit_lab_result_with_audit(uuid,jsonb,jsonb,text,text,text,text,jsonb,uuid[]) to authenticated;
grant execute on function public.review_lab_result(uuid,text,text) to authenticated;
grant execute on function public.create_formulation_version(uuid,text,text,text,jsonb) to authenticated;
grant execute on function public.create_formulation_with_audit(uuid,text,text) to authenticated;
grant execute on function public.add_formulation_trial(uuid,uuid,text) to authenticated;
grant execute on function public.add_meeting_minutes(uuid,uuid) to authenticated;
grant execute on function public.create_meeting_decision(uuid,text,uuid,uuid) to authenticated;
grant execute on function public.set_notification_preference(text,text,boolean,uuid) to authenticated;
grant execute on function public.record_notification_consent(text,text,text,text,text) to authenticated;
grant execute on function public.update_member_role_with_audit(uuid,uuid,text,uuid) to authenticated;
grant execute on function public.update_member_status_with_audit(uuid,uuid,text) to authenticated;
grant execute on function public.review_ai_report(uuid,text,text) to authenticated;
grant execute on function public.search_authorized_chunks(uuid,uuid,text,integer,uuid) to authenticated,service_role;


commit;
