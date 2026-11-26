-- Ejecutar en LAB solo tras autorizar e instalar 27_v57_cancelar_partido.sql.
-- Los datos de SWL-567892 sirven exclusivamente para leer IDs de equipos
-- y mánagers. Todos los cambios de esta prueba se revierten.
BEGIN;
DO $test$
DECLARE
  history_before jsonb;
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
        VALUES(current_player,'SWL-'||(990000300+i)::text,'Fixture V57','Cancelación '||i,i::text,'EP');
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
    PERFORM public.swl_v57_cancel_game(fixture,1,'CANCEL_REQUEST');
    BEGIN
      PERFORM public.swl_v57_cancel_game(fixture,2,'CANCEL_ACCEPT');
      RAISE SQLSTATE 'ZX011' USING MESSAGE='El solicitante pudo aceptar unilateralmente';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'CANCEL_ACTION_UNAVAILABLE' THEN RAISE; END IF;
    END;
    BEGIN
      PERFORM public.swl_v57_cancel_game(fixture,2,'CANCEL_REJECT');
      RAISE SQLSTATE 'ZX011' USING MESSAGE='El solicitante pudo rechazar su propia solicitud';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'CANCEL_ACTION_UNAVAILABLE' THEN RAISE; END IF;
    END;
    PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
    BEGIN
      PERFORM public.swl_v57_cancel_game(fixture,2,'CANCEL_ACCEPT');
      RAISE SQLSTATE 'ZX011' USING MESSAGE='Una cuenta ajena pudo aceptar';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
    BEGIN
      PERFORM public.swl_v56_save_lineup(other_game,source_game.home_team_id,home_players[1:9],0,home_players[1],true,NULL,home_def);
      RAISE SQLSTATE 'ZX011' USING MESSAGE='Una solicitud pendiente liberó a un jugador';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO' THEN RAISE; END IF;
    END;
    PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
    PERFORM public.swl_v57_cancel_game(fixture,2,'CANCEL_REJECT');
    IF NOT EXISTS (SELECT FROM public.swl_live_games
      WHERE id=fixture AND status='IN_PROGRESS' AND swl_cancel_requested_by IS NULL AND version=3)
    THEN RAISE EXCEPTION 'El rechazo cambió el estado o no retiró la solicitud'; END IF;
    PERFORM public.swl_v56_substitute_batter(
      fixture,source_game.away_team_id,1,away_players[1],away_players[11],
      (SELECT revision FROM public.swl_game_lineups
       WHERE game_id=fixture AND team_id=source_game.away_team_id),3
    );
    PERFORM public.swl_v56_record_plate_action(fixture,4,'OUT',away_players[11]);
    SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id) INTO history_before
      FROM public.swl_game_events e WHERE game_id=fixture;
    IF history_before IS NULL THEN RAISE EXCEPTION 'No se registró la jugada de control'; END IF;
    BEGIN
      PERFORM swl_private.v57_check_participation(
        other_game,source_game.away_team_id,ARRAY[away_players[1]]
      );
      RAISE SQLSTATE 'ZX011' USING MESSAGE='Se liberó al sustituido antes de cancelar';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO' THEN RAISE; END IF;
    END;
    PERFORM public.swl_v57_cancel_game(fixture,5,'CANCEL_REQUEST');
    PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
    BEGIN
      PERFORM public.swl_v57_cancel_game(fixture,5,'CANCEL_ACCEPT');
      RAISE SQLSTATE 'ZX011' USING MESSAGE='Se aceptó una versión obsoleta';
    EXCEPTION WHEN serialization_failure THEN
      IF SQLERRM <> 'CANCEL_STALE_VERSION' THEN RAISE; END IF;
    END;
    PERFORM public.swl_v57_cancel_game(fixture,6,'CANCEL_ACCEPT');
    IF NOT EXISTS (SELECT FROM public.swl_live_games
      WHERE id=fixture AND status='CANCELLED' AND swl_cancel_requested_by IS NULL AND version=7)
      OR (SELECT array_agg(action ORDER BY version)
          FROM public.swl_v57_cancel_decisions WHERE game_id=fixture)
         IS DISTINCT FROM ARRAY['CANCEL_REQUEST','CANCEL_REJECT','CANCEL_REQUEST','CANCEL_ACCEPT']
      OR (SELECT array_agg(actor_id ORDER BY version)
          FROM public.swl_v57_cancel_decisions WHERE game_id=fixture)
         IS DISTINCT FROM ARRAY[source_game.home_manager_id, source_game.away_manager_id,
                                  source_game.away_manager_id, source_game.home_manager_id]
      OR (SELECT count(*) FROM swl_private.v57_participation WHERE game_id=fixture) <> 20
      OR EXISTS (SELECT FROM swl_private.game_batting(fixture,NULL))
      OR EXISTS (SELECT FROM swl_private.game_pitching(fixture,NULL))
    THEN RAISE EXCEPTION 'Estado, auditoría, participación histórica o estadísticas incorrectas'; END IF;
    PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
    BEGIN
      PERFORM public.swl_v56_record_plate_action(fixture,7,'BALL',away_players[2]);
      RAISE SQLSTATE 'ZX011' USING MESSAGE='Un partido cancelado permitió anotar';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'El partido o la versión cambió antes de anotar.' THEN RAISE; END IF;
    END;
    IF (SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id)
        FROM public.swl_game_events e WHERE game_id=fixture)
       IS DISTINCT FROM history_before
    THEN RAISE EXCEPTION 'Se alteró el historial del partido cancelado'; END IF;
    PERFORM swl_private.v57_check_participation(other_game,source_game.home_team_id,home_players[1:9]);
    PERFORM swl_private.v57_check_participation(other_game,source_game.away_team_id,away_players);
    PERFORM public.swl_v56_save_lineup(other_game,source_game.away_team_id,away_players[1:9],0,away_players[10],false,away_players[9],away_def);
    PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
    PERFORM public.swl_v56_save_lineup(other_game,source_game.home_team_id,home_players[1:9],0,home_players[1],true,NULL,home_def);
    PERFORM public.swl_v56_start_game(other_game,0);
    IF NOT EXISTS (SELECT FROM public.swl_live_games WHERE id=other_game AND status='IN_PROGRESS')
    THEN RAISE EXCEPTION 'No se pudo iniciar otro partido con los peloteros liberados'; END IF;
  END;
END
$test$;
ROLLBACK;
