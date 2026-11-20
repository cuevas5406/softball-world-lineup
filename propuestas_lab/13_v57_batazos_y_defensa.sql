-- Propuesta V5.7 sin ejecutar. Requiere verificar las propuestas 05–11
-- contra LAB, en especial tipos de eventos, columnas y firmas instaladas.
begin;

create or replace function public.swl_v57_batted_ball(
  p_game_id uuid, p_expected_version bigint, p_action text,
  p_batter_id uuid, p_data jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  team uuid;
  defense uuid;
  pitcher uuid;
  batting jsonb;
  turn_index integer;
  occupied boolean[];
  resulting boolean[] := array[false,false,false];
  runners uuid[] := array[null,null,null]::uuid[];
  drives integer[] := array[(p_data->>'p_first_to')::integer,
    (p_data->>'p_second_to')::integer,(p_data->>'p_third_to')::integer];
  batter_base integer := (p_data->>'p_batter_base')::integer;
  dest integer;
  previous_dest integer;
  runs integer := 0;
  made integer := 0;
  last_out uuid;
  last_out_source integer;
  terminal boolean;
  hit_count integer;
  details jsonb;
begin
  if p_action is null or p_action not in ('HIT_WITH_OUT','ERROR')
    or batter_base is null or batter_base not between 1 and 3 then
    raise exception 'Tipo de batazo inválido.';
  end if;
  g := public.swl_v56_lock_batting_turn(p_game_id,p_expected_version);
  team := case when g.is_top then g.away_team_id else g.home_team_id end;
  defense := case when g.is_top then g.home_team_id else g.away_team_id end;
  select lineup into strict batting from public.swl_game_lineups
    where game_id = g.id and team_id = team;
  select next_order into turn_index from public.swl_game_batting_turns
    where game_id = g.id and team_id = team;
  turn_index := coalesce(turn_index,1);
  if p_batter_id is null or p_batter_id = any(g.swl_base_players) or not exists (
    select 1 from jsonb_array_elements(batting) slot
    where (slot->>'order')::integer = turn_index and slot->>'player_id' = p_batter_id::text
  ) then raise exception 'El bateador cambió.'; end if;
  occupied := public.swl_v56_base_occupancy(g.bases_state);
  perform public.swl_v56_validate_base_players(occupied,g.swl_base_players);
  previous_dest := batter_base;
  resulting[batter_base] := true;
  runners[batter_base] := p_batter_id;
  for i in 1..3 loop
    dest := drives[i];
    if occupied[i] is distinct from (dest is not null) then
      raise exception 'Indica el destino de cada corredor.';
    end if;
    if dest is null then continue; end if;
    if dest < 0 then
      if -dest <= i or -dest > 4 then raise exception 'Base del out inválida.'; end if;
      made := made + 1;
      last_out := g.swl_base_players[i];
      last_out_source := i;
    elsif dest = 0 then
      runs := runs + 1;
      previous_dest := 4;
    else
      if dest > 3 or dest < previous_dest or resulting[dest] or
        dest < i + (case when i = 1 or (occupied[1] and (i = 2 or occupied[2]))
          then 1 else 0 end) then
        raise exception 'Avance, orden o base de destino inválidos.';
      end if;
      previous_dest := dest;
      resulting[dest] := true;
      runners[dest] := g.swl_base_players[i];
    end if;
  end loop;
  if g.outs + made > 3 or (p_action = 'HIT_WITH_OUT' and made = 0) then
    raise exception 'Cantidad de outs incompatible con la jugada.';
  end if;
  terminal := g.outs + made = 3;
  if terminal then
    runs := 0;
    if made = 1 and p_data->'count_runs_on_third_out' = 'true'::jsonb
        and not (drives[last_out_source] = -(last_out_source + 1)
          and (last_out_source = 1 or (occupied[1] and (last_out_source = 2 or occupied[2])))) then
      for i in (last_out_source + 1)..3 loop
        if drives[i] = 0 then runs := runs + 1; end if;
      end loop;
    end if;
  end if;
  perform public.swl_v56_validate_base_players(resulting,runners);
  hit_count := case when p_action = 'HIT_WITH_OUT' then 1 else 0 end;
  update public.swl_live_games set version = g.version + 1, updated_at = now(),
    balls = 0, strikes = 0, outs = case when terminal then 0 else g.outs + made end,
    inning = g.inning + case when terminal and not g.is_top then 1 else 0 end,
    is_top = case when terminal then not g.is_top else g.is_top end,
    away_runs = g.away_runs + case when g.is_top then runs else 0 end,
    home_runs = g.home_runs + case when g.is_top then 0 else runs end,
    away_hits = g.away_hits + case when g.is_top then hit_count else 0 end,
    home_hits = g.home_hits + case when g.is_top then 0 else hit_count end,
    home_errors = coalesce(g.home_errors,0) + case when g.is_top then 1-hit_count else 0 end,
    away_errors = coalesce(g.away_errors,0) + case when g.is_top then 0 else 1-hit_count end,
    away_innings = case when g.is_top then public.swl_v56_add_inning_runs(g.away_innings,g.inning,runs) else g.away_innings end,
    home_innings = case when not g.is_top then public.swl_v56_add_inning_runs(g.home_innings,g.inning,runs) else g.home_innings end,
    bases_state = jsonb_build_object('first',not terminal and resulting[1],
      'second',not terminal and resulting[2],'third',not terminal and resulting[3]),
    swl_base_players = case when terminal then array[null,null,null]::uuid[] else runners end,
    swl_ghost_player = case when not terminal and g.swl_ghost_player = any(runners) then g.swl_ghost_player end
    where id = g.id;

  insert into public.swl_game_batting_turns(game_id,team_id,next_order)
    values(g.id,team,turn_index % jsonb_array_length(batting) + 1)
    on conflict (game_id,team_id) do update set next_order = excluded.next_order;

  details := p_data || jsonb_build_object('scope','hit_with_runners','batter_id',p_batter_id,'batter_base',batter_base,
    'plate_appearance_completed',true,'ab',1,'hits',hit_count,'runs',runs,'outs',made,
    'rbi',case when hit_count = 1 then runs else 0 end,
    'charged_team_id',case when hit_count = 0 then defense end,
    'last_out_player_id',case when made = 1 then last_out end);
  if hit_count = 1 then
    insert into public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
      values(g.id,auth.uid(),team,g.inning,g.is_top,'HIT',details,g.version + 1);
  else
    insert into public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
      values(g.id,auth.uid(),team,g.inning,g.is_top,'ERROR',details,g.version + 1);
  end if;
  select pitcher_id into pitcher from public.swl_game_lineups where game_id = g.id and team_id = defense;
  perform public.swl_v56_accumulate_pitching(g,pitcher,case when hit_count = 1 then 'HIT' else 'OUT' end);
  perform public.swl_v56_close_after_play(g);
end;
$$;
revoke all on function public.swl_v57_batted_ball(uuid,bigint,text,uuid,jsonb) from public,anon;
grant execute on function public.swl_v57_batted_ball(uuid,bigint,text,uuid,jsonb) to authenticated;

create or replace function public.swl_v57_swap_fielders(
  p_game_id uuid, p_expected_version bigint, p_team_id uuid, p_first uuid, p_second uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  l public.swl_game_lineups%rowtype;
  first_pos text;
  second_pos text;
begin
  select * into strict g from public.swl_live_games where id = p_game_id for update;
  if auth.uid() is null or g.is_top is null or p_team_id is null or
      p_team_id is distinct from (case when g.is_top then g.home_team_id else g.away_team_id end)
      or auth.uid() is distinct from (case when g.is_top then g.home_manager_id else g.away_manager_id end)
      or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Solo puede hacer cambios el mánager a la defensa.';
  end if;
  if g.status::text is distinct from 'IN_PROGRESS' or g.version is distinct from p_expected_version
      or g.balls is distinct from 0 or g.strikes is distinct from 0 then
    raise exception 'Actualiza el partido y haz el cambio entre bateadores.';
  end if;
  select * into strict l from public.swl_game_lineups where game_id = g.id and team_id = p_team_id for update;
  first_pos := l.defensive_positions->>p_first::text;
  second_pos := l.defensive_positions->>p_second::text;
  if first_pos is null or second_pos is null or first_pos = second_pos
      or first_pos = 'P' or second_pos = 'P' or p_first = p_second
      or (select count(distinct player_id) from public.rosters
        where team_id = p_team_id and removed_at is null and player_id in (p_first,p_second)) <> 2 then
    raise exception 'Elige dos defensores activos distintos. Para P, usa Cambiar pitcher.';
  end if;
  update public.swl_game_lineups set defensive_positions = l.defensive_positions ||
    jsonb_build_object(p_first::text,second_pos,p_second::text,first_pos),
    revision = l.revision + 1, updated_at = now()
    where game_id = g.id and team_id = p_team_id;
  update public.swl_live_games set version = g.version + 1, updated_at = now() where id = g.id;
end;
$$;
revoke all on function public.swl_v57_swap_fielders(uuid,bigint,uuid,uuid,uuid) from public,anon;
grant execute on function public.swl_v57_swap_fielders(uuid,bigint,uuid,uuid,uuid) to authenticated;

create or replace function public.swl_v56_change_pitcher(
  p_game_id uuid, p_expected_version bigint, p_team_id uuid, p_player_id uuid
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  l public.swl_game_lineups%rowtype;
  actor uuid := auth.uid();
  previous_position text;
  current_pitcher_position text;
  candidate_in_order boolean;
  current_pitcher_in_order boolean;
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
                    and player_id = p_player_id and removed_at is null) then
    raise exception 'El nuevo pitcher debe pertenecer al roster activo y ser distinto del actual.';
  end if;
  previous_position := l.defensive_positions ->> p_player_id::text;
  current_pitcher_position := l.defensive_positions ->> l.pitcher_id::text;
  if current_pitcher_position is distinct from 'P' then
    raise exception 'La defensa actual no identifica al pitcher en P.';
  end if;
  select exists(select 1 from jsonb_array_elements(l.lineup) s
                where s ->> 'player_id' = p_player_id::text) into candidate_in_order;
  select exists(select 1 from jsonb_array_elements(l.lineup) s
                where s ->> 'player_id' = l.pitcher_id::text) into current_pitcher_in_order;
  if current_pitcher_in_order is distinct from l.pitcher_bats
      or candidate_in_order is distinct from l.pitcher_bats
      or (l.pitcher_bats and previous_position is null)
      or (not l.pitcher_bats and previous_position is not null)
      or previous_position = 'P'
      or p_player_id = l.designated_hitter_id then
    raise exception 'El cambio de pitcher debe preservar el orden de bateo y el DH.';
  end if;
  update public.swl_game_lineups
    set pitcher_id = p_player_id, revision = l.revision + 1, updated_at = now(),
        defensive_positions = (l.defensive_positions - l.pitcher_id::text)
          || jsonb_build_object(p_player_id::text, 'P')
          || case when previous_position is not null
               then jsonb_build_object(l.pitcher_id::text, previous_position)
               else '{}'::jsonb end
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
