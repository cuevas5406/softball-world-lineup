-- Ejecutado en LAB (wgeziptdoabyicufnrfk) el 26 de noviembre de 2026.
-- La limpieza autorizada de SWL-998191 y SWL-998192 eliminó exactamente
-- 2 partidos, 4 alineaciones, 18 participaciones, 18 fichajes y 18 peloteros.
-- Verificación posterior: cero filas temporales en las cinco tablas.
-- Las huellas del partido SWL-567892, sus alineaciones y eventos, y las de
-- SWL-0023 a SWL-0032 con sus fichajes coincidieron antes y después.
-- La secuencia oficial quedó en 32, incremento 1 y valor ya emitido.
-- La regresión transaccional pasó, incluyendo rechazo de versión obsoleta
-- y de candidato externo al roster. Los partidos temporales se revierten.
BEGIN;
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
    BEGIN
      PERFORM public.swl_v56_change_pitcher(fixture,1,source_game.home_team_id,home_players[2]);
      RAISE SQLSTATE 'ZX011' USING MESSAGE='Se aceptó una versión obsoleta';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'Cambia el pitcher entre bateadores, con la versión actual del marcador.' THEN RAISE; END IF;
    END;
    BEGIN
      PERFORM public.swl_v56_change_pitcher(fixture,2,source_game.home_team_id,away_players[2]);
      RAISE SQLSTATE 'ZX011' USING MESSAGE='Se aceptó a un jugador fuera del roster';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'El nuevo pitcher debe pertenecer al roster activo y ser distinto del actual.' THEN RAISE; END IF;
    END;
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

ROLLBACK;
