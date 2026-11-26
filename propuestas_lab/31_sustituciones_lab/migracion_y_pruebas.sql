-- LAB. Instalación sin modificar partidos existentes.
CREATE TABLE swl_private.v57_participation_gate (
  id boolean PRIMARY KEY CHECK (id)
);
INSERT INTO swl_private.v57_participation_gate VALUES (true);
CREATE TABLE swl_private.v57_participation (
  game_id uuid NOT NULL REFERENCES public.swl_live_games(id) ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES public.teams(id),
  player_id uuid NOT NULL REFERENCES public.players(id),
  PRIMARY KEY (game_id, team_id, player_id)
);
CREATE INDEX ON swl_private.v57_participation (player_id);
REVOKE ALL ON swl_private.v57_participation_gate, swl_private.v57_participation
  FROM PUBLIC, anon, authenticated;

CREATE FUNCTION swl_private.v57_lineup_players(l public.swl_game_lineups)
RETURNS TABLE(player_id uuid) LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT DISTINCT ids.player_id FROM (
    SELECT (slot->>'player_id')::uuid AS player_id
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(l.lineup)='array' THEN l.lineup ELSE '[]'::jsonb END) slot
    UNION ALL SELECT l.pitcher_id
    UNION ALL SELECT l.designated_hitter_id
    UNION ALL SELECT defender::uuid
    FROM jsonb_object_keys(CASE WHEN jsonb_typeof(l.defensive_positions)='object'
      THEN l.defensive_positions ELSE '{}'::jsonb END) AS defenders(defender)
  ) ids WHERE ids.player_id IS NOT NULL;
$$;

CREATE FUNCTION swl_private.v57_check_participation(
  match_id uuid, own_team uuid, candidates uuid[]
) RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE
  conflict_game uuid;
BEGIN
  IF coalesce(cardinality(candidates),0)=0 THEN RETURN; END IF;
  WITH memberships AS (
    SELECT l.game_id,l.team_id,p.player_id
      FROM public.swl_game_lineups l
      JOIN public.swl_live_games g ON g.id=l.game_id
      CROSS JOIN LATERAL swl_private.v57_lineup_players(l) p
      WHERE g.id=match_id OR g.status IN ('IN_PROGRESS','FINAL')
    UNION ALL
    SELECT v.game_id,v.team_id,v.player_id
      FROM swl_private.v57_participation v JOIN public.swl_live_games g ON g.id=v.game_id
      WHERE g.id=match_id OR g.status IN ('IN_PROGRESS','FINAL')
    UNION ALL
    SELECT e.game_id,e.batting_team_id,ids.v::uuid
      FROM public.swl_game_events e JOIN public.swl_live_games g ON g.id=e.game_id
      CROSS JOIN LATERAL (VALUES (e.event_data->>'outgoing_player_id'),
                                 (e.event_data->>'incoming_player_id')) ids(v)
      WHERE (g.id=match_id OR g.status IN ('IN_PROGRESS','FINAL'))
        AND e.event_type='SUBSTITUTION'
        AND ids.v ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    UNION ALL
    SELECT h.game_id,h.team_id,ids.v
      FROM public.swl_v56_pitcher_changes h JOIN public.swl_live_games g ON g.id=h.game_id
      CROSS JOIN LATERAL (VALUES (h.old_pitcher_id),(h.new_pitcher_id)) ids(v)
      WHERE g.id=match_id OR g.status IN ('IN_PROGRESS','FINAL')
  )
  SELECT m.game_id INTO conflict_game
  FROM memberships m
  WHERE m.player_id=ANY(candidates)
    AND (m.game_id<>match_id OR m.team_id<>own_team)
  ORDER BY (m.game_id=match_id) DESC LIMIT 1;
  IF FOUND THEN
    IF conflict_game=match_id THEN RAISE EXCEPTION 'PELOTERO_EN_AMBOS_EQUIPOS'; END IF;
    RAISE EXCEPTION 'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO';
  END IF;
END;
$$;

CREATE FUNCTION swl_private.v57_guard_lineup()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  match_status text;
  prior_lineup public.swl_game_lineups%rowtype;
  incoming uuid[];
  old_players uuid[] := ARRAY[]::uuid[];
  new_players uuid[] := ARRAY[]::uuid[];
BEGIN
  -- Actualizar la fila serializa altas de partidos distintos y fuerza un
  -- conflicto de serialización si una transacción intenta usar una vista antigua.
  UPDATE swl_private.v57_participation_gate SET id=id WHERE id=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'PARTICIPATION_GATE_MISSING'; END IF;
  IF TG_OP='INSERT' THEN
    -- También corre antes de la rama UPDATE de INSERT ... ON CONFLICT.
    SELECT * INTO prior_lineup FROM public.swl_game_lineups l
      WHERE l.game_id=NEW.game_id AND l.team_id=NEW.team_id;
    IF FOUND THEN
      SELECT array_agg(p.player_id) INTO old_players
        FROM swl_private.v57_lineup_players(prior_lineup) p;
    END IF;
  ELSE
    SELECT array_agg(p.player_id) INTO old_players FROM swl_private.v57_lineup_players(OLD) p;
  END IF;
  IF TG_OP<>'DELETE' THEN
    SELECT array_agg(p.player_id) INTO new_players FROM swl_private.v57_lineup_players(NEW) p;
    IF TG_OP='UPDATE' AND (OLD.game_id,OLD.team_id) IS DISTINCT FROM (NEW.game_id,NEW.team_id)
    THEN RAISE EXCEPTION 'LINEUP_IDENTITY_CHANGED'; END IF;
  END IF;
  SELECT g.status INTO match_status FROM public.swl_live_games g
    WHERE g.id=CASE WHEN TG_OP='DELETE' THEN OLD.game_id ELSE NEW.game_id END;
  IF TG_OP<>'DELETE' AND match_status IN ('SCHEDULED','IN_PROGRESS','FINAL') THEN
    -- Mantener casos históricos existentes, pero no admitir nuevas colisiones.
    SELECT array_agg(id) INTO incoming FROM unnest(new_players) AS ids(id)
      WHERE NOT (id=ANY(coalesce(old_players,ARRAY[]::uuid[])));
    PERFORM swl_private.v57_check_participation(NEW.game_id,NEW.team_id,incoming);
  END IF;
  IF match_status IN ('IN_PROGRESS','FINAL') THEN
    IF TG_OP<>'INSERT' THEN
      INSERT INTO swl_private.v57_participation(game_id,team_id,player_id)
        SELECT OLD.game_id,OLD.team_id,id FROM unnest(old_players) AS ids(id)
        ON CONFLICT DO NOTHING;
    END IF;
    IF TG_OP<>'DELETE' THEN
      INSERT INTO swl_private.v57_participation(game_id,team_id,player_id)
        SELECT NEW.game_id,NEW.team_id,id FROM unnest(new_players) AS ids(id)
        ON CONFLICT DO NOTHING;
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION swl_private.v57_guard_start()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  l public.swl_game_lineups%rowtype;
  ids uuid[];
BEGIN
  UPDATE swl_private.v57_participation_gate SET id=id WHERE id=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'PARTICIPATION_GATE_MISSING'; END IF;
  FOR l IN SELECT * FROM public.swl_game_lineups WHERE game_id=NEW.id ORDER BY team_id LOOP
    SELECT array_agg(p.player_id) INTO ids FROM swl_private.v57_lineup_players(l) p;
    PERFORM swl_private.v57_check_participation(l.game_id,l.team_id,ids);
    INSERT INTO swl_private.v57_participation(game_id,team_id,player_id)
      SELECT l.game_id,l.team_id,id FROM unnest(ids) AS players(id)
      ON CONFLICT DO NOTHING;
  END LOOP;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION swl_private.v57_lineup_players(public.swl_game_lineups),
  swl_private.v57_check_participation(uuid,uuid,uuid[]),
  swl_private.v57_guard_lineup(),swl_private.v57_guard_start()
  FROM PUBLIC, anon, authenticated;
CREATE TRIGGER swl_v57_guard_participation_lineup
  BEFORE INSERT OR UPDATE OR DELETE ON public.swl_game_lineups
  FOR EACH ROW EXECUTE FUNCTION swl_private.v57_guard_lineup();
CREATE TRIGGER swl_v57_guard_participation_start
  BEFORE UPDATE OF status ON public.swl_live_games
  FOR EACH ROW WHEN (NEW.status='IN_PROGRESS' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION swl_private.v57_guard_start();
create function public.swl_v56_change_pitcher(
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
  if exists (
    select 1
    from public.swl_game_lineups rival
    where rival.game_id = p_game_id and rival.team_id <> p_team_id
      and (p_player_id in (rival.pitcher_id, rival.designated_hitter_id)
        or rival.defensive_positions ? p_player_id::text
        or exists (
          select 1 from jsonb_array_elements(rival.lineup) as slot(item)
          where slot.item->>'player_id' = p_player_id::text
        ))
  ) then
    raise exception 'PELOTERO_EN_AMBOS_EQUIPOS';
  end if;

  if exists (
    select 1 from public.swl_game_events e
    where e.game_id=p_game_id and e.batting_team_id=p_team_id
      and e.event_type='SUBSTITUTION' and e.event_data->>'outgoing_player_id'=p_player_id::text
  ) then
    raise exception 'REENTRY_NOT_SUPPORTED';
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
-- Fixture reversible. No cambia partidos ni usa la secuencia oficial de jugadores.
DO $test$
DECLARE
  g public.swl_live_games%rowtype;
  source_game public.swl_live_games%rowtype;
  fixture uuid := gen_random_uuid();
  other_game uuid := gen_random_uuid();
  home_players uuid[] := ARRAY[]::uuid[];
  away_players uuid[] := ARRAY[]::uuid[];
  current_player uuid;
  home_def jsonb;
  away_def jsonb;
  game_pin_one text;
  game_pin_two text;
  revision_now bigint;
  positions text[] := ARRAY['P','C','1B','2B','3B','SS','LF','CF','RF'];
  positions_unused text[];
BEGIN
  BEGIN
    SELECT * INTO STRICT source_game FROM public.swl_live_games WHERE game_pin='SWL-567892';
    SELECT array_agg(pin) INTO positions_unused
      FROM (SELECT 'SWL-'||p::text pin FROM generate_series(998101,998199) p
      WHERE NOT EXISTS (SELECT FROM public.swl_live_games a WHERE a.game_pin='SWL-'||p::text) LIMIT 2) open_pins;
    game_pin_one := positions_unused[1];
    game_pin_two := positions_unused[2];
    FOR i IN 1..22 LOOP
      current_player := gen_random_uuid();
      INSERT INTO public.players(id,universal_id,first_name,last_name,jersey_number,primary_position)
        VALUES(current_player,'SWL-'||(990000000+i)::text,'Fixture V57','Sustituciones '||i,i::text,'EP');
      INSERT INTO public.rosters(team_id,player_id,is_refuerzo)
        VALUES(CASE WHEN i<=11 THEN source_game.home_team_id ELSE source_game.away_team_id END,current_player,false);
      IF i<=11 THEN home_players:=array_append(home_players,current_player);
      ELSE away_players:=array_append(away_players,current_player); END IF;
    END LOOP;
    INSERT INTO public.rosters(team_id,player_id,is_refuerzo)
      VALUES(source_game.away_team_id,home_players[1],false);
    INSERT INTO public.swl_live_games(id,game_pin,home_team_id,away_team_id,created_by,
      home_manager_id,away_manager_id,status,version,inning,is_top,balls,strikes,outs,
      home_runs,away_runs,home_hits,away_hits,home_errors,away_errors,bases_state,home_innings,away_innings)
      SELECT id,pin,source_game.home_team_id,source_game.away_team_id,source_game.home_manager_id,
        source_game.home_manager_id,source_game.away_manager_id,'SCHEDULED',0,1,true,0,0,0,0,0,0,0,0,0,
        '{"first":false,"second":false,"third":false}'::jsonb,'[]'::jsonb,'[]'::jsonb
      FROM (VALUES(fixture,game_pin_one),(other_game,game_pin_two)) games(id,pin);
    SELECT jsonb_object_agg(home_players[i]::text,positions[i]) INTO home_def FROM generate_series(1,9) i;
    SELECT jsonb_object_agg((CASE WHEN i=1 THEN away_players[10] ELSE away_players[i-1] END)::text,positions[i])
      INTO away_def FROM generate_series(1,9) i;
    PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
    PERFORM public.swl_v56_save_lineup(fixture,source_game.home_team_id,home_players[1:9],0,home_players[1],true,NULL,home_def);
    PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
    BEGIN
      PERFORM public.swl_v53_save_lineup_checked(fixture,source_game.away_team_id,
        ARRAY[home_players[1]]||away_players[2:9],0);
      RAISE SQLSTATE 'ZX011' USING MESSAGE='Se aceptó el mismo UUID en ambos lados';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'PELOTERO_EN_AMBOS_EQUIPOS' THEN RAISE; END IF;
    END;
    PERFORM public.swl_v56_save_lineup(fixture,source_game.away_team_id,away_players[1:9],0,away_players[10],false,away_players[9],away_def);
    PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
    PERFORM public.swl_v56_start_game(fixture,0);
    BEGIN
      PERFORM public.swl_v56_save_lineup(other_game,source_game.home_team_id,home_players[1:9],0,home_players[1],true,NULL,home_def);
      RAISE SQLSTATE 'ZX011' USING MESSAGE='Se aceptó al jugador en un segundo partido';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO' THEN RAISE; END IF;
    END;
    INSERT INTO public.swl_game_batting_turns(game_id,team_id,next_order)
      VALUES(fixture,source_game.away_team_id,5);
    PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
    PERFORM public.swl_v56_record_plate_action(fixture,1,'OUT',away_players[5]);
    BEGIN
      PERFORM public.swl_v56_change_pitcher(fixture,2,source_game.home_team_id,home_players[2]);
      RAISE SQLSTATE 'ZX011' USING MESSAGE='El rival pudo cambiar al pitcher';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
    PERFORM public.swl_v56_change_pitcher(fixture,2,source_game.home_team_id,home_players[2]);
    IF NOT EXISTS (SELECT FROM public.swl_game_lineups l WHERE l.game_id=fixture AND l.team_id=source_game.home_team_id
      AND l.pitcher_id=home_players[2] AND l.lineup->0->>'player_id'=home_players[1]::text
      AND l.defensive_positions->>home_players[1]::text='C')
    THEN RAISE EXCEPTION 'El cambio de pitcher bateador movió indebidamente el orden'; END IF;
    PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
    SELECT l.revision INTO STRICT revision_now FROM public.swl_game_lineups l
      WHERE l.game_id=fixture AND l.team_id=source_game.away_team_id;
    PERFORM public.swl_v56_substitute_batter(fixture,source_game.away_team_id,6,away_players[6],away_players[11],revision_now,3);
    IF NOT EXISTS (SELECT FROM public.swl_game_lineups l WHERE l.game_id=fixture AND l.team_id=source_game.away_team_id
      AND l.lineup->0->>'player_id'=away_players[1]::text AND l.lineup->5->>'player_id'=away_players[11]::text)
    THEN RAISE EXCEPTION 'Sustitución alteró un puesto distinto al sexto'; END IF;
    PERFORM public.swl_v56_apply_hit(fixture,4,away_players[11],1,NULL,NULL,NULL);
    IF NOT EXISTS (SELECT FROM public.swl_game_events e WHERE e.game_id=fixture AND e.version=5 AND e.event_type='HIT'
        AND e.event_data->>'batter_id'=away_players[11]::text)
      OR NOT EXISTS (SELECT FROM public.swl_v56_pitching_events e WHERE e.game_id=fixture AND e.version=2 AND e.pitcher_id=home_players[1] AND e.outs=1)
      OR NOT EXISTS (SELECT FROM public.swl_v56_pitching_events e WHERE e.game_id=fixture AND e.version=5 AND e.pitcher_id=home_players[2] AND e.hits=1)
    THEN RAISE EXCEPTION 'Hit, lanzador entrante o estadísticas anteriores incorrectos'; END IF;
    PERFORM public.swl_v56_record_plate_action(fixture,5,'OUT',away_players[7]);
    PERFORM public.swl_v56_record_plate_action(fixture,6,'OUT',away_players[8]);
    -- Un nuevo suplente de solo defensa se mantiene fuera del orden y del DH.
    INSERT INTO public.rosters(team_id,player_id,is_refuerzo) VALUES(source_game.away_team_id,home_players[11],false);
    PERFORM public.swl_v56_change_pitcher(fixture,7,source_game.away_team_id,home_players[11]);
    IF NOT EXISTS (SELECT FROM public.swl_game_lineups l WHERE l.game_id=fixture AND l.team_id=source_game.away_team_id
      AND l.pitcher_id=home_players[11] AND l.pitcher_bats=false AND l.designated_hitter_id=away_players[9]
      AND jsonb_array_length(l.lineup)=9)
    THEN RAISE EXCEPTION 'El pitcher de solo defensa cambió el DH o los turnos'; END IF;
    PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
    PERFORM public.swl_v56_record_plate_action(fixture,8,'BALL',home_players[1]);
    IF NOT EXISTS (SELECT FROM public.swl_v56_pitching_events e WHERE e.game_id=fixture AND e.version=9
        AND e.pitcher_id=home_players[11])
    THEN RAISE EXCEPTION 'Pitcheo no atribuido al lanzador de solo defensa entrante'; END IF;
    UPDATE public.swl_live_games SET status='FINAL' WHERE id=fixture;
    PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
    BEGIN
      PERFORM public.swl_v53_save_lineup_checked(other_game,source_game.away_team_id,away_players[1:9],0);
      RAISE SQLSTATE 'ZX011' USING MESSAGE='Se liberó un sustituido antes del cierre oficial';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO' THEN RAISE; END IF;
    END;
    UPDATE public.swl_live_games SET status='OFFICIAL' WHERE id=fixture;
    PERFORM public.swl_v53_save_lineup_checked(other_game,source_game.away_team_id,away_players[1:9],0);
    IF NOT EXISTS (SELECT FROM swl_private.game_batting(fixture,NULL) b WHERE b.player_id=away_players[11] AND b.h=1)
    THEN RAISE EXCEPTION 'Box score oficial no acredita el hit al sustituto'; END IF;
    RAISE SQLSTATE 'ZX012' USING MESSAGE='revertir fixture aprobada';
  EXCEPTION WHEN SQLSTATE 'ZX012' THEN NULL;
  END;
  IF EXISTS (SELECT FROM public.swl_live_games WHERE id IN (fixture,other_game))
    THEN RAISE EXCEPTION 'Fixture no revertida'; END IF;
END
$test$;
