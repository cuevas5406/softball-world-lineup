-- Prueba transaccional exclusiva de LAB. La excepción de prueba revierte toda la fixture.
DO $regression$
DECLARE
  fixture public.swl_live_games%rowtype;
  state_now public.swl_live_games%rowtype;
  game_id_test uuid := gen_random_uuid();
  source_id uuid;
  pin_test text;
  visitor uuid[];
  local_batters uuid[];
  version_now bigint;
  strike_no integer;
  ball_no integer;
  expected_rejection text;
  old_hits bigint;
  old_pitch_rows bigint;
  prior_hash text;
  scorer uuid;
BEGIN
  BEGIN
    SELECT * INTO STRICT fixture FROM public.swl_live_games WHERE game_pin='SWL-567892';
    source_id := fixture.id;
    SELECT 'SWL-' || lpad(n::text,6,'0') INTO STRICT pin_test
      FROM generate_series(999999,999900,-1) AS pin(n)
      WHERE NOT EXISTS (SELECT FROM public.swl_live_games g
        WHERE g.game_pin='SWL-' || lpad(pin.n::text,6,'0')) LIMIT 1;
    SELECT array_agg((s.item->>'player_id')::uuid ORDER BY s.ordinal) INTO visitor
      FROM public.swl_game_lineups l, jsonb_array_elements(l.lineup) WITH ORDINALITY s(item,ordinal)
      WHERE l.game_id=source_id AND l.team_id=fixture.away_team_id;
    SELECT array_agg((s.item->>'player_id')::uuid ORDER BY s.ordinal) INTO local_batters
      FROM public.swl_game_lineups l, jsonb_array_elements(l.lineup) WITH ORDINALITY s(item,ordinal)
      WHERE l.game_id=source_id AND l.team_id=fixture.home_team_id;

    fixture.id := game_id_test;
    fixture.game_pin := pin_test;
    fixture.version := 0;
    fixture.inning := 1;
    fixture.is_top := true;
    fixture.balls := 0;
    fixture.strikes := 0;
    fixture.outs := 0;
    fixture.home_runs := 0;
    fixture.away_runs := 0;
    fixture.home_hits := 0;
    fixture.away_hits := 0;
    fixture.home_errors := 0;
    fixture.away_errors := 0;
    fixture.home_innings := '[]'::jsonb;
    fixture.away_innings := '[]'::jsonb;
    fixture.bases_state := '{"first":false,"second":false,"third":false}'::jsonb;
    fixture.swl_base_players := ARRAY[NULL,NULL,NULL]::uuid[];
    fixture.swl_ghost_player := NULL;
    INSERT INTO public.swl_live_games SELECT (fixture).*;
    INSERT INTO public.swl_game_lineups
       (game_id,team_id,lineup,submitted_by,pitcher_id,designated_hitter_id,pitcher_bats,defensive_positions)
      SELECT game_id_test,team_id,lineup,submitted_by,pitcher_id,designated_hitter_id,pitcher_bats,defensive_positions
      FROM public.swl_game_lineups WHERE game_id=source_id;

    PERFORM set_config('request.jwt.claim.sub',fixture.away_manager_id::text,true);
    PERFORM public.swl_v56_apply_hit(game_id_test,0,visitor[1],1,NULL,NULL,NULL);
    PERFORM public.swl_v56_apply_hit(game_id_test,1,visitor[2],4,0,NULL,NULL);
    FOR strike_no IN 2..4 LOOP
      PERFORM public.swl_v56_record_plate_action(game_id_test,strike_no,'STRIKE',visitor[3]);
    END LOOP;
    FOR ball_no IN 5..8 LOOP
      PERFORM public.swl_v56_record_plate_action(game_id_test,ball_no,'BALL',visitor[4]);
    END LOOP;
    PERFORM public.swl_v57_double_play(game_id_test,9,1);
    SELECT * INTO STRICT state_now FROM public.swl_live_games g WHERE g.id=game_id_test;
    IF (state_now.version,state_now.inning,state_now.is_top,state_now.outs,state_now.away_runs,state_now.away_hits)
       IS DISTINCT FROM (10::bigint,1,false,0,2,2)
       OR (SELECT next_order FROM public.swl_game_batting_turns
          WHERE game_id=game_id_test AND team_id=fixture.away_team_id) IS DISTINCT FROM 6
    THEN RAISE EXCEPTION 'Doble play, media entrada o cursor visitante incorrectos'; END IF;

    PERFORM set_config('request.jwt.claim.sub',fixture.home_manager_id::text,true);
    PERFORM public.swl_v56_record_plate_action(game_id_test,10,'BALL',local_batters[1]);
    IF (SELECT next_order FROM public.swl_game_batting_turns
        WHERE game_id=game_id_test AND team_id=fixture.home_team_id) IS DISTINCT FROM 1
    THEN RAISE EXCEPTION 'Una bola no debe avanzar el cursor local'; END IF;

    -- El sencillo es una alternativa independiente desde el mismo estado.
    BEGIN
      PERFORM public.swl_v57_batted_ball(game_id_test,11,'HIT_WITH_OUT',local_batters[1],
        jsonb_build_object('p_batter_id',local_batters[1],'p_batter_base',1));
      IF NOT EXISTS (SELECT FROM public.swl_live_games
          WHERE id=game_id_test AND version=12 AND home_hits=1 AND away_errors=0
            AND swl_base_players[1]=local_batters[1])
        OR NOT EXISTS (SELECT FROM public.swl_game_events
          WHERE game_id=game_id_test AND version=12 AND event_type='HIT')
      THEN RAISE EXCEPTION 'Sencillo localizado en un estado incorrecto'; END IF;
      RAISE SQLSTATE 'ZX001' USING MESSAGE='revertir solo variante sencillo';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
    END;

    SELECT count(*),coalesce(sum(hits),0) INTO old_pitch_rows,old_hits
      FROM public.swl_v56_pitching_events WHERE game_id=game_id_test;
    PERFORM public.swl_v57_defensive_error(game_id_test,11,'ERROR',local_batters[1],
      jsonb_build_object('p_batter_id',local_batters[1],'p_batter_base',1));
    SELECT * INTO STRICT state_now FROM public.swl_live_games g WHERE g.id=game_id_test;
    IF (state_now.version,state_now.home_runs,state_now.home_hits,state_now.away_errors,state_now.balls,state_now.outs)
        IS DISTINCT FROM (12::bigint,0,0,1,0,0)
      OR state_now.swl_base_players[1] IS DISTINCT FROM local_batters[1]
      OR (SELECT next_order FROM public.swl_game_batting_turns
          WHERE game_id=game_id_test AND team_id=fixture.home_team_id) IS DISTINCT FROM 2
      OR (SELECT count(*) FROM public.swl_game_events WHERE game_id=game_id_test AND version=12
          AND event_type='ERROR' AND event_data->'scoring_player_ids'='[]'::jsonb) <> 1
    THEN RAISE EXCEPTION 'Error con bases vacías no coincide con lo esperado'; END IF;

    prior_hash := md5(to_jsonb(state_now)::text);
    FOR expected_rejection IN SELECT unnest(ARRAY['version','manager','out']) LOOP
      BEGIN
        PERFORM set_config('request.jwt.claim.sub',CASE WHEN expected_rejection='manager'
          THEN fixture.away_manager_id ELSE fixture.home_manager_id END::text,true);
        version_now := CASE WHEN expected_rejection='version' THEN 11 ELSE 12 END;
        PERFORM public.swl_v57_defensive_error(game_id_test,version_now,'ERROR',local_batters[2],
          jsonb_build_object('p_batter_id',local_batters[2],'p_batter_base',1,
            'p_first_to',CASE WHEN expected_rejection='out' THEN -2 ELSE 0 END));
        RAISE SQLSTATE 'ZX002' USING MESSAGE='Se aceptó una anotación que debía rechazarse';
      EXCEPTION WHEN insufficient_privilege THEN
        IF expected_rejection <> 'manager' THEN RAISE; END IF;
      WHEN raise_exception THEN
        IF NOT ((expected_rejection='version' AND SQLERRM='El partido o la versión cambió antes de anotar.')
          OR (expected_rejection='out' AND SQLERRM='V57_ERROR_OUT_NOT_ENABLED')) THEN RAISE; END IF;
      END;
    END LOOP;
    IF (SELECT md5(to_jsonb(g)::text) FROM public.swl_live_games g WHERE g.id=game_id_test) <> prior_hash
      OR (SELECT count(*) FROM public.swl_game_events WHERE game_id=game_id_test) <> 12
      OR (SELECT next_order FROM public.swl_game_batting_turns
          WHERE game_id=game_id_test AND team_id=fixture.home_team_id) IS DISTINCT FROM 2
    THEN RAISE EXCEPTION 'Un rechazo modificó el partido, el cursor o los eventos'; END IF;

    PERFORM set_config('request.jwt.claim.sub',fixture.home_manager_id::text,true);
    PERFORM public.swl_v57_defensive_error(game_id_test,12,'ERROR',local_batters[2],
      jsonb_build_object('p_batter_id',local_batters[2],'p_batter_base',1,'p_first_to',0));
    scorer := local_batters[1];
    IF NOT EXISTS (SELECT FROM public.swl_live_games
       WHERE id=game_id_test AND version=13 AND home_runs=1 AND home_hits=0 AND away_errors=2
         AND swl_base_players[1]=local_batters[2])
      OR (SELECT count(*) FROM public.swl_game_events WHERE game_id=game_id_test AND version=13
          AND event_type='ERROR' AND event_data->'scoring_player_ids'=jsonb_build_array(scorer)) <> 1
      OR (SELECT count(*) FROM public.swl_game_events WHERE game_id=game_id_test) <> 13
      OR (SELECT count(*) FROM public.swl_v56_pitching_events WHERE game_id=game_id_test) <> old_pitch_rows
      OR (SELECT coalesce(sum(hits),0) FROM public.swl_v56_pitching_events WHERE game_id=game_id_test) <> old_hits
      OR (SELECT next_order FROM public.swl_game_batting_turns
          WHERE game_id=game_id_test AND team_id=fixture.home_team_id) IS DISTINCT FROM 3
    THEN RAISE EXCEPTION 'Error con carrera, historial, estadísticas o cursor inconsistentes'; END IF;

    -- Consultar estadísticas oficiales solo sobre la fixture reversible.
    UPDATE public.swl_live_games SET status='OFFICIAL' WHERE id=game_id_test;
    IF NOT EXISTS (SELECT FROM swl_private.game_batting(game_id_test,NULL) b
        WHERE b.player_id=scorer AND b.team_id=fixture.home_team_id AND b.ab=1 AND b.h=0 AND b.r=1)
      OR NOT EXISTS (SELECT FROM swl_private.game_batting(game_id_test,NULL) b
        WHERE b.player_id=local_batters[2] AND b.team_id=fixture.home_team_id AND b.ab=1 AND b.h=0)
    THEN RAISE EXCEPTION 'Estadísticas oficiales no coinciden con los dos errores y una carrera'; END IF;
    RAISE SQLSTATE 'ZX003' USING MESSAGE='revertir fixture de pruebas aprobadas';
  EXCEPTION WHEN SQLSTATE 'ZX003' THEN NULL;
  END;
  IF EXISTS (SELECT FROM public.swl_live_games WHERE id=game_id_test)
    OR EXISTS (SELECT FROM public.swl_game_events WHERE game_id=game_id_test)
  THEN RAISE EXCEPTION 'La fixture de pruebas no se revirtió'; END IF;
END
$regression$;
