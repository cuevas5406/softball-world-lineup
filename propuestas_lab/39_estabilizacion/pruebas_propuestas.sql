BEGIN;
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
  scenario record;
  batter uuid;
  active_pitcher uuid;
  positions text[] := ARRAY['P','C','1B','2B','3B','SS','LF','CF','RF'];
  positions_unused text[];
BEGIN
  BEGIN
    SELECT * INTO STRICT source_game FROM public.swl_live_games WHERE game_pin='SWL-378859';
    SELECT array_agg(pin ORDER BY pin) INTO positions_unused
      FROM (SELECT 'SWL-'||p::text pin FROM generate_series(998101,998199) p
      WHERE NOT EXISTS (SELECT FROM public.swl_live_games a WHERE a.game_pin='SWL-'||p::text) LIMIT 2) open_pins;
    game_pin_one := positions_unused[1];
    game_pin_two := positions_unused[2];
    FOR i IN 1..22 LOOP
      current_player := gen_random_uuid();
      INSERT INTO public.players(id,universal_id,first_name,last_name,jersey_number,primary_position)
        VALUES(current_player,'SWL-'||(990000400+i)::text,'Fixture V57','Cierre '||i,i::text,'EP');
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



    FOR scenario IN SELECT * FROM (VALUES
      ('AUTO', 'FINAL', false), ('DISABLED', 'IN_PROGRESS', false),
      ('CONSULT', 'IN_PROGRESS', false), ('CONSULT', 'IN_PROGRESS', true)
    ) AS v(mode, expected, finish) LOOP
      BEGIN
        PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
        PERFORM public.swl_v57_knockout_decision(fixture,0,scenario.mode);
        PERFORM public.swl_v56_start_game(fixture,1);
        UPDATE public.swl_live_games SET inning=3,is_top=false,outs=2,
          home_runs=1,away_runs=16,home_innings='[1,0,0]',away_innings='[0,0,16]'
          WHERE id=fixture;
        PERFORM public.swl_v56_record_plate_action(fixture,2,'OUT',home_players[1]);
        SELECT * INTO g FROM public.swl_live_games WHERE id=fixture;
        IF g.status IS DISTINCT FROM scenario.expected
           OR (g.swl_knockout_pending IS NOT NULL)<>(scenario.mode='CONSULT')
        THEN RAISE EXCEPTION 'Modo incorrecto: %',scenario.mode; END IF;
        IF scenario.mode='CONSULT' THEN
          PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
          BEGIN
            PERFORM public.swl_v57_knockout_decision(fixture,3,'CONTINUE');
            RAISE SQLSTATE 'ZX011' USING MESSAGE='Un fanático pudo votar';
          EXCEPTION WHEN insufficient_privilege THEN
            IF SQLERRM<>'KNOCKOUT_MANAGER_REQUIRED' THEN RAISE; END IF;
          END;
          PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
          BEGIN
            PERFORM public.swl_v56_record_plate_action(fixture,3,'OUT',away_players[1]);
            RAISE SQLSTATE 'ZX011' USING MESSAGE='Se pudo anotar durante la consulta';
          EXCEPTION WHEN raise_exception THEN
            IF SQLERRM<>'KNOCKOUT_DECISION_PENDING' THEN RAISE; END IF;
          END;
          IF scenario.finish THEN
            PERFORM public.swl_v57_knockout_decision(fixture,3,'FINISH');
            IF NOT EXISTS(SELECT FROM public.swl_live_games WHERE id=fixture
              AND status='FINAL' AND swl_knockout_pending IS NULL
              AND swl_finish_reason='Súper knockout' AND version=4)
            THEN RAISE EXCEPTION 'La negativa no finalizó el partido'; END IF;
            RAISE SQLSTATE 'ZX012';
          END IF;
          PERFORM public.swl_v57_knockout_decision(fixture,3,'CONTINUE');
          BEGIN
            PERFORM public.swl_v57_knockout_decision(fixture,4,'FINISH');
            RAISE SQLSTATE 'ZX011' USING MESSAGE='Se permitió cambiar el voto';
          EXCEPTION WHEN raise_exception THEN
            IF SQLERRM<>'KNOCKOUT_ALREADY_VOTED' THEN RAISE; END IF;
          END;
          PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
          PERFORM public.swl_v57_knockout_decision(fixture,4,'CONTINUE');
          IF NOT EXISTS(SELECT FROM public.swl_live_games WHERE id=fixture
            AND status='IN_PROGRESS' AND swl_knockout_pending IS NULL
            AND swl_knockout_waived_through=3 AND version=5)
          THEN RAISE EXCEPTION 'Dos votos no reanudaron el juego'; END IF;
          PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
          PERFORM public.swl_v56_record_plate_action(fixture,5,'OUT',away_players[1]);
          IF EXISTS (SELECT FROM public.swl_live_games WHERE id=fixture
                     AND swl_knockout_pending IS NOT NULL)
          THEN RAISE EXCEPTION 'Se reabrió antes de terminar la cuarta'; END IF;
          UPDATE public.swl_live_games SET is_top=false,outs=2 WHERE id=fixture;
          PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
          PERFORM public.swl_v56_record_plate_action(fixture,6,'OUT',home_players[2]);
          IF NOT EXISTS (SELECT FROM public.swl_live_games WHERE id=fixture
             AND version=7 AND swl_knockout_pending->>'reason'='Knockout')
            OR (SELECT count(*) FROM swl_private.v57_knockout_audit
                WHERE game_id=fixture AND action='PENDING')<>2
          THEN RAISE EXCEPTION 'No se reabrió la consulta al finalizar la cuarta'; END IF;
        END IF;
        RAISE SQLSTATE 'ZX012';
      EXCEPTION WHEN SQLSTATE 'ZX012' THEN NULL;
      END;
    END LOOP;
    PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
    PERFORM public.swl_v56_start_game(fixture,0);
    PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
    PERFORM public.swl_v56_apply_hit(fixture,1,away_players[1],1,NULL,NULL,NULL);
    FOR scenario IN SELECT * FROM (VALUES
      (-1,0),(-2,0),(-3,0),(-4,0),(-2,2)
    ) AS v(destination, previous_outs) LOOP
      BEGIN
        UPDATE public.swl_live_games SET outs=scenario.previous_outs WHERE id=fixture;
        PERFORM public.swl_v57_defensive_error(fixture,2,'ERROR',away_players[2],
          jsonb_build_object('p_batter_id',away_players[2],'p_batter_base',1,'p_first_to',scenario.destination));
        IF NOT EXISTS (SELECT FROM public.swl_live_games WHERE id=fixture
           AND outs=CASE WHEN scenario.previous_outs=2 THEN 0 ELSE 1 END
           AND is_top=(scenario.previous_outs=0) AND home_errors=1 AND away_hits=1
           AND swl_base_players[1] IS NOT DISTINCT FROM
             CASE WHEN scenario.previous_outs=2 THEN NULL::uuid ELSE away_players[2] END)
           OR NOT EXISTS (SELECT FROM public.swl_v56_pitching_events WHERE game_id=fixture
              AND version=3 AND pitcher_id=home_players[1] AND outs=1 AND hits=0)
           OR NOT EXISTS (SELECT FROM public.swl_game_events WHERE game_id=fixture
              AND version=3 AND event_type='ERROR' AND event_data->>'out_runner_id'=away_players[1]::text
              AND (event_data->>'out_at_base')::integer=-scenario.destination)
        THEN RAISE EXCEPTION 'Out por error incorrecto: %',scenario.destination; END IF;
        RAISE SQLSTATE 'ZX012';
      EXCEPTION WHEN SQLSTATE 'ZX012' THEN NULL;
      END;
    END LOOP;

    PERFORM public.swl_v56_apply_hit(fixture,2,away_players[2],1,2,NULL,NULL);
    PERFORM public.swl_v56_apply_hit(fixture,3,away_players[3],1,2,3,NULL);
    FOR scenario IN SELECT * FROM (VALUES
      (0,-3,-4,0,NULL::integer,false,2,1),
      (1,-3,-4,0,1,true,2,1),
      (1,-2,-4,0,1,true,2,0),
      (0,-2,-3,-4,3,false,3,0)
    ) AS v(previous_outs,first_to,second_to,third_to,last_out,timing,outs_added,runs) LOOP
      BEGIN
        UPDATE public.swl_live_games SET outs=scenario.previous_outs WHERE id=fixture;
        PERFORM public.swl_v57_defensive_error(fixture,4,'ERROR',away_players[4],
          jsonb_build_object('p_batter_id',away_players[4],'p_batter_base',1,
           'p_first_to',scenario.first_to,'p_second_to',scenario.second_to,
           'p_third_to',scenario.third_to,'p_last_out_source',scenario.last_out,
           'count_runs_on_third_out',scenario.timing));
        IF NOT EXISTS (SELECT FROM public.swl_live_games WHERE id=fixture AND version=5
            AND away_runs=scenario.runs AND away_hits=3 AND home_errors=1
            AND is_top=(scenario.previous_outs+scenario.outs_added<3)
            AND outs=(scenario.previous_outs+scenario.outs_added)%3)
          OR NOT EXISTS (SELECT FROM public.swl_v56_pitching_events WHERE game_id=fixture
              AND version=5 AND pitcher_id=home_players[1] AND outs=scenario.outs_added AND hits=0)
          OR NOT EXISTS (SELECT FROM public.swl_game_events WHERE game_id=fixture
              AND version=5 AND event_type='ERROR' AND event_data->>'batter_id'=away_players[4]::text
              AND event_data->>'pitcher_id'=home_players[1]::text
              AND jsonb_array_length(event_data->'out_runner_ids')=scenario.outs_added
              AND (event_data->>'runs')::int=scenario.runs)
          THEN RAISE EXCEPTION 'Error con múltiples outs incorrecto: %',scenario; END IF;
        BEGIN
          PERFORM public.swl_v57_defensive_error(fixture,4,'ERROR',away_players[4],
            jsonb_build_object('p_batter_id',away_players[4],'p_batter_base',1,
             'p_first_to',scenario.first_to,'p_second_to',scenario.second_to,
             'p_third_to',scenario.third_to,'p_last_out_source',scenario.last_out));
          RAISE SQLSTATE 'ZX011' USING MESSAGE='Se aceptó repetir un error';
        EXCEPTION WHEN raise_exception OR insufficient_privilege THEN
          IF SQLERRM NOT IN ('El partido o la versión cambió antes de anotar.',
                               'Solo anota el mánager del equipo al bate.') THEN RAISE; END IF;
        END;
        IF (SELECT count(*) FROM public.swl_game_events
              WHERE game_id=fixture AND event_type='ERROR')<>1
          THEN RAISE EXCEPTION 'Se duplicó el evento de error'; END IF;
        IF NOT EXISTS (
          SELECT FROM jsonb_array_elements(
            public.swl_v57_spectator_box_source(fixture)->'pitches') p
            WHERE (p->>'version')::int=5 AND p->>'pitcher_id'=home_players[1]::text)
          OR public.swl_v57_spectator_box_source(fixture)->'game' ? 'home_manager_id'
          THEN RAISE EXCEPTION 'Box Score público inconsistente'; END IF;
        RAISE SQLSTATE 'ZX012';
      EXCEPTION WHEN SQLSTATE 'ZX012' THEN NULL;
      END;
    END LOOP;
    IF public.swl_v57_spectator_box_source(other_game) IS NOT NULL THEN
      RAISE EXCEPTION 'Box Score disponible antes de iniciar el partido';
    END IF;
    PERFORM set_config('request.jwt.claim.sub','',true);
    IF public.swl_v57_spectator_box_source(fixture) IS NOT NULL
      OR has_function_privilege('anon','public.swl_v57_spectator_box_source(uuid)','EXECUTE')

    THEN RAISE EXCEPTION 'Acceso público indebido al Box Score'; END IF;
    RAISE SQLSTATE 'ZX013';
  EXCEPTION WHEN SQLSTATE 'ZX013' THEN NULL;
  END;
END;
$test$;
ROLLBACK;
