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
  fan_id uuid := gen_random_uuid();
  lineup_revision bigint;
  manager_box jsonb;
  fan_box jsonb;
  admin_action text;
  dp_case text;
  dp_actor uuid;
  dp_rival uuid;
  dp_team uuid;
  dp_players uuid[];
  dp_version bigint;
  dp_before jsonb;
  dp_credit jsonb;
  dp_defense jsonb;
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
    FOR scenario IN
      SELECT * FROM (VALUES (3,15,'Súper knockout'),(4,10,'Knockout')) n(inning,margin,reason)
      CROSS JOIN (VALUES ('AUTO'),('CONSULT'),('DISABLED')) m(mode)
      CROSS JOIN (VALUES ('AWAY_REDUCE'),('AWAY_HOLD'),('HOME_LEAD')) s(side)
    LOOP
      BEGIN
        PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
        PERFORM public.swl_v57_knockout_decision(fixture,0,scenario.mode);
        PERFORM public.swl_v56_start_game(fixture,1);
        UPDATE public.swl_live_games SET inning=scenario.inning,outs=2,
          home_runs=CASE WHEN scenario.side='HOME_LEAD' THEN scenario.margin ELSE 0 END,
          away_runs=CASE WHEN scenario.side='HOME_LEAD' THEN 0 ELSE scenario.margin END
        WHERE id=fixture;
        PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
        PERFORM public.swl_v56_record_plate_action(fixture,2,'OUT',away_players[1]);
        IF scenario.side<>'HOME_LEAD' OR scenario.mode='DISABLED' THEN
          IF NOT EXISTS (SELECT FROM public.swl_live_games WHERE id=fixture
             AND version=3 AND status='IN_PROGRESS' AND inning=scenario.inning
             AND NOT is_top AND outs=0 AND swl_knockout_pending IS NULL)
          THEN RAISE EXCEPTION 'Se omitió el derecho al bate: %',scenario; END IF;
        END IF;
        IF scenario.side<>'HOME_LEAD' THEN
          PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
          IF scenario.side='AWAY_REDUCE' THEN
            PERFORM public.swl_v56_apply_hit(fixture,3,home_players[1],4,NULL,NULL,NULL);
            IF NOT EXISTS (SELECT FROM public.swl_live_games WHERE id=fixture AND version=4
              AND home_runs=1 AND away_runs-home_runs=scenario.margin-1)
            THEN RAISE EXCEPTION 'No se redujo la diferencia: %',scenario; END IF;
          END IF;
          FOR j IN 1..3 LOOP
            PERFORM public.swl_v56_record_plate_action(fixture,
              2+j+CASE WHEN scenario.side='AWAY_REDUCE' THEN 1 ELSE 0 END,
              'OUT',home_players[j+CASE WHEN scenario.side='AWAY_REDUCE' THEN 1 ELSE 0 END]);
          END LOOP;
        END IF;
        SELECT * INTO STRICT g FROM public.swl_live_games WHERE id=fixture;
        IF scenario.side='AWAY_REDUCE' OR scenario.mode='DISABLED' THEN
          IF g.status<>'IN_PROGRESS' OR g.swl_knockout_pending IS NOT NULL
             OR (scenario.side<>'HOME_LEAD' AND (g.inning<>scenario.inning+1 OR NOT g.is_top))
          THEN RAISE EXCEPTION 'El encuentro debía continuar: %',scenario; END IF;
        ELSIF scenario.mode='AUTO' THEN
          IF g.status<>'FINAL' OR g.swl_finish_reason IS DISTINCT FROM scenario.reason
            OR g.inning<>scenario.inning OR g.is_top IS DISTINCT FROM (scenario.side='HOME_LEAD')
          THEN RAISE EXCEPTION 'Cierre automático incorrecto: %',scenario; END IF;
        ELSIF g.status<>'IN_PROGRESS'
          OR g.swl_knockout_pending->>'reason' IS DISTINCT FROM scenario.reason
          OR (g.swl_knockout_pending->>'top')::boolean IS DISTINCT FROM (scenario.side='HOME_LEAD')
        THEN RAISE EXCEPTION 'Consulta de knockout incorrecta: %',scenario;
        END IF;
        RAISE SQLSTATE 'ZX012';
      EXCEPTION WHEN SQLSTATE 'ZX012' THEN NULL;
      END;
    END LOOP;

    BEGIN
      PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
      PERFORM public.swl_v56_start_game(fixture,0);
      UPDATE public.swl_live_games SET is_top=false WHERE id=fixture;
      PERFORM public.swl_v56_apply_hit(fixture,1,home_players[1],1,NULL,NULL,NULL);
      PERFORM public.swl_v57_defensive_error(fixture,2,'ERROR',home_players[2],
        jsonb_build_object('p_batter_id',home_players[2],'p_batter_base',1,'p_first_to',2));
      PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
      PERFORM public.swl_v56_change_pitcher(p_game_id=>fixture,p_expected_version=>3,
        p_team_id=>source_game.away_team_id,p_player_id=>away_players[11]);
      IF NOT EXISTS (SELECT FROM public.swl_live_games WHERE id=fixture AND version=4
        AND swl_base_players[1]=home_players[2] AND swl_base_players[2]=home_players[1])
      THEN RAISE EXCEPTION 'El relevo perdió los corredores heredados'; END IF;
      PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
      PERFORM public.swl_v56_apply_hit(fixture,4,home_players[3],4,0,0,NULL);
      PERFORM public.swl_v56_apply_hit(fixture,5,home_players[4],1,NULL,NULL,NULL);
      PERFORM public.swl_v57_defensive_error(fixture,6,'ERROR',home_players[5],
        jsonb_build_object('p_batter_id',home_players[5],'p_batter_base',1,'p_first_to',-2));
      SELECT revision INTO STRICT lineup_revision FROM public.swl_game_lineups
        WHERE game_id=fixture AND team_id=source_game.home_team_id;
      PERFORM public.swl_v56_substitute_batter(fixture,source_game.home_team_id,4,
        home_players[4],home_players[10],lineup_revision,7);
      SELECT * INTO STRICT g FROM public.swl_live_games WHERE id=fixture;
      IF g.version<>8 OR g.home_runs<>3 OR g.home_hits<>3 OR g.away_errors<>2 OR g.outs<>1
      THEN RAISE EXCEPTION 'Totales colectivos inesperados tras el relevo'; END IF;

      -- Oráculo de este caso: relaciona a los anotadores del HR con su
      -- aparición de llegada a base y el crédito de pitcheo de esa versión.
      IF EXISTS (
        WITH scorers AS (
          SELECT jsonb_array_elements_text(e.event_data->'scoring_player_ids') AS player
          FROM public.swl_game_events e WHERE e.game_id=fixture AND e.version=5 AND e.event_type='HIT'
        ), charges AS (
          SELECT p.pitcher_id,count(*)::int AS runs,
                 count(*) FILTER (WHERE e.event_type='HIT')::int AS earned
          FROM scorers s JOIN public.swl_game_events e
            ON e.game_id=fixture AND e.version IN (2,3,5) AND e.event_data->>'batter_id'=s.player
          JOIN public.swl_v56_pitching_events p ON p.game_id=e.game_id AND p.version=e.version
          GROUP BY p.pitcher_id
        ), expected AS (
          SELECT * FROM (VALUES (away_players[10],2,1),(away_players[11],1,1))
            AS x(pitcher_id,runs,earned)
        )
        SELECT FROM ((SELECT * FROM expected EXCEPT ALL SELECT * FROM charges)
          UNION ALL (SELECT * FROM charges EXCEPT ALL SELECT * FROM expected)) diffs
      ) THEN RAISE EXCEPTION 'Créditos C/CL inesperados en la secuencia de prueba'; END IF;
      IF EXISTS (
        SELECT FROM (VALUES (away_players[10],2,1,0),(away_players[11],3,2,1))
          AS expected(id,contacts,hits,outs)
        WHERE (SELECT ROW(count(*)::int,coalesce(sum(p.hits),0)::int,coalesce(sum(p.outs),0)::int)
          FROM public.swl_v56_pitching_events p WHERE p.game_id=fixture AND p.pitcher_id=expected.id)
          IS DISTINCT FROM ROW(expected.contacts,expected.hits,expected.outs)
      ) OR NOT EXISTS (SELECT FROM public.swl_game_events e
         WHERE e.game_id=fixture AND e.version=7 AND e.event_type='ERROR'
           AND e.event_data->'out_runner_ids'=jsonb_build_array(home_players[4]))
        OR NOT EXISTS (SELECT FROM public.swl_v56_pitcher_changes c
           WHERE c.game_id=fixture AND c.version=4 AND c.old_pitcher_id=away_players[10]
             AND c.new_pitcher_id=away_players[11])
      THEN RAISE EXCEPTION 'No se conservaron los lanzamientos, outs o cambios individuales'; END IF;

      manager_box := public.swl_v57_spectator_box_source(fixture);
      IF manager_box IS NULL OR jsonb_array_length(manager_box->'lineups')<>2
        OR jsonb_array_length(manager_box->'events')<>6 OR jsonb_array_length(manager_box->'pitches')<>5
        OR (manager_box->'game'->>'home_runs')::integer IS DISTINCT FROM g.home_runs
        OR NOT EXISTS (SELECT FROM jsonb_array_elements(manager_box->'lineups') l
          WHERE l->>'team_id'=source_game.home_team_id::text
            AND l->'defensive_positions' ? home_players[10]::text
            AND EXISTS (SELECT FROM jsonb_array_elements(l->'lineup') slot
              WHERE slot->>'player_id'=home_players[10]::text))
        OR NOT EXISTS (SELECT FROM jsonb_array_elements(manager_box->'events') e
          WHERE e->>'event_type'='SUBSTITUTION'
            AND e->'event_data'->>'outgoing_player_id'=home_players[4]::text)
        OR NOT EXISTS (SELECT FROM jsonb_array_elements(manager_box->'players') p
          WHERE p->>'id'=home_players[4]::text)
      THEN RAISE EXCEPTION 'La fuente del Box Score está incompleta'; END IF;
      IF EXISTS (
        (SELECT (r->>'version')::bigint, r->>'pitcher_id', (r->>'hits')::int, (r->>'outs')::int
         FROM jsonb_array_elements(manager_box->'pitches') r
         EXCEPT ALL
         SELECT version, pitcher_id::text, hits, outs
         FROM public.swl_v56_pitching_events WHERE game_id=fixture)
        UNION ALL
        (SELECT version, pitcher_id::text, hits, outs
         FROM public.swl_v56_pitching_events WHERE game_id=fixture
         EXCEPT ALL
         SELECT (r->>'version')::bigint, r->>'pitcher_id', (r->>'hits')::int, (r->>'outs')::int
         FROM jsonb_array_elements(manager_box->'pitches') r)
      ) THEN RAISE EXCEPTION 'El pitcheo público difiere de los créditos oficiales'; END IF;
      IF (SELECT count(*) FROM jsonb_array_elements(manager_box->'events') e
            WHERE e->>'event_type'='HIT' AND e->>'batting_team_id'=source_game.home_team_id::text)
          IS DISTINCT FROM g.home_hits::bigint
      THEN RAISE EXCEPTION 'El bateo público difiere del total oficial'; END IF;

      -- Rol efectivo de la Data API con una identidad temporal sin afiliación.
      PERFORM set_config('request.jwt.claim.sub',fan_id::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',fan_id,'role','authenticated')::text,true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      IF current_user<>'authenticated' OR auth.uid() IS DISTINCT FROM fan_id
      THEN RAISE EXCEPTION 'No se aplicó la identidad del fanático'; END IF;
      fan_box := public.swl_v57_spectator_box_source(fixture);
      IF fan_box IS DISTINCT FROM manager_box
        OR fan_box->'game' ?| ARRAY['home_manager_id','away_manager_id','created_by']
        OR EXISTS (SELECT FROM jsonb_array_elements(fan_box->'players') p
          WHERE p ?| ARRAY['email','phone','account_id','universal_id'])
        OR EXISTS (SELECT FROM jsonb_array_elements(fan_box->'events') e WHERE e ? 'actor_id')
      THEN RAISE EXCEPTION 'Diferencia de datos o filtración de información privada'; END IF;

      FOR admin_action IN SELECT unnest(ARRAY['SCORE','SUBSTITUTE','CANCEL','SIGN','STATS']) LOOP
        BEGIN
          CASE admin_action
            WHEN 'SCORE' THEN PERFORM public.swl_v56_record_plate_action(fixture,8,'OUT',home_players[6]);
            WHEN 'SUBSTITUTE' THEN PERFORM public.swl_v56_substitute_batter(fixture,source_game.home_team_id,6,
              home_players[6],home_players[11],lineup_revision+1,8);
            WHEN 'CANCEL' THEN PERFORM public.swl_v57_cancel_game(fixture,8,'CANCEL_REQUEST');
            WHEN 'SIGN' THEN PERFORM public.swl_v56_match_decision(fixture,8,'SIGN');
            WHEN 'STATS' THEN
              UPDATE public.swl_v56_pitching_events SET hits=999 WHERE game_id=fixture;
              IF NOT FOUND THEN CONTINUE; END IF;
          END CASE;
          RAISE SQLSTATE 'ZX011' USING MESSAGE='El fanático pudo ejecutar: '||admin_action;
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;
      END LOOP;
      IF public.swl_v57_spectator_box_source(fixture) IS DISTINCT FROM manager_box
      THEN RAISE EXCEPTION 'El fanático alteró el partido'; END IF;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claim.sub','',true);
      PERFORM set_config('request.jwt.claims','{}',true);
      EXECUTE 'SET LOCAL ROLE anon';
      BEGIN
        PERFORM public.swl_v57_spectator_box_source(fixture);
        RAISE SQLSTATE 'ZX011' USING MESSAGE='Anónimo obtuvo acceso a la RPC';
      EXCEPTION WHEN insufficient_privilege THEN NULL;
      END;
      EXECUTE 'RESET ROLE';
      RAISE SQLSTATE 'ZX012';
    EXCEPTION WHEN SQLSTATE 'ZX012' THEN NULL;
    END;

    -- D01–D05: esquema histórico, ambas entradas de anotación y knockout.
    FOR dp_case IN SELECT unnest(ARRAY['HISTORICAL','STANDARD','TIME','AUTO','CONSULT']) LOOP
      BEGIN
        PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
        PERFORM public.swl_v56_start_game(fixture,0);
        UPDATE public.swl_live_games SET
          inning=CASE WHEN dp_case IN ('AUTO','CONSULT') THEN 3 ELSE 1 END,
          is_top=dp_case NOT IN ('AUTO','CONSULT'),
          outs=CASE WHEN dp_case='STANDARD' THEN 0 ELSE 1 END,
          swl_knockout_mode=CASE WHEN dp_case='CONSULT' THEN 'CONSULT'
                                 WHEN dp_case='AUTO' THEN 'AUTO' ELSE 'DISABLED' END,
          away_runs=CASE WHEN dp_case IN ('AUTO','CONSULT') THEN 15 ELSE 0 END,
          away_innings=CASE WHEN dp_case IN ('AUTO','CONSULT') THEN '[0,0,15]'::jsonb ELSE '[]'::jsonb END
          WHERE id=fixture;
        SELECT * INTO STRICT g FROM public.swl_live_games WHERE id=fixture;
        dp_actor:=CASE WHEN g.is_top THEN source_game.away_manager_id ELSE source_game.home_manager_id END;
        dp_rival:=CASE WHEN g.is_top THEN source_game.home_manager_id ELSE source_game.away_manager_id END;
        dp_team:=CASE WHEN g.is_top THEN source_game.away_team_id ELSE source_game.home_team_id END;
        dp_players:=CASE WHEN g.is_top THEN away_players ELSE home_players END;
        PERFORM set_config('request.jwt.claim.sub',dp_actor::text,true);
        PERFORM public.swl_v56_apply_hit(fixture,1,dp_players[1],
          CASE WHEN dp_case='TIME' THEN 3 ELSE 1 END,NULL,NULL,NULL);
        IF dp_case='TIME' THEN
          PERFORM public.swl_v57_defensive_error(fixture,2,'ERROR',dp_players[2],
            jsonb_build_object('p_batter_id',dp_players[2],'p_batter_base',1,'p_third_to',3));
        END IF;
        SELECT * INTO STRICT g FROM public.swl_live_games WHERE id=fixture;
        dp_version:=g.version;
        dp_before:=to_jsonb(g)-ARRAY['updated_at','version'];
        SELECT jsonb_agg(to_jsonb(p) ORDER BY p.version,p.pitcher_id) INTO dp_credit
          FROM public.swl_v56_pitching_events p WHERE p.game_id=fixture;
        SELECT to_jsonb(l) INTO STRICT dp_defense FROM public.swl_game_lineups l
          WHERE l.game_id=fixture AND l.team_id<>dp_team;
        IF dp_case IN ('HISTORICAL','STANDARD') THEN
          PERFORM public.swl_v57_double_play(fixture,dp_version,1);
        ELSE
          PERFORM public.swl_v57_double_play_advanced(fixture,dp_version,1,
            CASE WHEN dp_case='TIME' THEN '{"3":0}'::jsonb ELSE '{}'::jsonb END,
            CASE WHEN dp_case='TIME' THEN 'TIME' ELSE 'FORCE' END);
        END IF;
        IF NOT EXISTS (SELECT FROM swl_private.v57_dp_undo_state s
          WHERE s.game_id=fixture AND s.version=dp_version+1 AND s.snapshot_schema=2
            AND s.prior-ARRAY['updated_at','version']=dp_before)
        THEN RAISE EXCEPTION 'La RPC no escribió el snapshot v2: %',dp_case; END IF;
        IF dp_case='HISTORICAL' THEN
          -- Reproduce la forma exacta anterior al DDL con datos temporales.
          UPDATE swl_private.v57_dp_undo_state SET snapshot_schema=1,
            prior=prior-ARRAY['swl_knockout_mode','swl_knockout_waived_through','swl_knockout_pending']
          WHERE game_id=fixture AND version=dp_version+1;
        END IF;
        IF NOT EXISTS (SELECT FROM public.swl_v56_pitching_events p WHERE p.game_id=fixture
            AND p.version=dp_version+1 AND p.outs=2 AND p.pitcher_id::text=dp_defense->>'pitcher_id')
        THEN RAISE EXCEPTION 'Crédito DP incorrecto: %',dp_case; END IF;
        IF dp_case='TIME' AND NOT EXISTS (SELECT FROM public.swl_live_games a
          WHERE a.id=fixture AND NOT a.is_top AND a.outs=0 AND a.away_runs=1)
        THEN RAISE EXCEPTION 'No se registró el tercer out y la carrera de tiempo'; END IF;
        IF dp_case='AUTO' AND NOT EXISTS (SELECT FROM public.swl_v56_match_decisions
          WHERE game_id=fixture AND version=dp_version+1 AND action='AUTO')
        THEN RAISE EXCEPTION 'Falta la decisión automática tras DP'; END IF;

        PERFORM set_config('request.jwt.claim.sub',dp_rival::text,true);
        BEGIN
          PERFORM public.swl_v57_undo_last_out(fixture,dp_version+1);
          RAISE SQLSTATE 'ZX011' USING MESSAGE='El rival pudo deshacer el DP';
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;
        PERFORM set_config('request.jwt.claim.sub',dp_actor::text,true);
        IF dp_case='CONSULT' THEN
          BEGIN
            PERFORM public.swl_v57_undo_last_out(fixture,dp_version+1);
            RAISE SQLSTATE 'ZX011' USING MESSAGE='Deshacer borró una consulta pendiente';
          EXCEPTION WHEN raise_exception THEN
            IF SQLERRM<>'KNOCKOUT_DECISION_PENDING' THEN RAISE; END IF;
          END;
          PERFORM public.swl_v57_knockout_decision(fixture,dp_version+1,'CONTINUE');
          PERFORM set_config('request.jwt.claim.sub',dp_rival::text,true);
          PERFORM public.swl_v57_knockout_decision(fixture,dp_version+2,'CONTINUE');
          BEGIN
            PERFORM public.swl_v57_undo_last_out(fixture,dp_version+1);
            RAISE SQLSTATE 'ZX011' USING MESSAGE='Deshacer obsoleto borró votos válidos';
          EXCEPTION WHEN raise_exception THEN
            IF SQLERRM<>'GAME_STATE_CHANGED' THEN RAISE; END IF;
          END;
          IF NOT EXISTS (SELECT FROM public.swl_live_games a WHERE a.id=fixture
            AND a.swl_knockout_mode='CONSULT' AND a.swl_knockout_pending IS NULL
            AND a.swl_knockout_waived_through=3 AND a.version=dp_version+3)
            OR (SELECT count(*) FROM swl_private.v57_knockout_audit
                WHERE game_id=fixture AND action='CONTINUE')<>2
          THEN RAISE EXCEPTION 'Se perdieron votos o configuración'; END IF;
        ELSE
          PERFORM public.swl_v57_undo_last_out(fixture,dp_version+1);
          IF NOT EXISTS (SELECT FROM public.swl_live_games a WHERE a.id=fixture
              AND a.version=dp_version+2 AND to_jsonb(a)-ARRAY['updated_at','version']=dp_before)
            OR (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.version,p.pitcher_id)
                FROM public.swl_v56_pitching_events p WHERE p.game_id=fixture) IS DISTINCT FROM dp_credit
            OR (SELECT to_jsonb(l) FROM public.swl_game_lineups l
                WHERE l.game_id=fixture AND l.team_id<>dp_team) IS DISTINCT FROM dp_defense
            OR NOT EXISTS (SELECT FROM public.swl_game_batting_turns WHERE game_id=fixture
                AND team_id=dp_team AND next_order=CASE WHEN dp_case='TIME' THEN 3 ELSE 2 END)
            OR NOT EXISTS (SELECT FROM public.swl_game_events WHERE game_id=fixture
                AND version=dp_version+2 AND event_type='UNDO_OUT'
                AND event_data->>'reverts_version'=(dp_version+1)::text)
            OR (dp_case='AUTO' AND NOT EXISTS (SELECT FROM public.swl_v56_match_decisions
                WHERE game_id=fixture AND version=dp_version+1 AND action='AUTO'))
          THEN RAISE EXCEPTION 'Restauración incompleta del DP: %',dp_case; END IF;
          BEGIN
            PERFORM public.swl_v57_undo_last_out(fixture,dp_version+2);
            RAISE SQLSTATE 'ZX011' USING MESSAGE='Se deshizo el mismo DP dos veces';
          EXCEPTION WHEN raise_exception THEN
            IF SQLERRM NOT IN ('ONLY_LAST_SIMPLE_OUT_CAN_BE_UNDONE','GAME_STATE_CHANGED') THEN RAISE; END IF;
          END;
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
