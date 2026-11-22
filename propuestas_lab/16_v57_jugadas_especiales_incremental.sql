-- Migración incremental: únicamente RPC de jugadas especiales. No ejecutar sobre producción.
-- Requiere funciones auxiliares ya instaladas en LAB y swl_v53_substitute_batter.
BEGIN;
create or replace function public.swl_v56_special_play(
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
  lineup_revision bigint;
  details jsonb;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception 'Los datos de la jugada deben ser un objeto JSON.';
  end if;
  -- Evitar operaciones con bateador ausente o avances ambiguos.
  if p_action in ('DOUBLE_PLAY','SACRIFICE_FLY') and p_batter_id is null then
    raise exception 'La jugada requiere un bateador identificado.';
  end if;
  if p_action in ('RUNNER_MOVE','RUNNER_OUT','DOUBLE_PLAY','RUNNER_REPLACE')
      and (p_data ->> 'source') is null then
    raise exception 'La jugada requiere base de origen.';
  end if;
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
    perform public.swl_v53_substitute_batter(g.id,team,turn_order,players[source],runner,lineup_revision,g.version);
    update public.swl_live_games set swl_base_players = array_replace(swl_base_players, players[source], runner),
      swl_ghost_player = case when swl_ghost_player = players[source] then runner else swl_ghost_player end
      where id = g.id;
    return;
  end if;
  if p_action in ('RUNNER_MOVE','RUNNER_OUT','DOUBLE_PLAY') then
    if source is null or source not between 1 and 3 or not occupied[source] then
      raise exception 'No hay corredor en la base de origen.';
    end if;
    runner := players[source];
    if p_action = 'RUNNER_MOVE' then
      if dest is null or dest not between 0 and 3 or source = dest or (dest <> 0 and dest < source) then raise exception 'Destino inválido: no se permite retroceder de base.'; end if;
      next_dest := case when dest = 0 then 4 else dest end;
      for i in least(source,next_dest)..least(3,greatest(source,next_dest)) loop
        if i <> source and occupied[i] then raise exception 'Hay un corredor en el trayecto.'; end if;
      end loop;
      if dest = 0 then
        runs := 1;
      else
        if resulting[dest] then
          raise exception 'La base de destino ya está ocupada.';
        end if;
        resulting[dest] := true;
        players[dest] := runner;
      end if;
    else
      -- RUNNER_OUT: destination=0 identifica out en home, nunca carrera.
      -- Para otros outs, destination identifica la base donde ocurrió.
      if p_action = 'RUNNER_OUT' and (dest is null or dest not between 0 and 3
          or (dest > 0 and dest < source)) then
        raise exception 'Indique la base del out (0 = home); no se permite retroceder.';
      end if;
      -- DOUBLE_PLAY registra el out del bateador y el de un corredor existente.
      -- No se suman carreras por esta acción.
      made := case when p_action = 'DOUBLE_PLAY' then 2 else 1 end;
    end if;
    resulting[source] := false;
    players[source] := null;
  elsif p_action = 'SACRIFICE_FLY' then
    if g.outs >= 2 or not occupied[3] or destinations[3] is distinct from 0 then
      raise exception 'El sacrificio requiere carrera desde tercera y menos de dos outs.';
    end if;
    resulting := array[false,false,false];
    -- Procesar desde tercera hacia primera. El corredor adelantado debe
    -- terminar por delante del que viene detras; home se representa como 4.
    previous_dest := 4;
    for i in reverse 3..1 loop
      dest := destinations[i];
      if occupied[i] is distinct from (dest is not null)
          or (dest is not null and (dest < 0 or dest > 3 or (dest > 0 and dest < i))) then
        raise exception 'Avance invalido.';
      end if;
      if occupied[i] then
        next_dest := case when dest = 0 then 4 else dest end;
        if next_dest > previous_dest or (next_dest = previous_dest and next_dest <> 4) then
          raise exception 'Los corredores no pueden rebasarse ni ocupar la misma base.';
        end if;
        previous_dest := next_dest;
        if dest = 0 then runs := runs+1;
        else
          resulting[dest] := true;
          moved[dest] := players[i];
        end if;
      end if;
    end loop;
    players := moved;
    made := 1;
  elsif p_action = 'GHOST_RUNNER' then
    if g.inning <= g.swl_regulation_innings or g.home_runs <> g.away_runs
       or occupied[1] or occupied[2] or occupied[3]
       or g.outs <> 0 or g.balls <> 0 or g.strikes <> 0 then
      raise exception 'El corredor fantasma requiere entradas extras, marcador empatado y segunda libre.';
    end if;
    if exists (select 1 from public.swl_game_events where game_id = g.id and inning = g.inning
      and is_top = g.is_top) then
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
  else
    raise exception 'Acción especial sin rama de procesamiento: %', p_action;
  end if;
  -- No permitir un doble play que intente producir un cuarto out.
  if p_action = 'DOUBLE_PLAY' and g.outs > 1 then
    raise exception 'No se puede registrar doble play con dos outs.';
  end if;
  if p_action in ('RUNNER_OUT','DOUBLE_PLAY') and runner is null then
    raise exception 'Se requiere identificar al corredor retirado en la doble matanza.';
  end if;
  -- En una doble matanza el bateador y el corredor son dos outs distintos.
  -- No permitir que el mismo pelotero figure en ambos roles.
  if p_action = 'DOUBLE_PLAY' and runner = p_batter_id then
    raise exception 'El bateador y el corredor retirado deben ser distintos.';
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
COMMIT;
