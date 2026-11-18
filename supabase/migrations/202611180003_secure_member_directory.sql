-- Secure member directory: email is exposed only through a membership-scoped RPC.
-- Additive, source-only migration. Apply through a reviewed external Supabase process.
begin;

create or replace function public.get_organization_directory(p_organization_id uuid)
returns table(
  user_id uuid,
  display_name text,
  email citext,
  role text,
  status text,
  joined_at timestamptz
)
language plpgsql stable security definer
set search_path = pg_catalog, public, auth
set row_security = off
as $$
begin
  if auth.uid() is null then raise exception 'authenticated user required'; end if;
  if not public.has_org_role(p_organization_id, null) then
    raise exception 'active organization membership required';
  end if;
  return query
    select m.user_id, p.display_name, p.email, m.role, m.status, m.joined_at
      from public.organization_members m
      join public.profiles p on p.id = m.user_id
     where m.organization_id = p_organization_id
     order by m.joined_at nulls last, p.display_name;
end;
$$;

revoke all on function public.get_organization_directory(uuid) from public, anon;
grant execute on function public.get_organization_directory(uuid) to authenticated;

commit;
