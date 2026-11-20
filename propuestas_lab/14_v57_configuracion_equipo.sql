-- Propuesta V5.7 sin ejecutar. Revisar nombres y roles efectivos en LAB.
begin;
create table if not exists public.swl_v57_team_settings_data (
  team_id uuid primary key references public.teams(id),
  revision integer not null default 0,
  primary_color text check (primary_color ~ '^#[0-9A-F]{6}$'),
  secondary_color text check (secondary_color ~ '^#[0-9A-F]{6}$'),
  delegate text check (length(delegate) <= 100),
  contact text check (length(contact) <= 150)
);
alter table public.swl_v57_team_settings_data enable row level security;
revoke all on public.swl_v57_team_settings_data from public, anon, authenticated;

create or replace function public.swl_v57_team_settings(p_team_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  result jsonb;
begin
  if auth.uid() is null or p_team_id is null or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Configuración reservada al mánager autorizado.';
  end if;
  select jsonb_build_object('name',t.name,'province',t.province,'revision',coalesce(s.revision,0),
    'primary_color',s.primary_color,'secondary_color',s.secondary_color,
    'delegate',s.delegate,'contact',s.contact) into strict result
    from public.teams t left join public.swl_v57_team_settings_data s on s.team_id = t.id
    where t.id = p_team_id;
  return result;
end;
$$;

create or replace function public.swl_v57_update_team_settings(
  p_team_id uuid, p_expected_revision integer, p_data jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare
  team_name text := nullif(btrim(p_data->>'name'),'');
  locality text := coalesce(btrim(p_data->>'province'),'');
  revision_now integer;
begin
  if auth.uid() is null or p_team_id is null or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Configuración reservada al mánager autorizado.';
  end if;
  if team_name is null or length(team_name) > 100 or length(locality) > 100 then
    raise exception 'Revisa el nombre y la localidad del equipo.';
  end if;
  perform 1 from public.teams where id = p_team_id for update;
  if not found then raise exception 'Equipo no encontrado.'; end if;
  select revision into revision_now from public.swl_v57_team_settings_data where team_id = p_team_id;
  if coalesce(revision_now,0) is distinct from p_expected_revision then
    raise exception 'La configuración cambió. Vuelve a entrar antes de guardar.';
  end if;
  insert into public.swl_v57_team_settings_data(team_id,revision,primary_color,secondary_color,delegate,contact)
    values(p_team_id,p_expected_revision + 1,nullif(upper(btrim(p_data->>'primary_color')),''),
      nullif(upper(btrim(p_data->>'secondary_color')),''),nullif(btrim(p_data->>'delegate'),''),
      nullif(btrim(p_data->>'contact'),''))
    on conflict(team_id) do update set revision = excluded.revision, primary_color = excluded.primary_color,
      secondary_color = excluded.secondary_color, delegate = excluded.delegate, contact = excluded.contact;
  update public.teams set name = team_name, province = locality where id = p_team_id;
end;
$$;

revoke all on function public.swl_v57_team_settings(uuid) from public, anon;
revoke all on function public.swl_v57_update_team_settings(uuid,integer,jsonb) from public, anon;
grant execute on function public.swl_v57_team_settings(uuid) to authenticated;
grant execute on function public.swl_v57_update_team_settings(uuid,integer,jsonb) to authenticated;
commit;
