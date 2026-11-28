-- Ejecutar solo en LAB después de instalar la RPC. Datos temporales.
BEGIN;
DO $test$
DECLARE
  g public.swl_live_games%rowtype;
  before_dp jsonb;
  mask integer; o integer; b integer; src integer; priv text; scenario text;
  ids uuid[]; expected uuid[]; moves jsonb; scorers uuid[];
  ev jsonb; mode text;
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

    INSERT INTO public.swl_game_batting_turns(game_id,team_id,next_order)
    VALUES(fixture,source_game.away_team_id,1)
    ON CONFLICT(game_id,team_id) DO NOTHING;
    FOR mask IN 0..7 LOOP
      FOR o IN 0..2 LOOP
        FOR src IN 1..3 LOOP
          FOR scenario IN SELECT unnest(ARRAY['hold','advance','score_force','score_time','legacy','duplicate','wrong_manager','undo']) LOOP
            IF scenario <> 'hold' AND NOT (
              (scenario='advance' AND mask=7 AND o=0 AND src=2) OR
              (scenario IN ('score_force','score_time') AND mask=7 AND src=1 AND o<2) OR
              (scenario='legacy' AND mask=1 AND src=1 AND o=0) OR
              (scenario='undo' AND mask=7 AND src=1 AND o<2) OR
              (scenario IN ('duplicate','wrong_manager') AND mask=3 AND src=1 AND o=0)
            ) THEN CONTINUE; END IF;
            BEGIN
              ids:=ARRAY[NULL,NULL,NULL]::uuid[];
              FOR b IN 1..3 LOOP
                IF (mask & (1 << (b-1))) <> 0 THEN ids[b]:=away_players[b+1]; END IF;
              END LOOP;
              UPDATE public.swl_live_games SET outs=o,
                bases_state=jsonb_build_object('first',ids[1] IS NOT NULL,'second',ids[2] IS NOT NULL,'third',ids[3] IS NOT NULL),
                swl_base_players=ids WHERE id=fixture;
              PERFORM set_config('request.jwt.claim.sub',CASE WHEN scenario='wrong_manager' THEN source_game.home_manager_id ELSE source_game.away_manager_id END::text,true);
              expected:=ids; expected[src]:=NULL; scorers:=ARRAY[]::uuid[];
              moves:='{}'; mode:='FORCE';
              IF scenario='advance' THEN moves:='{"1":2,"3":0}'; expected:=ARRAY[NULL,ids[1],NULL]; scorers:=ARRAY[ids[3]]; END IF;
              IF scenario IN ('score_force','score_time') THEN
                moves:='{"2":0,"3":0}'; expected:=ARRAY[NULL,NULL,NULL]; scorers:=ARRAY[ids[3],ids[2]];
                IF scenario='score_time' THEN mode:='TIME'; END IF;
              END IF;
              IF o=1 THEN expected:=ARRAY[NULL,NULL,NULL]::uuid[]; END IF;
              IF scenario='undo' THEN
                moves:='{"3":0}'; mode:='TIME'; scorers:=ARRAY[ids[3]];
                expected[3]:=NULL;
              END IF;
              SELECT to_jsonb(a)-'updated_at'-'version' INTO STRICT before_dp
                FROM public.swl_live_games a WHERE id=fixture;
              priv:=CASE WHEN scenario='wrong_manager' THEN '42501'
                WHEN o=2 THEN 'DOUBLE_PLAY_REQUIRES_FEWER_THAN_TWO_OUTS'
                WHEN ids[src] IS NULL THEN 'RUNNER_NOT_ON_BASE'
                WHEN scenario='score_force' AND o=1 THEN 'DOUBLE_PLAY_RUN_CANNOT_SCORE_ON_THIRD_OUT' END;
              BEGIN
                IF scenario='legacy' THEN PERFORM public.swl_v57_double_play(fixture,1,src);
                ELSE PERFORM public.swl_v57_double_play_advanced(fixture,1,src,moves,mode); END IF;
                IF priv IS NOT NULL THEN RAISE SQLSTATE 'ZX001' USING MESSAGE='Se aceptó jugada inválida'; END IF;
              EXCEPTION WHEN OTHERS THEN
                IF priv IS NOT NULL AND (SQLSTATE=priv OR SQLERRM=priv) THEN
                  RAISE SQLSTATE 'ZX002' USING MESSAGE='Rechazo verificado';
                END IF;
                RAISE;
              END;
              SELECT * INTO STRICT g FROM public.swl_live_games WHERE id=fixture;
              SELECT event_data INTO STRICT ev FROM public.swl_game_events WHERE game_id=fixture AND version=2 AND event_type='DOUBLE_PLAY';
              IF g.version<>2 OR g.is_top IS DISTINCT FROM (o=0) OR g.inning<>1
                 OR g.outs<>(CASE WHEN o=0 THEN 2 ELSE 0 END)
                 OR g.swl_base_players IS DISTINCT FROM expected
                 OR g.away_runs<>cardinality(scorers) OR g.home_runs<>0
                 OR ev->>'runner_id' IS DISTINCT FROM ids[src]::text
                 OR ev->>'batter_id' IS DISTINCT FROM away_players[1]::text
                 OR (ev->>'outs_added')::int IS DISTINCT FROM 2
                 OR (scenario<>'legacy' AND (ev->'scoring_player_ids' IS DISTINCT FROM to_jsonb(scorers)
                    OR ev->>'plate_appearance_completed' IS DISTINCT FROM 'true'))
                 OR NOT EXISTS (SELECT FROM public.swl_game_batting_turns WHERE game_id=fixture AND team_id=source_game.away_team_id AND next_order=2)
                 OR NOT EXISTS (SELECT FROM public.swl_v56_pitching_events WHERE game_id=fixture AND version=2 AND outs=2 AND pitcher_id=home_players[1] AND hits=0 AND walks=0 AND strikes_out=0)
              THEN RAISE EXCEPTION 'Estado o crédito inesperado: %, %, %, %',mask,o,src,scenario; END IF;
              IF scenario='duplicate' THEN
                BEGIN
                  PERFORM public.swl_v57_double_play_advanced(fixture,1,src,moves,mode);
                  RAISE SQLSTATE 'ZX001' USING MESSAGE='Duplicado aceptado';
                EXCEPTION WHEN raise_exception THEN
                  IF SQLERRM <> 'El partido o la versión cambió antes de anotar.' THEN RAISE; END IF;
                END;
                IF (SELECT count(*) FROM public.swl_game_events WHERE game_id=fixture)<>1 THEN RAISE EXCEPTION 'Historial duplicado'; END IF;
              END IF;
              IF scenario IN ('legacy','undo') THEN
                IF ev->>'pitcher_id' IS DISTINCT FROM home_players[1]::text THEN
                  RAISE EXCEPTION 'Pitcher ausente del historial';
                END IF;
                PERFORM public.swl_v57_undo_last_out(fixture,2);
                IF NOT EXISTS(SELECT FROM public.swl_live_games a WHERE id=fixture AND version=3
                    AND (to_jsonb(a)-'updated_at'-'version') = before_dp)
                  OR NOT EXISTS(SELECT FROM public.swl_game_batting_turns WHERE game_id=fixture
                    AND team_id=source_game.away_team_id AND next_order=1)
                  OR EXISTS(SELECT FROM public.swl_v56_pitching_events WHERE game_id=fixture)
                  OR NOT EXISTS(SELECT FROM public.swl_game_events WHERE game_id=fixture
                    AND version=3 AND event_type='UNDO_OUT' AND event_data->>'reverts_version'='2')
                  OR NOT EXISTS(SELECT FROM public.swl_game_events WHERE game_id=fixture
                    AND version=2 AND event_type='DOUBLE_PLAY')
                THEN RAISE EXCEPTION 'Deshacer no restauró el estado anterior'; END IF;
              END IF;
              RAISE SQLSTATE 'ZX002' USING MESSAGE='Revertir escenario probado';
            EXCEPTION WHEN SQLSTATE 'ZX002' THEN NULL;
            END;
          END LOOP;
        END LOOP;
      END LOOP;
    END LOOP;
    RAISE SQLSTATE 'ZX003' USING MESSAGE='Revertir preparación';
  EXCEPTION WHEN SQLSTATE 'ZX003' THEN NULL;
  END;
  IF EXISTS (SELECT FROM public.swl_live_games WHERE id IN (fixture,other_game)) THEN RAISE EXCEPTION 'Fixture persistente'; END IF;
END;
$test$;

ROLLBACK;
