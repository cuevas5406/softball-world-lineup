-- PROPUESTA PARA LAB. NO APLICADA. Requiere 01 y 05.
begin;
create function public.swl_v56_substitute_batter(
  p_game_id uuid, p_team_id uuid, p_batting_order integer,
  p_outgoing_id uuid, p_incoming_id uuid, p_expected_revision integer, p_expected_game_version bigint
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  l public.swl_game_lineups%rowtype;
  position text;
  next_version bigint;
  actor uuid := auth.uid();
begin
  select * into g from public.swl_live_games where id = p_game_id for update;
  if not found or actor is null or p_team_id is null or
      ((g.home_team_id = p_team_id and g.home_manager_id = actor)
       or (g.away_team_id = p_team_id and g.away_manager_id = actor)) is not true
      or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Solo puede sustituir el mánager de ese equipo.';
  end if;
  if g.status::text is distinct from 'IN_PROGRESS' or g.version is distinct from p_expected_game_version then
    raise exception 'El partido o su versión cambió.';
  end if;
  select * into l from public.swl_game_lineups
    where game_id = p_game_id and team_id = p_team_id for update;
  if not found then raise exception 'Alineación no disponible.'; end if;
  if l.pitcher_id = p_incoming_id then
    raise exception 'El pitcher de solo defensa no puede entrar por esta vía al orden al bate.';
  end if;
  perform public.swl_v53_substitute_batter(p_game_id => p_game_id, p_team_id => p_team_id,
    p_batting_order => p_batting_order, p_outgoing_id => p_outgoing_id, p_incoming_id => p_incoming_id,
    p_expected_revision => p_expected_revision, p_expected_game_version => p_expected_game_version);
  select version into next_version from public.swl_live_games where id = p_game_id;
  if next_version is distinct from g.version + 1 then
    raise exception 'La sustitución no generó la versión esperada.';
  end if;
  position := l.defensive_positions ->> p_outgoing_id::text;
  update public.swl_game_lineups set
    defensive_positions = (l.defensive_positions - p_outgoing_id::text)
      || case when position is null then '{}'::jsonb else jsonb_build_object(p_incoming_id::text, position) end,
    pitcher_id = case when l.pitcher_id = p_outgoing_id then p_incoming_id else l.pitcher_id end,
    designated_hitter_id = case when l.designated_hitter_id = p_outgoing_id then p_incoming_id else l.designated_hitter_id end
  where game_id = p_game_id and team_id = p_team_id;
  if l.pitcher_id = p_outgoing_id then
    insert into public.swl_v56_pitcher_changes(game_id,team_id,version,old_pitcher_id,new_pitcher_id,innings_number,actor_id)
      values (p_game_id, p_team_id, next_version, p_outgoing_id, p_incoming_id, g.inning, actor);
  end if;
end;
$$;
revoke all on function public.swl_v56_substitute_batter(uuid,uuid,integer,uuid,uuid,integer,bigint) from public, anon;
grant execute on function public.swl_v56_substitute_batter(uuid,uuid,integer,uuid,uuid,integer,bigint) to authenticated;
commit;
