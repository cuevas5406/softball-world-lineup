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
    PERFORM public.swl_v56_start_game(fixture,0);

    FOR scenario IN SELECT * FROM (VALUES
      ('super exacto visitante',3,false,2,1,16,false,'Súper knockout'),
      ('super debajo del margen',3,false,2,1,15,false,NULL),
      ('visitante debe defender la baja',3,true,2,1,16,false,NULL),
      ('super local cierra al terminar alta',3,true,2,16,1,false,'Súper knockout'),
      ('super local al alcanzar margen',3,false,0,15,1,true,'Súper knockout'),
      ('KO exacto visitante',4,false,2,1,11,false,'Knockout'),
      ('KO debajo del margen',4,false,2,1,10,false,NULL),
      ('KO local cierra al terminar alta',4,true,2,11,1,false,'Knockout'),
      ('KO local al alcanzar margen',4,false,0,10,1,true,'Knockout'),
      ('sexta local gana sin batear',6,true,2,2,1,false,'Final reglamentario'),
      ('sexta visitante debe defender la baja',6,true,2,1,2,false,NULL),
      ('sexta visitante gana tras la baja',6,false,2,1,2,false,'Final reglamentario'),
      ('sexta local deja en el terreno',6,false,0,2,2,true,'Final reglamentario'),
      ('empate abre séptima',6,false,2,2,2,false,NULL),
      ('victoria local en extra',7,false,0,3,3,true,'Final reglamentario')
    ) AS v(label, inning, top, outs, home, away, hit, reason) LOOP
      BEGIN
        UPDATE public.swl_live_games SET inning=scenario.inning,is_top=scenario.top,
          outs=scenario.outs,home_runs=scenario.home,away_runs=scenario.away,
          home_innings=jsonb_build_array(scenario.home),away_innings=jsonb_build_array(scenario.away)
        WHERE id=fixture;
        PERFORM set_config('request.jwt.claim.sub',CASE WHEN scenario.top
          THEN source_game.away_manager_id ELSE source_game.home_manager_id END::text,true);
        batter:=CASE WHEN scenario.top THEN away_players[1] ELSE home_players[1] END;
        active_pitcher:=CASE WHEN scenario.top THEN home_players[1] ELSE away_players[10] END;
        IF scenario.hit THEN
          PERFORM public.swl_v56_apply_hit(fixture,1,batter,4,NULL,NULL,NULL);
        ELSE
          PERFORM public.swl_v56_record_plate_action(fixture,1,'OUT',batter);
        END IF;
        SELECT * INTO STRICT g FROM public.swl_live_games WHERE id=fixture;
        IF g.version<>2 OR g.swl_finish_reason IS DISTINCT FROM scenario.reason
          OR g.status IS DISTINCT FROM (CASE WHEN scenario.reason IS NULL THEN 'IN_PROGRESS' ELSE 'FINAL' END)
          OR g.home_runs<>scenario.home+(CASE WHEN scenario.hit THEN 1 ELSE 0 END)
          OR g.away_runs<>scenario.away
          OR NOT EXISTS (SELECT FROM public.swl_game_events WHERE game_id=fixture AND version=2
            AND event_type=CASE WHEN scenario.hit THEN 'HIT' ELSE 'OUT' END AND event_data->>'batter_id'=batter::text)
          OR NOT EXISTS (SELECT FROM public.swl_v56_pitching_events WHERE game_id=fixture AND version=2
            AND pitcher_id=active_pitcher AND outs=CASE WHEN scenario.hit THEN 0 ELSE 1 END
            AND hits=CASE WHEN scenario.hit THEN 1 ELSE 0 END)
        THEN RAISE EXCEPTION 'Cierre o jugada incorrectos: %',scenario.label; END IF;
        IF scenario.reason IS NOT NULL THEN
          IF g.inning<>scenario.inning OR g.is_top<>scenario.top
             OR g.swl_final_half_completed IS DISTINCT FROM (scenario.outs=2 AND NOT scenario.hit)
             OR (SELECT count(*) FROM public.swl_v56_match_decisions
                 WHERE game_id=fixture AND version=2 AND action='AUTO')<>1
          THEN RAISE EXCEPTION 'Auditoría de cierre incorrecta: %',scenario.label; END IF;
          BEGIN
            PERFORM public.swl_v56_record_plate_action(fixture,2,'OUT',batter);
            RAISE SQLSTATE 'ZX011' USING MESSAGE='Se pudo anotar después del cierre';
          EXCEPTION WHEN raise_exception THEN
            IF SQLERRM<>'El partido o la versión cambió antes de anotar.' THEN RAISE; END IF;
          END;
          BEGIN
            PERFORM public.swl_v56_record_plate_action(fixture,1,'OUT',batter);
            RAISE SQLSTATE 'ZX011' USING MESSAGE='Reintento de tercer OUT aceptado';
          EXCEPTION WHEN raise_exception THEN
            IF SQLERRM<>'El partido o la versión cambió antes de anotar.' THEN RAISE; END IF;
          END;
          IF (SELECT count(*) FROM public.swl_v56_match_decisions WHERE game_id=fixture AND action='AUTO')<>1
             OR (SELECT count(*) FROM public.swl_game_events WHERE game_id=fixture)<>1
          THEN RAISE EXCEPTION 'Reintento duplicó auditoría o jugada'; END IF;
          IF scenario.label='super exacto visitante' THEN
            PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
            PERFORM public.swl_v56_match_decision(fixture,2,'SIGN');
            PERFORM public.swl_v56_match_decision(fixture,3,'SIGN');
            PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
            PERFORM public.swl_v56_match_decision(fixture,3,'SIGN');
            IF NOT EXISTS (SELECT FROM public.swl_live_games WHERE id=fixture AND version=4
                           AND status='OFFICIAL' AND home_runs=1 AND away_runs=16)
               OR (SELECT count(*) FROM public.swl_v56_match_decisions WHERE game_id=fixture AND action='SIGN')<>2
               OR NOT EXISTS (SELECT FROM swl_private.game_batting(fixture,NULL::uuid))
               OR NOT EXISTS (SELECT FROM swl_private.game_pitching(fixture,NULL::uuid))
            THEN RAISE EXCEPTION 'Firmas, ganador o estadísticas oficiales incorrectos'; END IF;
          END IF;
        ELSIF g.is_top IS DISTINCT FROM (NOT scenario.top)
           OR g.inning<>scenario.inning+(CASE WHEN scenario.top THEN 0 ELSE 1 END)
        THEN RAISE EXCEPTION 'No avanzó la media entrada: %',scenario.label; END IF;
        RAISE SQLSTATE 'ZX012';
      EXCEPTION WHEN SQLSTATE 'ZX012' THEN NULL;
      END;
    END LOOP;

    FOR scenario IN SELECT * FROM (VALUES
      ('ACCEPT',5,2,1,true),('REJECT',5,2,1,true),
      ('INVALIDATED',5,2,1,true),('REQUEST',4,2,1,false),('REQUEST',5,2,2,false)
    ) AS v(action,inning,home,away,allowed) LOOP
      BEGIN
        UPDATE public.swl_live_games SET inning=scenario.inning,home_runs=scenario.home,
          away_runs=scenario.away WHERE id=fixture;
        PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
        BEGIN
          PERFORM public.swl_v56_match_decision(fixture,1,'REQUEST');
          IF NOT scenario.allowed THEN RAISE SQLSTATE 'ZX011' USING MESSAGE='Solicitud prematura o empatada aceptada'; END IF;
        EXCEPTION WHEN raise_exception THEN
          IF NOT scenario.allowed AND SQLERRM='El partido no admite esta acción.' THEN RAISE SQLSTATE 'ZX012'; END IF;
          RAISE;
        END;
        BEGIN
          PERFORM public.swl_v56_match_decision(fixture,2,'ACCEPT');
          RAISE SQLSTATE 'ZX011' USING MESSAGE='Cierre unilateral aceptado';
        EXCEPTION WHEN raise_exception THEN
          IF SQLERRM<>'El partido no admite esta acción.' THEN RAISE; END IF;
        END;
        PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
        IF scenario.action='INVALIDATED' THEN
          PERFORM public.swl_v56_record_plate_action(fixture,2,'OUT',away_players[1]);
        ELSE
          PERFORM public.swl_v56_match_decision(fixture,2,scenario.action);
        END IF;
        IF NOT EXISTS(SELECT FROM public.swl_live_games WHERE id=fixture AND version=3
          AND swl_finish_requested_by IS NULL AND status=CASE WHEN scenario.action='ACCEPT' THEN 'FINAL' ELSE 'IN_PROGRESS' END)
          OR NOT EXISTS(SELECT FROM public.swl_v56_match_decisions WHERE game_id=fixture
                        AND version=3 AND action=scenario.action)
        THEN RAISE EXCEPTION 'Decisión de cierre incorrecta: %',scenario.action; END IF;
        RAISE SQLSTATE 'ZX012';
      EXCEPTION WHEN SQLSTATE 'ZX012' THEN NULL;
      END;
    END LOOP;
    RAISE SQLSTATE 'ZX013';
  EXCEPTION WHEN SQLSTATE 'ZX013' THEN NULL;
  END;
  IF EXISTS (SELECT FROM public.swl_live_games WHERE id IN (fixture,other_game))
  THEN RAISE EXCEPTION 'Partidos temporales persistentes'; END IF;
END;
$test$;
ROLLBACK;
