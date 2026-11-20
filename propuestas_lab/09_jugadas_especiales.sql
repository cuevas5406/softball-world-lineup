-- PROPUESTA SIN EJECUTAR. Requiere 06, 07 y 08. Verificar restricciones de
-- event_type, estructura de bases_state y cursor antes de aplicar.
begin;
alter table public.swl_live_games
  add column swl_base_players uuid[] not null default array[null,null,null]::uuid[],
  add column swl_ghost_player uuid,
  add column swl_allow_roster_ghost boolean not null default false;

create function public.swl_v56_add_inning_runs(p_totals jsonb,p_inning integer,p_runs integer)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  totals jsonb := coalesce(p_totals,'[]'::jsonb);
  index integer := p_inning-1;
begin
  if p_inning < 1 or jsonb_typeof(totals) <> 'array' then raise exception 'Entrada inválida'; end if;
  while jsonb_array_length(totals) < p_inning loop totals := totals || '0'::jsonb; end loop;
  return jsonb_set(totals,array[index::text],to_jsonb(coalesce((totals ->> index)::integer,0)+p_runs));
end;
$$;
revoke all on function public.swl_v56_add_inning_runs(jsonb,integer,integer) from public, anon, authenticated;

-- Admite una base ocupada con identidad desconocida al migrar un partido.
-- Una identidad conocida siempre corresponde a una única base ocupada.
create function public.swl_v56_base_occupancy(state jsonb)
returns boolean[] language plpgsql immutable set search_path = '' as $$
begin
  if jsonb_typeof(state) is distinct from 'object' or exists (
      select 1 from jsonb_each(state) e where e.key in ('first','second','third')
        and jsonb_typeof(e.value) <> 'boolean') then
    raise exception 'Formato de ocupación no compatible.';
  end if;
  return array[coalesce(state -> 'first' = 'true'::jsonb,false),
    coalesce(state -> 'second' = 'true'::jsonb,false),
    coalesce(state -> 'third' = 'true'::jsonb,false)];
end;
$$;

create function public.swl_v56_validate_base_players(occupied boolean[], players uuid[])
returns void language plpgsql immutable set search_path = '' as $$
begin
  if array_length(players,1) is distinct from 3 or array_lower(players,1) is distinct from 1
      or array_ndims(players) is distinct from 1 then
    raise exception 'Mapa de identidades de bases inválido.';
  end if;
  for i in 1..3 loop
    if players[i] is not null and occupied[i] is not true then
      raise exception 'Una identidad conocida exige una base ocupada.';
    end if;
  end loop;
  if exists (select 1 from unnest(players) id where id is not null group by id having count(*) > 1) then
    raise exception 'Un corredor no puede ocupar dos bases.';
  end if;
end;
$$;
revoke all on function public.swl_v56_base_occupancy(jsonb),
  public.swl_v56_validate_base_players(boolean[],uuid[]) from public, anon, authenticated;

-- Mantiene identidades durante el flujo de batazos y boletos ya validado.
create function public.swl_v56_track_base_players(prior public.swl_live_games,
  action text, batter uuid, batter_base integer, first_to integer, second_to integer, third_to integer)
returns void language plpgsql set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  players uuid[] := prior.swl_base_players;
  new_players uuid[] := array[null,null,null]::uuid[];
  moves integer[];
  occupied boolean[];
  resulting boolean[];
  previous_dest integer;
  target integer;
begin
  select * into strict g from public.swl_live_games where id = prior.id;
  if g.version is distinct from prior.version + 1 then raise exception 'Versión inválida'; end if;
  occupied := public.swl_v56_base_occupancy(prior.bases_state);
  perform public.swl_v56_validate_base_players(occupied,players);
  resulting := occupied;
  if g.is_top is distinct from prior.is_top or g.inning is distinct from prior.inning then
    players := new_players;
    resulting := array[false,false,false];
  elsif action = 'HIT' then
    if batter is null or batter = any(players) or batter_base is null or batter_base not between 1 and 4 then
      raise exception 'Bateador o destino inválido.';
    end if;
    resulting := array[false,false,false];
    moves := array[first_to,second_to,third_to];
    previous_dest := batter_base;
    for i in 1..3 loop
      if occupied[i] is distinct from (moves[i] is not null)
          or moves[i] < 0 or moves[i] > 3 then
        raise exception 'Avance incompatible con las bases ocupadas.';
      end if;
      if occupied[i] then
        target := case when moves[i] = 0 then 4 else moves[i] end;
        if target < previous_dest or (moves[i] > 0 and moves[i] < i) then
          raise exception 'Un avance no puede rebasar a otro corredor ni retroceder.';
        end if;
        previous_dest := target;
      end if;
      if moves[i] between 1 and 3 then
        if resulting[moves[i]] then raise exception 'Dos corredores en una base.'; end if;
        resulting[moves[i]] := true;
        new_players[moves[i]] := players[i];
      end if;
    end loop;
    if batter_base between 1 and 3 then
      if resulting[batter_base] then raise exception 'La base del bateador está ocupada.'; end if;
      resulting[batter_base] := true;
      new_players[batter_base] := batter;
    end if;
    players := new_players;
  elsif action = 'BALL' and prior.balls = 3 then
    if batter is null or batter = any(players) then raise exception 'Bateador inválido para el boleto.'; end if;
    if occupied[1] then
      if occupied[2] then players[3] := players[2]; resulting[3] := true; end if;
      players[2] := players[1];
      resulting[2] := true;
    end if;
    players[1] := batter;
    resulting[1] := true;
  end if;
  if resulting is distinct from public.swl_v56_base_occupancy(g.bases_state) then
    raise exception 'El avance legado no coincide con la ocupación esperada.';
  end if;
  perform public.swl_v56_validate_base_players(resulting,players);
  update public.swl_live_games set swl_base_players = players,
    swl_ghost_player = case when prior.swl_ghost_player = any(players) then prior.swl_ghost_player end
    where id = prior.id;
end;
$$;
revoke all on function public.swl_v56_track_base_players(public.swl_live_games,text,uuid,integer,integer,integer,integer)
  from public, anon, authenticated;

create function public.swl_v56_special_play(
  p_game_id uuid, p_expected_version bigint, p_action text, p_batter_id uuid, p_data jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  team uuid;
  pitcher uuid;
  runner uuid;
  ghost uuid;
  players uuid[];
  moved uuid[] := array[null,null,null]::uuid[];
  keys text[] := array['first','second','third'];
  occupied boolean[];
  resulting boolean[];
  source int := (p_data ->> 'source')::integer;
  dest int := (p_data ->> 'destination')::integer;
  destinations int[] := array[(p_data ->> 'first_to')::integer,
    (p_data ->> 'second_to')::integer,(p_data ->> 'third_to')::integer];
  runs int := 0;
  made int := 0;
  previous_dest int := 0;
  next_dest int;
  terminal boolean;
  plate boolean;
  batting_order jsonb;
  turn_order integer;
  lineup_revision integer;
  details jsonb;
begin
  g := public.swl_v56_lock_batting_turn(p_game_id, p_expected_version);
  team := case when g.is_top then g.away_team_id else g.home_team_id end;
  if p_action is null or p_action not in ('RUNNER_MOVE','RUNNER_OUT','RUNNER_REPLACE','GHOST_RUNNER','DOUBLE_PLAY','SACRIFICE_FLY') then
    raise exception 'Jugada especial inválida.';
  end if;
  if exists (select 1 from jsonb_each(g.bases_state) e
      where not (e.key = any(keys)) or jsonb_typeof(e.value) <> 'boolean') then
    raise exception 'El formato de bases instalado requiere revisar el adaptador.';
  end if;
  occupied := array[coalesce(g.bases_state -> 'first' = 'true'::jsonb,false),
    coalesce(g.bases_state -> 'second' = 'true'::jsonb,false),
    coalesce(g.bases_state -> 'third' = 'true'::jsonb,false)];
  resulting := occupied;
  players := g.swl_base_players;
  perform public.swl_v56_validate_base_players(occupied,players);
  ghost := g.swl_ghost_player;
  plate := p_action in ('SACRIFICE_FLY','DOUBLE_PLAY');
  if plate then
    if p_batter_id = any(players) then
      raise exception 'El bateador ya figura como corredor.';
    end if;
    select lineup into strict batting_order from public.swl_game_lineups
      where game_id = g.id and team_id = team;
    select next_order into turn_order from public.swl_game_batting_turns
      where game_id = g.id and team_id = team;
    turn_order := coalesce(turn_order,1);
    if p_batter_id is null or not exists (select 1 from jsonb_array_elements(batting_order) slot
        where (slot ->> 'order')::integer = turn_order and slot ->> 'player_id' = p_batter_id::text) then
      raise exception 'El bateador cambió.';
    end if;
  end if;
  if p_action = 'RUNNER_REPLACE' then
    if source is null or source not between 1 and 3 or not occupied[source] or players[source] is null then
      raise exception 'Falta la identidad confirmada del corredor.';
    end if;
    runner := (p_data ->> 'player_id')::uuid;
    if runner is null or runner = any(players) then raise exception 'Corredor repetido o inválido.'; end if;
    select lineup, revision into strict batting_order, lineup_revision from public.swl_game_lineups
      where game_id = g.id and team_id = team;
    select (slot ->> 'order')::integer into turn_order from jsonb_array_elements(batting_order) slot
      where slot ->> 'player_id' = players[source]::text;
    if turn_order is null then raise exception 'El corredor no pertenece al turno activo.'; end if;
    perform public.swl_v56_substitute_batter(g.id,team,turn_order,players[source],runner,lineup_revision,g.version);
    return;
  end if;
  if p_action in ('RUNNER_MOVE','RUNNER_OUT','DOUBLE_PLAY') then
    if source is null or source not between 1 and 3 or not occupied[source] then
      raise exception 'No hay corredor en la base de origen.';
    end if;
    runner := players[source];
    if p_action = 'RUNNER_MOVE' then
      if dest is null or dest not between 0 and 3 or source = dest then raise exception 'Destino inválido.'; end if;
      next_dest := case when dest = 0 then 4 else dest end;
      for i in least(source,next_dest)..least(3,greatest(source,next_dest)) loop
        if i <> source and occupied[i] then raise exception 'Hay un corredor en el trayecto.'; end if;
      end loop;
      if dest = 0 then runs := 1;
      else resulting[dest] := true; players[dest] := runner; end if;
    else
      made := case when p_action = 'DOUBLE_PLAY' then 2 else 1 end;
    end if;
    resulting[source] := false;
    players[source] := null;
  elsif p_action = 'SACRIFICE_FLY' then
    if g.outs >= 2 or not occupied[3] or destinations[3] is distinct from 0 then
      raise exception 'El sacrificio requiere carrera desde tercera y menos de dos outs.';
    end if;
    resulting := array[false,false,false];
    for i in 1..3 loop
      dest := destinations[i];
      if occupied[i] is distinct from (dest is not null) or dest < 0 or dest > 3 or (dest <> 0 and dest < i) then
        raise exception 'Avance inválido.';
      end if;
      if occupied[i] then
        next_dest := case when dest = 0 then 4 else dest end;
        if next_dest < previous_dest then raise exception 'Un corredor no puede rebasar a otro.'; end if;
        previous_dest := next_dest;
        if dest = 0 then runs := runs+1;
        elsif resulting[dest] then raise exception 'Dos corredores en una base.';
        else resulting[dest] := true; moved[dest] := players[i]; end if;
      end if;
    end loop;
    players := moved;
    made := 1;
  else
    if g.inning < 6 or occupied[2] then raise exception 'Segunda debe estar libre, desde la sexta.'; end if;
    if exists (select 1 from public.swl_game_events where game_id = g.id and inning = g.inning
      and is_top = g.is_top and event_type::text = 'GHOST_RUNNER') then
      raise exception 'Ya se colocó un corredor fantasma en esta media entrada.';
    end if;
    if p_data ->> 'player_id' = 'LAST_OUT' then
      select coalesce(event_data ->> 'last_out_player_id',event_data ->> 'batter_id')::uuid into runner
        from public.swl_game_events where game_id = g.id and batting_team_id = team and
        (event_type::text in ('OUT','RUNNER_OUT','SACRIFICE_FLY','DOUBLE_PLAY')
          or (event_type::text = 'STRIKE' and event_data -> 'plate_appearance_completed' = 'true'::jsonb))
        order by version desc nulls last, id desc limit 1;
    else
      runner := (p_data ->> 'player_id')::uuid;
    end if;
    if not g.swl_allow_roster_ghost and not exists (
        select 1 from public.swl_game_lineups l, jsonb_array_elements(l.lineup) slot
        where l.game_id = g.id and l.team_id = team and slot ->> 'player_id' = runner::text) then
      raise exception 'Este torneo requiere un jugador del lineup activo.';
    end if;
    if runner is null or runner = any(players) or
        (occupied[1] and players[1] is null) or (occupied[3] and players[3] is null)
        or not exists (select 1 from public.rosters r where r.team_id = team
          and r.player_id = runner and r.removed_at is null) then
      raise exception 'Identidad del corredor no elegible o no confirmada.';
    end if;
    resulting[2] := true;
    players[2] := runner;
    ghost := runner;
  end if;
  if g.outs+made > 3 then raise exception 'La jugada supera los tres outs.'; end if;
  terminal := g.outs+made = 3;
  perform public.swl_v56_validate_base_players(resulting,players);
  update public.swl_live_games set version = g.version+1, updated_at = now(),
    outs = case when terminal then 0 else g.outs+made end,
    inning = g.inning + case when terminal and not g.is_top then 1 else 0 end,
    is_top = case when terminal then not g.is_top else g.is_top end,
    balls = case when plate or terminal then 0 else g.balls end,
    strikes = case when plate or terminal then 0 else g.strikes end,
    away_runs = g.away_runs + case when g.is_top then runs else 0 end,
    home_runs = g.home_runs + case when g.is_top then 0 else runs end,
    away_innings = case when g.is_top then public.swl_v56_add_inning_runs(g.away_innings,g.inning,runs) else g.away_innings end,
    home_innings = case when not g.is_top then public.swl_v56_add_inning_runs(g.home_innings,g.inning,runs) else g.home_innings end,
    bases_state = jsonb_build_object('first',not terminal and resulting[1],
      'second',not terminal and resulting[2],'third',not terminal and resulting[3]),
    swl_base_players = case when terminal then array[null,null,null]::uuid[] else players end,
    swl_ghost_player = case when not terminal and ghost = any(players) then ghost end
    where id = g.id;
  if plate then
    insert into public.swl_game_batting_turns(game_id,team_id,next_order)
      values(g.id,team,turn_order % jsonb_array_length(batting_order)+1)
      on conflict (game_id,team_id) do update set next_order = excluded.next_order;
  end if;
  details := p_data || jsonb_build_object('plate_appearance_completed',plate,'batter_id',p_batter_id,
    'runner_id',runner, 'runs',runs, 'outs',made,'sf',case when p_action = 'SACRIFICE_FLY' then 1 else 0 end,
    'ab',case when p_action = 'DOUBLE_PLAY' then 1 else 0 end,
    'rbi',case when p_action = 'SACRIFICE_FLY' then runs else 0 end,
    'last_out_player_id', case when p_action in ('RUNNER_OUT','DOUBLE_PLAY') then runner
      when p_action = 'SACRIFICE_FLY' then p_batter_id end);
  insert into public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
    values(g.id,auth.uid(),team,g.inning,g.is_top,p_action,details,g.version+1);
  select pitcher_id into pitcher from public.swl_game_lineups where game_id = g.id
    and team_id = (case when g.is_top then g.home_team_id else g.away_team_id end);
  perform public.swl_v56_accumulate_pitching(g,pitcher,p_action);
  perform public.swl_v56_close_after_play(g);
end;
$$;
revoke all on function public.swl_v56_special_play(uuid,bigint,text,uuid,jsonb) from public, anon;
grant execute on function public.swl_v56_special_play(uuid,bigint,text,uuid,jsonb) to authenticated;
create or replace function public.swl_v56_record_plate_action(
  p_game_id uuid, p_expected_version bigint, p_action text, p_batter_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  pitcher uuid;
begin
  g := public.swl_v56_lock_batting_turn(p_game_id, p_expected_version);
  if p_action is null or p_action not in ('BALL','STRIKE','OUT') then raise exception 'Jugada inválida.'; end if;
  select pitcher_id into pitcher from public.swl_game_lineups where game_id = p_game_id
    and team_id = (case when g.is_top then g.home_team_id else g.away_team_id end);
  perform public.swl_v53_record_plate_action(p_game_id => p_game_id, p_expected_version => p_expected_version,
      p_action => p_action, p_batter_id => p_batter_id);
  perform public.swl_v56_track_base_players(g,p_action,p_batter_id,null,null,null,null);
  perform public.swl_v56_accumulate_pitching(g, pitcher, p_action);
  perform public.swl_v56_close_after_play(g);
end;
$$;

create or replace function public.swl_v56_apply_hit(
  p_game_id uuid, p_expected_version bigint, p_batter_id uuid, p_batter_base integer,
  p_first_to integer, p_second_to integer, p_third_to integer
) returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  pitcher uuid;
begin
  g := public.swl_v56_lock_batting_turn(p_game_id, p_expected_version);
  select pitcher_id into pitcher from public.swl_game_lineups where game_id = p_game_id
    and team_id = (case when g.is_top then g.home_team_id else g.away_team_id end);
  perform public.swl_v53_apply_hit_for_player(p_game_id => p_game_id, p_expected_version => p_expected_version,
    p_batter_id => p_batter_id, p_batter_base => p_batter_base,
    p_first_to => p_first_to, p_second_to => p_second_to, p_third_to => p_third_to);
  perform public.swl_v56_track_base_players(g,'HIT',p_batter_id,p_batter_base,p_first_to,p_second_to,p_third_to);
  perform public.swl_v56_accumulate_pitching(g, pitcher, 'HIT');
  perform public.swl_v56_close_after_play(g);
end;
$$;

create or replace function public.swl_v56_substitute_batter(
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
  perform public.swl_v56_validate_base_players(public.swl_v56_base_occupancy(g.bases_state),g.swl_base_players);
  if exists (select 1 from public.swl_live_games latest where latest.id = g.id
      and (latest.bases_state is distinct from g.bases_state or latest.inning is distinct from g.inning
           or latest.is_top is distinct from g.is_top)) then
    raise exception 'La sustitución no puede cambiar bases ni media entrada.';
  end if;
  position := l.defensive_positions ->> p_outgoing_id::text;
  update public.swl_game_lineups set
    defensive_positions = (l.defensive_positions - p_outgoing_id::text)
      || case when position is null then '{}'::jsonb else jsonb_build_object(p_incoming_id::text, position) end,
    pitcher_id = case when l.pitcher_id = p_outgoing_id then p_incoming_id else l.pitcher_id end,
    designated_hitter_id = case when l.designated_hitter_id = p_outgoing_id then p_incoming_id else l.designated_hitter_id end
  where game_id = p_game_id and team_id = p_team_id;
  if p_incoming_id = any(g.swl_base_players) then
    raise exception 'El sustituto ya figura en una base.';
  end if;
  if p_outgoing_id = any(g.swl_base_players) then
    update public.swl_live_games set
      swl_base_players = array_replace(g.swl_base_players,p_outgoing_id,p_incoming_id),
      swl_ghost_player = case when g.swl_ghost_player = p_outgoing_id
        then p_incoming_id else g.swl_ghost_player end
      where id = g.id;
  end if;
  if l.pitcher_id = p_outgoing_id then
    insert into public.swl_v56_pitcher_changes(game_id,team_id,version,old_pitcher_id,new_pitcher_id,innings_number,actor_id)
      values (p_game_id, p_team_id, next_version, p_outgoing_id, p_incoming_id, g.inning, actor);
  end if;
end;
$$;
commit;
