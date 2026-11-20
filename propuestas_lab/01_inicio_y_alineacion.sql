-- PROPUESTA PARA LAB. NO APLICADA. Verificar tipos, estados y firmas instaladas.
begin;

alter table public.swl_game_lineups
  add column if not exists pitcher_id uuid references public.players(id),
  add column if not exists designated_hitter_id uuid references public.players(id),
  add column if not exists pitcher_bats boolean not null default true,
  add column if not exists defensive_positions jsonb not null default '{}'::jsonb;

create or replace function public.swl_v56_start_game(p_game_id uuid, p_expected_version bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  g public.swl_live_games%rowtype;
  actor uuid := auth.uid();
begin
  select * into g from public.swl_live_games where id = p_game_id for update;
  if not found or actor is null or g.home_manager_id is distinct from actor
      or public.swl_can_manage_roster(g.home_team_id) is not true then
    raise exception using errcode = '42501', message = 'Solo el mánager local autorizado puede iniciar.';
  end if;
  if g.status::text = 'IN_PROGRESS' then return; end if;
  if g.status::text is distinct from 'SCHEDULED' or g.version is distinct from p_expected_version then
    raise exception 'El estado o la versión cambió. Actualiza el partido.';
  end if;
  if g.away_manager_id is null or g.away_manager_id = actor or g.home_team_id is null
      or g.away_team_id is null or g.home_team_id = g.away_team_id then
    raise exception 'Confirma los dos equipos y sus mánagers.';
  end if;
  if (select count(*) from public.swl_game_lineups l
      where l.game_id = g.id and l.team_id in (g.home_team_id, g.away_team_id)
        and case when jsonb_typeof(l.lineup) = 'array'
            then jsonb_array_length(l.lineup) between 9 and 13 else false end) <> 2 then
    raise exception 'Ambos equipos deben guardar sus alineaciones.';
  end if;
  update public.swl_live_games set status = 'IN_PROGRESS', version = g.version + 1
    where id = g.id;
end;
$$;

create or replace function public.swl_v56_save_lineup(
  p_game_id uuid, p_team_id uuid, p_player_ids uuid[], p_expected_revision integer,
  p_pitcher_id uuid, p_pitcher_bats boolean, p_designated_hitter_id uuid, p_defensive_positions jsonb
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  g public.swl_live_games%rowtype;
  actor uuid := auth.uid();
begin
  select * into g from public.swl_live_games where id = p_game_id for update;
  if not found or actor is null or p_team_id is null or
      ((g.home_team_id = p_team_id and g.home_manager_id = actor)
       or (g.away_team_id = p_team_id and g.away_manager_id = actor)) is not true
      or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Alineación reservada al mánager del equipo.';
  end if;
  if g.status::text is null or g.status::text not in ('SCHEDULED', 'IN_PROGRESS') then
    raise exception 'El partido no admite cambios de alineación.';
  end if;
  if p_player_ids is null or cardinality(p_player_ids) not between 9 and 13
      or array_position(p_player_ids, null::uuid) is not null
      or (select count(distinct id) from unnest(p_player_ids) as t(id)) <> cardinality(p_player_ids) then
    raise exception 'El orden al bate requiere entre 9 y 13 peloteros distintos.';
  end if;
  if jsonb_typeof(p_defensive_positions) is distinct from 'object' then
    raise exception 'Las posiciones defensivas deben enviarse por ID de pelotero.';
  end if;
  if p_pitcher_bats is null or (p_pitcher_id is null and
      (not p_pitcher_bats or p_defensive_positions <> '{}'::jsonb)) then
    raise exception 'Asigna un pitcher titular en la posición P.';
  end if;
  if p_pitcher_id is not null then
    if not exists (select 1 from public.rosters r where r.team_id = p_team_id
                   and r.player_id = p_pitcher_id and r.removed_at is null) then
      raise exception 'El pitcher debe pertenecer al roster activo.';
    end if;
    if (p_defensive_positions ->> p_pitcher_id::text) is distinct from 'P' then
      raise exception 'El pitcher titular debe ocupar P.';
    end if;
    if ((p_pitcher_id = any(p_player_ids)) is distinct from p_pitcher_bats) then
      raise exception 'El orden al bate no coincide con la opción El pitcher batea.';
    end if;
  end if;
  if (p_pitcher_bats and p_designated_hitter_id is not null)
      or (not p_pitcher_bats and (p_designated_hitter_id is null
          or (p_designated_hitter_id = any(p_player_ids)) is not true
          or p_defensive_positions ? p_designated_hitter_id::text)) then
    raise exception 'El bateador designado debe estar en el orden y carecer de posición defensiva.';
  end if;
  if exists (
    select 1 from jsonb_each_text(p_defensive_positions) p
    where not exists (select 1 from unnest(p_player_ids) as batter(id)
                      where batter.id::text = p.key)
          and p.key is distinct from p_pitcher_id::text
  ) or exists (
    select 1 from jsonb_each_text(p_defensive_positions) p
    where p.value is null or p.value not in ('P','C','1B','2B','3B','SS','LF','CF','RF','SF')
      or (p.value = 'P' and p.key is distinct from p_pitcher_id::text)
  ) or exists (
    select 1 from jsonb_each_text(p_defensive_positions) p group by p.value having count(*) > 1
  ) then
    raise exception 'Cada posición defensiva debe ser válida y tener un solo pelotero seleccionado.';
  end if;
  perform public.swl_v53_save_lineup_checked(
    p_game_id, p_team_id, p_player_ids, p_expected_revision
  );
  update public.swl_game_lineups
    set pitcher_id = p_pitcher_id, pitcher_bats = p_pitcher_bats,
        defensive_positions = p_defensive_positions, designated_hitter_id = p_designated_hitter_id
    where game_id = p_game_id and team_id = p_team_id;
  if not found then raise exception 'La alineación no fue guardada.'; end if;
end;
$$;

revoke all on function public.swl_v56_start_game(uuid,bigint) from public, anon;
revoke all on function public.swl_v56_save_lineup(uuid,uuid,uuid[],integer,uuid,boolean,uuid,jsonb) from public, anon;
grant execute on function public.swl_v56_start_game(uuid,bigint) to authenticated;
grant execute on function public.swl_v56_save_lineup(uuid,uuid,uuid[],integer,uuid,boolean,uuid,jsonb) to authenticated;

commit;
