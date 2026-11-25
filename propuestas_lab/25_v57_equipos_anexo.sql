-- PROPUESTA LAB SIN EJECUTAR. Requiere 03_logos.sql y 14_v57_configuracion_equipo.sql.
-- Operaciones de Storage: los archivos reemplazados quedan para limpieza administrativa.
begin;
create sequence if not exists public.swl_v57_team_code_seq start 100000;
alter table public.teams add column if not exists team_code text;
alter table public.teams alter column team_code set default
  ('SWL-' || nextval('public.swl_v57_team_code_seq'::regclass)::text);
update public.teams set team_code = default where team_code is null;
alter table public.teams alter column team_code set not null;
create unique index if not exists swl_v57_team_code_unique on public.teams(team_code);

create or replace function public.swl_v57_set_team_logo(
  p_team_id uuid, p_path text, p_expected_url text, p_public_url text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  base constant text := 'https://wgeziptdoabyicufnrfk.supabase.co/storage/v1/object/public/swl-team-logos/';
  prior public.teams%rowtype;
  next_url text;
begin
  if auth.uid() is null or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Solo el mánager autorizado puede administrar el logo.';
  end if;
  select * into strict prior from public.teams where id = p_team_id for update;
  if coalesce(base || prior.logo_path, prior.logo_url) is distinct from p_expected_url then
    raise exception 'El logo cambió en otro dispositivo. Vuelve a abrir la configuración.';
  end if;
  if p_path is not null then
    next_url := base || p_path;
    if p_public_url is distinct from next_url
        or split_part(p_path, '/', 1) is distinct from p_team_id::text
        or public.swl_v56_can_upload_logo(p_path) is not true
        or not exists (select 1 from storage.objects where bucket_id = 'swl-team-logos' and name = p_path) then
      raise exception 'No se encontró una imagen válida en el almacenamiento autorizado.';
    end if;
  end if;
  update public.teams set logo_path = p_path, logo_url = next_url where id = p_team_id;
  return next_url;
end;
$$;
revoke all on function public.swl_v57_set_team_logo(uuid,text,text,text) from public, anon;
grant execute on function public.swl_v57_set_team_logo(uuid,text,text,text) to authenticated;

create or replace function public.swl_v57_search_teams(p_term text, p_exclude uuid default null)
returns table(id uuid, name text, province text, team_code text, logo_path text, logo_url text)
language sql stable security invoker set search_path = '' as $$
  with input as (
    select lower(btrim(left(p_term, 100))) as term,
      regexp_replace(upper(btrim(left(p_term, 100))), '^SWL[ -]*', '') as digits
  )
  select t.id, t.name::text, t.province::text, t.team_code, t.logo_path, t.logo_url
  from public.teams t cross join input i
  where length(i.term) >= 2 and t.id is distinct from p_exclude
    and (t.team_code = 'SWL-' || i.digits
      or strpos(lower(t.name), i.term) > 0
      or strpos(lower(coalesce(t.province, '')), i.term) > 0
      or (length(i.term) >= 4 and left(lower(t.name), 3) = left(i.term, 3)))
  order by (t.team_code = 'SWL-' || i.digits) desc,
    (lower(t.name) = i.term) desc, (strpos(lower(t.name), i.term) > 0) desc, t.name, t.id
  limit 20;
$$;
revoke all on function public.swl_v57_search_teams(text,uuid) from public;
grant execute on function public.swl_v57_search_teams(text,uuid) to anon, authenticated;
commit;
