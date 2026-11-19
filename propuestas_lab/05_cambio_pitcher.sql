-- PROPUESTA PARA LAB. NO APLICADA. Requiere 01_inicio_y_alineacion.sql.
begin;
create table public.swl_v56_pitcher_changes (
  game_id uuid not null references public.swl_live_games(id),
  team_id uuid not null references public.teams(id),
  version bigint not null,
  old_pitcher_id uuid references public.players(id),
  new_pitcher_id uuid not null references public.players(id),
  innings_number integer not null,
  actor_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (game_id, version)
);
alter table public.swl_v56_pitcher_changes enable row level security;
revoke all on public.swl_v56_pitcher_changes from public, anon, authenticated;
grant select on public.swl_v56_pitcher_changes to authenticated;
create policy swl_v56_pitcher_history_read on public.swl_v56_pitcher_changes
  for select to authenticated using (
    exists (select 1 from public.swl_game_lineups l where l.game_id = swl_v56_pitcher_changes.game_id)
  );

create function public.swl_v56_change_pitcher(
  p_game_id uuid, p_expected_version bigint, p_team_id uuid, p_player_id uuid
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  l public.swl_game_lineups%rowtype;
  actor uuid := auth.uid();
begin
  select * into g from public.swl_live_games where id = p_game_id for update;
  if not found or actor is null or g.is_top is null or p_team_id is null
      or (case when g.is_top then g.home_team_id else g.away_team_id end) is distinct from p_team_id
      or (case when g.is_top then g.home_manager_id else g.away_manager_id end) is distinct from actor
      or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Cambio reservado al mánager del equipo a la defensa.';
  end if;
  if g.status::text is distinct from 'IN_PROGRESS' or g.version is distinct from p_expected_version
      or g.balls is distinct from 0 or g.strikes is distinct from 0 then
    raise exception 'Cambia el pitcher entre bateadores, con la versión actual del marcador.';
  end if;
  select * into l from public.swl_game_lineups
    where game_id = p_game_id and team_id = p_team_id for update;
  if not found or l.pitcher_id is null or l.pitcher_id = p_player_id
      or not exists (select 1 from public.rosters where team_id = p_team_id
                    and player_id = p_player_id and removed_at is null)
      or (exists (select 1 from jsonb_array_elements(l.lineup) s
                 where s ->> 'player_id' = p_player_id::text)) is distinct from l.pitcher_bats then
    raise exception 'El nuevo pitcher debe estar activo y mantener la regla de bateo del pitcher saliente.';
  end if;
  update public.swl_game_lineups
    set pitcher_id = p_player_id, revision = l.revision + 1, updated_at = now(),
        defensive_positions = (l.defensive_positions - l.pitcher_id::text)
          || jsonb_build_object(p_player_id::text, 'P')
    where game_id = p_game_id and team_id = p_team_id;
  insert into public.swl_v56_pitcher_changes
    (game_id, team_id, version, old_pitcher_id, new_pitcher_id, innings_number, actor_id)
    values (p_game_id, p_team_id, g.version + 1, l.pitcher_id, p_player_id, g.inning, actor);
  update public.swl_live_games set version = g.version + 1 where id = p_game_id;
end;
$$;
revoke all on function public.swl_v56_change_pitcher(uuid,bigint,uuid,uuid) from public, anon;
grant execute on function public.swl_v56_change_pitcher(uuid,bigint,uuid,uuid) to authenticated;
commit;
