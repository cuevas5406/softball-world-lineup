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
  runner_text text;
  ghost uuid;
  players uuid[];
  moved uuid[] := array[null,null,null]::uuid[];
  keys text[] := array['first','second','third'];
  occupied boolean[];
  resulting boolean[];
  source int;
  dest int;
  destinations int[];
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
  -- Rechazar solicitudes no autenticadas antes de interpretar datos externos.
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
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
  -- Convertir los parámetros solo después de verificar el objeto JSON.
  -- Así los errores de tipo son explícitos y no fallan durante DECLARE.
  -- Validar TODOS los destinos antes de convertirlos a integer.
  -- JSON permite decimales, exponentes y cadenas arbitrarias; la RPC solo
  -- admite enteros de base (0 = home, 1..3 = bases). null es opcional.
  if exists (
    select 1 from jsonb_each(p_data) as field(key, value)
    where field.key = any(array['source','destination','first_to','second_to','third_to'])
      and field.value <> 'null'::jsonb
      and (
        jsonb_typeof(field.value) <> 'number'
        or field.value::text !~ '^[0-3]$'
      )
  ) then
    raise exception 'Las bases y destinos deben ser enteros entre 0 y 3.';
  end if;
  -- El jugador puede ser UUID o el marcador especial LAST_OUT solo para extras.
  -- Validar el texto antes de convertirlo a uuid (evita mensajes crípticos).
  if p_action in ('GHOST_RUNNER','RUNNER_REPLACE') then
    if jsonb_typeof(p_data -> 'player_id') <> 'string'
       or (p_data ->> 'player_id') is null
       or not (
         (p_action = 'GHOST_RUNNER' and btrim(p_data ->> 'player_id') = 'LAST_OUT')
         or (p_data ->> 'player_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       ) then
      raise exception 'Seleccione un jugador válido para esta jugada.';
    end if;
  end if;
  source := (p_data ->> 'source')::integer;
  dest := (p_data ->> 'destination')::integer;
  destinations := array[(p_data ->> 'first_to')::integer,
    (p_data ->> 'second_to')::integer,(p_data ->> 'third_to')::integer];
  g := public.swl_v56_lock_batting_turn(p_game_id, p_expected_version);
  if g.inning is null or g.inning < 1
      or g.outs is null or g.outs not between 0 and 2
      or g.balls is null or g.balls not between 0 and 3
      or g.strikes is null or g.strikes not between 0 and 2
      or g.home_runs is null or g.home_runs < 0
      or g.away_runs is null or g.away_runs < 0 then
    raise exception 'Estado de partido inválido para una jugada especial.';
  end if;
  team := case when g.is_top then g.away_team_id else g.home_team_id end;
  if p_action is null or p_action not in ('RUNNER_MOVE','RUNNER_OUT','RUNNER_REPLACE','GHOST_RUNNER','DOUBLE_PLAY','SACRIFICE_FLY') then
    raise exception 'Jugada especial inválida.';
  end if;
  -- No interpretar un JSON incompleto o nulo como bases vacías.
  if g.bases_state is null or jsonb_typeof(g.bases_state) <> 'object' then
    raise exception 'El estado de bases está incompleto o es inválido.';
  end if;
  if not (g.bases_state ?& array['first','second','third'])
      or (select count(*) from jsonb_object_keys(g.bases_state)) <> 3 then
    raise exception 'El estado de bases está incompleto o es inválido.';
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
    if p_batter_id is null or not exists (
        select 1 from jsonb_array_elements(batting_order) as slot(item)
        where coalesce(slot.item ->> 'order', slot.item ->> 'batting_order') = turn_order::text
          and slot.item ->> 'player_id' = p_batter_id::text) then
      raise exception 'El bateador cambió.';
    end if;
  end if;
  if p_action = 'RUNNER_REPLACE' then
    if source is null or source not between 1 and 3 or not occupied[source] or players[source] is null then
      raise exception 'Falta la identidad confirmada del corredor.';
    end if;
    -- El identificador del sustituto proviene del cliente: validar antes del cast.
    -- No aceptar LAST_OUT en sustituciones; es exclusivo del corredor fantasma.
    runner_text := p_data ->> 'player_id';
    if runner_text is null or runner_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Seleccione un jugador sustituto con identificador válido.';
    end if;
    runner := runner_text::uuid;
    if runner = any(players) then raise exception 'El sustituto ya ocupa una base.'; end if;
    select lineup, revision into strict batting_order, lineup_revision from public.swl_game_lineups
      where game_id = g.id and team_id = team;
    select coalesce(slot.item ->> 'order', slot.item ->> 'batting_order')::integer into turn_order
      from jsonb_array_elements(batting_order) as slot(item)
      where slot.item ->> 'player_id' = players[source]::text;
    if turn_order is null then raise exception 'El corredor no pertenece al turno activo.'; end if;
    if exists (select 1 from public.swl_game_lineups l
        where l.game_id = g.id and l.team_id = team and l.pitcher_id is not null) then
      perform public.swl_v56_substitute_batter(g.id,team,turn_order,players[source],runner,lineup_revision,g.version);
    else
      perform public.swl_v53_substitute_batter(g.id,team,turn_order,players[source],runner,lineup_revision,g.version);
    end if;
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
    if runner is null and p_action in ('RUNNER_MOVE','RUNNER_OUT','DOUBLE_PLAY') then
      raise exception 'Confirme la identidad del corredor antes de registrar la jugada.';
    end if;
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
    if g.outs >= 2 or not occupied[3] or players[3] is null
       or destinations[3] is distinct from 0 then
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
    if g.swl_regulation_innings is null or g.swl_regulation_innings < 1
       or g.swl_allow_roster_ghost is null
       or g.inning <= g.swl_regulation_innings or g.home_runs <> g.away_runs
       or occupied[1] or occupied[2] or occupied[3]
       or g.outs <> 0 or g.balls <> 0 or g.strikes <> 0 then
      raise exception 'El corredor fantasma requiere entradas extras, marcador empatado y segunda libre.';
    end if;
    if exists (select 1 from public.swl_game_events where game_id = g.id and inning = g.inning
      and is_top = g.is_top) then
      raise exception 'Ya se colocó un corredor fantasma en esta media entrada.';
    end if;
    if btrim(p_data ->> 'player_id') = 'LAST_OUT' then
      -- Leer primero como texto: un evento histórico incompleto no debe
      -- provocar una excepción de conversión a UUID.
      select case when event_type::text in ('RUNNER_OUT','DOUBLE_PLAY','HIT')
          then coalesce(nullif(btrim(event_data ->> 'last_out_player_id'), ''),
                        nullif(btrim(event_data ->> 'runner_id'), ''),
                        nullif(btrim(event_data ->> 'out_runner_id'), ''))
          else coalesce(nullif(btrim(event_data ->> 'last_out_player_id'), ''),
                        nullif(btrim(event_data ->> 'batter_id'), '')) end
        into runner_text
        from public.swl_game_events
        where game_id = g.id and batting_team_id = team and
          (event_type::text in ('OUT','RUNNER_OUT','SACRIFICE_FLY','DOUBLE_PLAY')
           or (event_type::text = 'HIT' and event_data -> 'third_out' = 'true'::jsonb)
           or (event_type::text = 'STRIKE'
               and event_data -> 'plate_appearance_completed' = 'true'::jsonb))
        order by version desc nulls last, id desc limit 1;
      -- Normalizar también el valor seleccionado del historial: el cast y
      -- la expresión regular deben comprobar exactamente el mismo texto.
      runner_text := nullif(btrim(runner_text), '');
      if runner_text is null
         or runner_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        raise exception 'No se pudo identificar al jugador del último out. Seleccione un corredor del roster.';
      end if;
      runner := runner_text::uuid;
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
