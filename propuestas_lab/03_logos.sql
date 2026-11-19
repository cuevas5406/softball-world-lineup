-- PROPUESTA PARA LAB. NO APLICADA. Auditar las políticas de storage existentes.
begin;
alter table public.teams add column if not exists logo_path text;
alter table public.teams add column if not exists logo_url text;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('swl-team-logos', 'swl-team-logos', true, 2097152,
        array['image/png','image/jpeg','image/webp']);

create function public.swl_v56_can_upload_logo(p_path text)
returns boolean
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is not null and p_path ~*
      '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/[0-9]+-[0-9a-f]+\.(png|jpeg|webp)$'
    then public.swl_can_manage_roster(split_part(p_path, '/', 1)::uuid) is true
    else false end;
$$;
revoke all on function public.swl_v56_can_upload_logo(text) from public, anon;
grant execute on function public.swl_v56_can_upload_logo(text) to authenticated;

create policy swl_v56_upload_team_logo on storage.objects for insert to authenticated
  with check (bucket_id = 'swl-team-logos' and public.swl_v56_can_upload_logo(name));

create function public.swl_v56_team_logo_bucket(p_team_id uuid)
returns text
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is not null and public.swl_can_manage_roster(p_team_id) is true
      and exists (select 1 from storage.buckets where id = 'swl-team-logos')
    then 'swl-team-logos' else null end;
$$;

create function public.swl_v56_set_team_logo(p_team_id uuid, p_path text)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or public.swl_v56_can_upload_logo(p_path) is not true
      or split_part(p_path, '/', 1) is distinct from p_team_id::text
      or not exists (select 1 from storage.objects
        where bucket_id = 'swl-team-logos' and name = p_path) then
    raise exception using errcode = '42501', message = 'El logo no pertenece a un equipo autorizado.';
  end if;
  update public.teams set logo_path = p_path where id = p_team_id;
end;
$$;
revoke all on function public.swl_v56_team_logo_bucket(uuid),
  public.swl_v56_set_team_logo(uuid,text) from public, anon;
grant execute on function public.swl_v56_team_logo_bucket(uuid),
  public.swl_v56_set_team_logo(uuid,text) to authenticated;
commit;
