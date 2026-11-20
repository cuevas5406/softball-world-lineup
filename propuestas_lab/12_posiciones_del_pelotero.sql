-- PROPUESTA SIN EJECUTAR. Firma y retorno de swl_register_player verificados en LAB:
-- (text,text,text,text,text) -> TABLE(player_id uuid, universal_id text).
-- La función original permite EP como posición principal por defecto; esta
-- propuesta la conserva para no bloquear jugadores existentes o nuevos.
-- El fichaje sigue siendo una segunda operación desde Flutter (swl_sign_player).
begin;

alter table public.players add column if not exists secondary_position text;

create or replace function public.swl_v56_set_position_values(
  p_player_id uuid, p_primary_position text, p_secondary_position text
) returns void
language plpgsql security invoker set search_path = ''
as $$
declare
  primary_pos text := upper(btrim(coalesce(p_primary_position,'')));
  secondary_pos text := nullif(upper(btrim(p_secondary_position)), '');
begin
  if primary_pos not in ('P','C','1B','2B','3B','SS','LF','CF','RF','SF','EP') then
    raise exception 'La posición principal debe ser válida.';
  end if;
  if secondary_pos is not null and (primary_pos = secondary_pos
      or secondary_pos not in ('P','C','1B','2B','3B','SS','LF','CF','RF','SF')) then
    raise exception 'La posición secundaria debe ser válida y distinta de la principal.';
  end if;
  update public.players set primary_position = primary_pos, secondary_position = secondary_pos
    where id = p_player_id;
  if not found then raise exception 'Pelotero no encontrado.'; end if;
end;
$$;

create or replace function public.swl_v56_register_player_positions(
  p_team_id uuid, p_first_name text, p_last_name text, p_jersey_number text,
  p_primary_position text, p_secondary_position text, p_photo_url text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  registration jsonb;
  player_id uuid;
begin
  if auth.uid() is null or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Registro reservado al mánager autorizado.';
  end if;
  -- Reutiliza el registro actual y su generador SWL; firma verificada en LAB.
  select to_jsonb(r) into strict registration
    from public.swl_register_player(
      p_first_name => p_first_name, p_last_name => p_last_name,
      p_jersey_number => p_jersey_number, p_primary_position => p_primary_position,
      p_photo_url => p_photo_url
    ) as r;
  if coalesce(registration->>'v_player_id', registration->>'player_id', registration->>'id') is null then
    raise exception 'El registro no devolvió el identificador del pelotero; verificar contrato de LAB.';
  end if;
  player_id := coalesce(registration->>'v_player_id', registration->>'player_id', registration->>'id')::uuid;
  perform public.swl_v56_set_position_values(player_id, p_primary_position, p_secondary_position);
  return registration;
end;
$$;

create or replace function public.swl_v56_edit_player_positions(
  p_team_id uuid, p_player_id uuid, p_primary_position text, p_secondary_position text
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Edición reservada al mánager autorizado.';
  end if;
  perform 1 from public.rosters
    where team_id = p_team_id and player_id = p_player_id and removed_at is null
      and is_refuerzo is false for update;
  if not found or exists (
    select 1 from public.rosters where player_id = p_player_id and removed_at is null
      and is_refuerzo is false and team_id is distinct from p_team_id
  ) then
    raise exception using errcode = '42501',
      message = 'El pelotero debe tener un fichaje regular activo y exclusivo en tu equipo.';
  end if;
  perform public.swl_v56_set_position_values(p_player_id, p_primary_position, p_secondary_position);
end;
$$;

revoke all on function public.swl_v56_set_position_values(uuid,text,text) from public, anon, authenticated;
revoke all on function public.swl_v56_register_player_positions(uuid,text,text,text,text,text,text) from public, anon;
revoke all on function public.swl_v56_edit_player_positions(uuid,uuid,text,text) from public, anon;
grant execute on function public.swl_v56_register_player_positions(uuid,text,text,text,text,text,text) to authenticated;
grant execute on function public.swl_v56_edit_player_positions(uuid,uuid,text,text) to authenticated;

commit;
