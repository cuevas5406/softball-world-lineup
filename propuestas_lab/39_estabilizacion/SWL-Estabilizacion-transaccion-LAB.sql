-- Destino exclusivo: Supabase LAB wgeziptdoabyicufnrfk.
-- Ejecutar como un lote PostgreSQL. Un error impide el COMMIT.
-- Verificar el proyecto y el SHA-256 antes de enviar.
BEGIN;
SET LOCAL lock_timeout='5s';
LOCK TABLE public.swl_live_games IN ACCESS EXCLUSIVE MODE;
SELECT id FROM public.swl_live_games WHERE game_pin='SWL-378859' FOR SHARE;
CREATE TEMP VIEW swl_v57_integridad AS
SELECT g.id, md5((to_jsonb(g)-ARRAY['swl_knockout_mode','swl_knockout_pending',
                        'swl_knockout_waived_through'])::text) AS partido,
 (SELECT md5(jsonb_agg(to_jsonb(e) ORDER BY e.id)::text)
   FROM public.swl_game_events e WHERE e.game_id=g.id) AS historial,
 (SELECT md5(jsonb_agg(to_jsonb(l) ORDER BY l.team_id)::text)
   FROM public.swl_game_lineups l WHERE l.game_id=g.id) AS alineaciones,
 (SELECT md5(jsonb_agg(to_jsonb(p) ORDER BY p.version,p.pitcher_id)::text)
   FROM public.swl_v56_pitching_events p WHERE p.game_id=g.id) AS pitcheo,
 (SELECT md5(jsonb_agg(to_jsonb(c) ORDER BY c.version,c.team_id)::text)
   FROM public.swl_v56_pitcher_changes c WHERE c.game_id=g.id) AS cambios,
 (SELECT md5(jsonb_agg(to_jsonb(t) ORDER BY t.team_id)::text)
   FROM public.swl_game_batting_turns t WHERE t.game_id=g.id) AS turnos,
 (SELECT md5(jsonb_agg(to_jsonb(d) ORDER BY d.id)::text)
   FROM public.swl_v56_match_decisions d WHERE d.game_id=g.id) AS decisiones
FROM public.swl_live_games g WHERE g.game_pin='SWL-378859';
CREATE TEMP TABLE swl_v57_funciones ON COMMIT DROP AS
SELECT oid, proowner, proacl, prosecdef, proconfig, pg_get_functiondef(oid) AS definition
FROM pg_proc WHERE oid IN (
  'public.swl_v56_close_after_play(public.swl_live_games)'::regprocedure,
  'public.swl_v57_defensive_error(uuid,bigint,text,uuid,jsonb)'::regprocedure,
  'public.swl_v57_double_play(uuid,bigint,integer)'::regprocedure,
  'public.swl_v57_double_play_advanced(uuid,bigint,integer,jsonb,text)'::regprocedure,
  'swl_private.v57_undo_dp(public.swl_live_games,public.swl_game_events,uuid)'::regprocedure
);
DO $preflight$
BEGIN
 IF (SELECT count(*) FROM pg_temp.swl_v57_integridad)<>1
   OR (SELECT count(*) FROM pg_temp.swl_v57_funciones)<>5
   OR NOT EXISTS (SELECT FROM pg_publication_tables
     WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='swl_live_games')
 THEN RAISE EXCEPTION 'Falta partido, función o publicación de LAB'; END IF;
END $preflight$;

CREATE TEMP TABLE swl_v57_huellas ON COMMIT DROP AS SELECT * FROM pg_temp.swl_v57_integridad;

-- Desacoplar el almacenamiento histórico del tipo de fila del partido.
LOCK TABLE swl_private.v57_dp_undo_state IN ACCESS EXCLUSIVE MODE;
DO $dp_preflight$
BEGIN
 IF NOT EXISTS (SELECT FROM pg_attribute
  WHERE attrelid='swl_private.v57_dp_undo_state'::regclass AND attname='prior'
    AND atttypid='public.swl_live_games'::regtype AND NOT attisdropped)
 THEN RAISE EXCEPTION 'Tipo inesperado en el snapshot histórico de DP'; END IF;
 IF EXISTS (
   SELECT FROM (VALUES
     ('public.swl_v57_double_play(uuid,bigint,integer)','e2dd9eeadb775524e4899189b6848c1e'),
     ('public.swl_v57_double_play_advanced(uuid,bigint,integer,jsonb,text)','ba853729bcdac68139d22816d35191f9'),
     ('swl_private.v57_undo_dp(public.swl_live_games,public.swl_game_events,uuid)','ad22b39c084a0efb7b88fa725c7247e6')
   ) x(signature,fingerprint)
   WHERE md5(pg_get_functiondef(to_regprocedure(x.signature))) IS DISTINCT FROM x.fingerprint
 ) THEN RAISE EXCEPTION 'Cambió una función de DP desde la auditoría de LAB'; END IF;
END $dp_preflight$;
CREATE TEMP TABLE swl_v57_dp_original ON COMMIT DROP AS
 SELECT game_id,version,to_jsonb(s) AS payload FROM swl_private.v57_dp_undo_state s;
CREATE TEMP TABLE swl_v57_dp_acl ON COMMIT DROP AS
 SELECT relowner,relacl,relrowsecurity,relforcerowsecurity
 FROM pg_class WHERE oid='swl_private.v57_dp_undo_state'::regclass;
ALTER TABLE swl_private.v57_dp_undo_state
 ALTER COLUMN prior TYPE jsonb USING to_jsonb(prior),
 ADD COLUMN snapshot_schema smallint NOT NULL DEFAULT 1,
 ADD CONSTRAINT v57_dp_snapshot_schema_check CHECK (snapshot_schema IN (1,2)),
 ADD CONSTRAINT v57_dp_snapshot_shape_check CHECK (jsonb_typeof(prior)='object');
ALTER TABLE swl_private.v57_dp_undo_state ALTER COLUMN snapshot_schema DROP DEFAULT;
DO $dp_dependencies$
BEGIN
 IF EXISTS (
   WITH RECURSIVE types(oid) AS (
     SELECT 'public.swl_live_games'::regtype::oid
     UNION SELECT t.oid FROM pg_type t JOIN types x ON t.typelem=x.oid OR t.typbasetype=x.oid
   )
   SELECT FROM pg_attribute a JOIN types t ON t.oid=a.atttypid
    JOIN pg_class c ON c.oid=a.attrelid
   WHERE a.attnum>0 AND NOT a.attisdropped AND c.relkind IN ('r','p','m','f','c')
 ) THEN RAISE EXCEPTION 'Queda una dependencia material del tipo de partido'; END IF;
END $dp_dependencies$;

-- Propuesta para LAB. No ejecutar sin autorización.
ALTER TABLE public.swl_live_games
  ADD COLUMN swl_knockout_mode text NOT NULL DEFAULT 'AUTO'
    CHECK (swl_knockout_mode IN ('AUTO','CONSULT','DISABLED')),
  ADD COLUMN swl_knockout_waived_through integer NOT NULL DEFAULT 0,
  ADD COLUMN swl_knockout_pending jsonb;
CREATE TABLE swl_private.v57_knockout_audit (
 game_id uuid NOT NULL REFERENCES public.swl_live_games(id),
 version bigint NOT NULL,
 actor_id uuid NOT NULL,
 action text NOT NULL CHECK (action IN ('PENDING','CONTINUE','FINISH')),
 PRIMARY KEY(game_id,version)
);
ALTER TABLE swl_private.v57_knockout_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON swl_private.v57_knockout_audit FROM PUBLIC, anon, authenticated;

CREATE FUNCTION swl_private.v57_guard_knockout_pending()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $guard$
BEGIN
 IF OLD.swl_knockout_pending IS NOT NULL
    AND NEW.swl_knockout_pending IS NOT DISTINCT FROM OLD.swl_knockout_pending
    AND NEW IS DISTINCT FROM OLD
 THEN RAISE EXCEPTION 'KNOCKOUT_DECISION_PENDING'; END IF;
 RETURN NEW;
END;
$guard$;
REVOKE ALL ON FUNCTION swl_private.v57_guard_knockout_pending() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER swl_v57_wait_knockout BEFORE UPDATE ON public.swl_live_games
 FOR EACH ROW EXECUTE FUNCTION swl_private.v57_guard_knockout_pending();

CREATE FUNCTION public.swl_v57_knockout_decision(p_game_id uuid,p_expected_version bigint,p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $vote$
DECLARE g public.swl_live_games%ROWTYPE; actor uuid:=auth.uid(); is_home boolean;
 pending jsonb; vote_key text; done boolean;
BEGIN
 SELECT * INTO g FROM public.swl_live_games WHERE id=p_game_id FOR UPDATE;
 IF NOT FOUND OR actor IS NULL OR
   (actor IS DISTINCT FROM g.home_manager_id AND actor IS DISTINCT FROM g.away_manager_id)
 THEN RAISE EXCEPTION 'KNOCKOUT_MANAGER_REQUIRED' USING ERRCODE='42501'; END IF;
 is_home:=actor=g.home_manager_id;
 IF public.swl_can_manage_roster(CASE WHEN is_home THEN g.home_team_id ELSE g.away_team_id END) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'KNOCKOUT_MANAGER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF g.version IS DISTINCT FROM p_expected_version THEN RAISE EXCEPTION 'STALE_VERSION'; END IF;
 IF g.status='SCHEDULED' AND is_home AND p_action IN ('AUTO','CONSULT','DISABLED') THEN
   UPDATE public.swl_live_games SET swl_knockout_mode=p_action,version=g.version+1 WHERE id=g.id;
   RETURN;
 END IF;
 pending:=g.swl_knockout_pending;
 IF g.status<>'IN_PROGRESS' OR pending IS NULL OR p_action IS NULL OR p_action NOT IN ('CONTINUE','FINISH')
 THEN RAISE EXCEPTION 'KNOCKOUT_DECISION_NOT_AVAILABLE'; END IF;
 vote_key:=CASE WHEN is_home THEN 'home_continue' ELSE 'away_continue' END;
 IF pending->vote_key='true'::jsonb THEN RAISE EXCEPTION 'KNOCKOUT_ALREADY_VOTED'; END IF;
 IF p_action='FINISH' THEN
   UPDATE public.swl_live_games SET status='FINAL',swl_finish_reason=pending->>'reason',
     inning=(pending->>'inning')::integer,is_top=(pending->>'top')::boolean,
     swl_final_half_completed=(pending->>'half_ended')::boolean,
     swl_knockout_pending=NULL,version=g.version+1 WHERE id=g.id;
 ELSE
   pending:=jsonb_set(pending,ARRAY[vote_key],'true'::jsonb);
   done:=pending->'home_continue'='true'::jsonb AND pending->'away_continue'='true'::jsonb;
   UPDATE public.swl_live_games SET
     swl_knockout_pending=CASE WHEN done THEN NULL ELSE pending END,
     swl_knockout_waived_through=CASE WHEN done THEN (pending->>'inning')::integer ELSE g.swl_knockout_waived_through END,
     version=g.version+1 WHERE id=g.id;
 END IF;
 INSERT INTO swl_private.v57_knockout_audit(game_id,version,actor_id,action)
 VALUES(g.id,g.version+1,actor,p_action);
END;
$vote$;
REVOKE ALL ON FUNCTION public.swl_v57_knockout_decision(uuid,bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.swl_v57_knockout_decision(uuid,bigint,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.swl_v56_close_after_play(prior swl_live_games)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 latest public.swl_live_games%rowtype;
 half_ended boolean;
 lead integer;
 threshold integer;
 reason text;
BEGIN
 SELECT * INTO STRICT latest FROM public.swl_live_games WHERE id=prior.id FOR UPDATE;
 IF latest.version IS DISTINCT FROM prior.version+1 THEN RAISE EXCEPTION 'La jugada no generó la versión esperada.'; END IF;
 IF latest.status::text IS DISTINCT FROM 'IN_PROGRESS' THEN RETURN; END IF;
 IF prior.is_top IS NULL OR latest.is_top IS NULL OR prior.inning IS NULL OR latest.inning IS NULL THEN RAISE EXCEPTION 'No se pudo identificar la media entrada.'; END IF;
 half_ended := latest.is_top <> prior.is_top;
 IF latest.inning <> prior.inning+(CASE WHEN half_ended AND NOT prior.is_top THEN 1 ELSE 0 END) THEN RAISE EXCEPTION 'Transición de media entrada incompatible con el marcador.'; END IF;
 lead := latest.home_runs-latest.away_runs;
 threshold := CASE WHEN prior.inning=3 THEN latest.swl_super_margin WHEN prior.inning>=4 THEN latest.swl_knockout_margin ELSE NULL END;
 IF coalesce(threshold,0)>0 AND
 latest.swl_knockout_mode <> 'DISABLED' AND prior.inning > latest.swl_knockout_waived_through AND
 (CASE WHEN prior.is_top THEN half_ended AND lead>=threshold
 ELSE lead>=threshold OR (half_ended AND lead<=-threshold) END) AND
 (latest.swl_knockout_waived_through=0 OR (half_ended AND NOT prior.is_top)) THEN
  reason := CASE WHEN prior.inning=3 THEN 'Súper knockout' ELSE 'Knockout' END;
 ELSIF prior.inning>=latest.swl_regulation_innings THEN
  IF (prior.is_top AND half_ended AND lead>0)
  OR (NOT prior.is_top AND (lead>0 OR (half_ended AND lead<0))) THEN
   reason := 'Final reglamentario';
  END IF;
 END IF;
 IF reason IN ('Súper knockout','Knockout') AND latest.swl_knockout_mode='CONSULT' THEN
  UPDATE public.swl_live_games SET swl_knockout_pending=jsonb_build_object(
    'reason',reason,'inning',prior.inning,'top',prior.is_top,'half_ended',half_ended,
    'difference',abs(lead),'home_continue',false,'away_continue',false),
    swl_finish_requested_by=NULL WHERE id=prior.id;
  IF latest.swl_finish_requested_by IS NOT NULL THEN
    INSERT INTO public.swl_v56_match_decisions(game_id,version,action,actor_id)
    VALUES(prior.id,latest.version,'INVALIDATED',auth.uid());
  END IF;
  INSERT INTO swl_private.v57_knockout_audit(game_id,version,actor_id,action)
    VALUES(prior.id,latest.version,auth.uid(),'PENDING');
  RETURN;
 END IF;
 IF reason IS NOT NULL THEN
  UPDATE public.swl_live_games SET status='FINAL',inning=prior.inning,is_top=prior.is_top,
   swl_finish_reason=reason,swl_final_half_completed=half_ended,swl_finish_requested_by=NULL WHERE id=prior.id;
  INSERT INTO public.swl_v56_match_decisions(game_id,version,action,actor_id)
   VALUES(prior.id,latest.version,'AUTO',auth.uid());
 ELSIF latest.swl_finish_requested_by IS NOT NULL THEN
  UPDATE public.swl_live_games SET swl_finish_requested_by=NULL WHERE id=prior.id;
  INSERT INTO public.swl_v56_match_decisions(game_id,version,action,actor_id)
   VALUES(prior.id,latest.version,'INVALIDATED',auth.uid());
 END IF;
END $function$;

-- Propuesta LAB sin ejecutar.
CREATE OR REPLACE FUNCTION public.swl_v57_defensive_error(p_game_id uuid, p_expected_version bigint, p_action text, p_batter_id uuid, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 g public.swl_live_games%ROWTYPE; lineup jsonb; team uuid; pitcher uuid; batting_order integer;
 bbase integer; moves integer[]:=ARRAY[NULL,NULL,NULL]::integer[]; occ boolean[]; players uuid[];
 new_players uuid[]:=ARRAY[NULL,NULL,NULL]::uuid[]; new_occ boolean[]:=ARRAY[false,false,false];
 i integer; d integer; target integer; last_target integer; outs_made integer:=0; scored integer:=0;
 scoring_players uuid[]:=ARRAY[]::uuid[];
 terminal boolean:=false; retired_source integer;
 retired_players uuid[]:=ARRAY[]::uuid[]; forced_out boolean:=false; confirmed_timing boolean:=false;
 new_bases jsonb; new_innings jsonb; new_home integer; new_away integer; result jsonb;
BEGIN
 IF p_action IS DISTINCT FROM 'ERROR' OR p_data IS NULL OR jsonb_typeof(p_data)<>'object' THEN
   RAISE EXCEPTION 'V57_COMPLEX_PLAY_NOT_ENABLED'; END IF;
 IF p_batter_id IS NULL OR p_data->>'p_batter_id' IS DISTINCT FROM p_batter_id::text THEN
   RAISE EXCEPTION 'BATTER_ID_MISMATCH'; END IF;
 IF coalesce(p_data->>'p_batter_base','') !~ '^[1-3]$' THEN RAISE EXCEPTION 'INVALID_BATTER_BASE'; END IF;
 bbase:=(p_data->>'p_batter_base')::integer;
 FOR i IN 1..3 LOOP
   IF p_data->(ARRAY['p_first_to','p_second_to','p_third_to'])[i] IS NOT NULL
      AND p_data->>(ARRAY['p_first_to','p_second_to','p_third_to'])[i] IS NOT NULL THEN
      IF p_data->>(ARRAY['p_first_to','p_second_to','p_third_to'])[i] !~ '^-?[0-9]+$' THEN
        RAISE EXCEPTION 'INVALID_RUNNER_DESTINATION'; END IF;
      moves[i]:=(p_data->>(ARRAY['p_first_to','p_second_to','p_third_to'])[i])::integer;
   END IF;
 END LOOP;
 IF p_data ? 'count_runs_on_third_out' AND jsonb_typeof(p_data->'count_runs_on_third_out') <> 'boolean' THEN
   RAISE EXCEPTION 'INVALID_TIMING_CONFIRMATION'; END IF;
 confirmed_timing:=coalesce((p_data->>'count_runs_on_third_out')::boolean,false);
 outs_made:=(SELECT count(*) FROM unnest(moves) x WHERE x<0);
 g:=public.swl_v56_lock_batting_turn(p_game_id,p_expected_version);
 IF g.outs+outs_made>3 THEN RAISE EXCEPTION 'INVALID_OUT_COUNT'; END IF;
 terminal:=g.outs+outs_made=3;
 IF terminal AND outs_made>1 THEN
   IF coalesce(p_data->>'p_last_out_source','') !~ '^[1-3]$' THEN
     RAISE EXCEPTION 'LAST_OUT_REQUIRED';
   END IF;
   retired_source:=(p_data->>'p_last_out_source')::integer;
   IF moves[retired_source] IS NULL OR moves[retired_source]>=0 THEN
     RAISE EXCEPTION 'INVALID_LAST_OUT';
   END IF;
 ELSIF outs_made=1 THEN
   SELECT x.origin INTO retired_source
   FROM unnest(moves) WITH ORDINALITY AS x(destination,origin) WHERE x.destination<0;
 END IF;
 team:=CASE WHEN g.is_top THEN g.away_team_id ELSE g.home_team_id END;
 SELECT l.lineup INTO lineup FROM public.swl_game_lineups l WHERE l.game_id=g.id AND l.team_id=team;
 IF lineup IS NULL OR jsonb_typeof(lineup)<>'array' OR jsonb_array_length(lineup) NOT BETWEEN 9 AND 13 THEN
 RAISE EXCEPTION 'LINEUP_REQUIRED'; END IF;
 SELECT next_order INTO batting_order FROM public.swl_game_batting_turns WHERE game_id=g.id AND team_id=team FOR UPDATE;
 batting_order:=coalesce(batting_order,1);
 IF batting_order NOT BETWEEN 1 AND jsonb_array_length(lineup)
 OR lineup->(batting_order-1)->>'player_id' IS DISTINCT FROM p_batter_id::text THEN
 RAISE EXCEPTION 'WRONG_BATTER_TURN'; END IF;
 occ:=public.swl_v56_base_occupancy(g.bases_state);
 players:=g.swl_base_players;
 PERFORM public.swl_v56_validate_base_players(occ,players);
 IF p_batter_id=ANY(players) THEN RAISE EXCEPTION 'BATTER_ALREADY_ON_BASE'; END IF;
 last_target:=bbase;
 FOR i IN 1..3 LOOP
   d:=moves[i];
   IF occ[i] IS DISTINCT FROM (d IS NOT NULL) THEN RAISE EXCEPTION 'RUNNER_DESTINATIONS_REQUIRED'; END IF;
   IF d IS NOT NULL THEN
     IF (i=1 AND d NOT IN (0,2,3,-1,-2,-3,-4))
     OR (i=2 AND d NOT IN (0,2,3,-2,-3,-4))
     OR (i=3 AND d NOT IN (0,3,-3,-4)) THEN RAISE EXCEPTION 'INVALID_RUNNER_DESTINATION'; END IF;
     IF d<0 THEN
       retired_players:=array_append(retired_players,players[i]);
       IF -d<i THEN RAISE EXCEPTION 'INVALID_OUT_BASE'; END IF;
     ELSE
       target:=CASE WHEN d=0 THEN 4 ELSE d END;
       IF target<last_target OR (target=last_target AND target<>4) THEN
         RAISE EXCEPTION 'RUNNER_ORDER_INVALID'; END IF;
       last_target:=target;
       IF d=0 THEN
         scored:=scored+1;
         scoring_players:=array_append(scoring_players,players[i]);
       ELSE
         IF new_occ[d] THEN RAISE EXCEPTION 'DUPLICATE_OCCUPIED_BASE'; END IF;
         new_occ[d]:=true;new_players[d]:=players[i];
       END IF;
     END IF;
   END IF;
 END LOOP;
 IF new_occ[bbase] THEN RAISE EXCEPTION 'BATTER_BASE_OCCUPIED'; END IF;
 new_occ[bbase]:=true;new_players[bbase]:=p_batter_id;
 IF terminal THEN
   forced_out := moves[retired_source] = -(retired_source+1)
     AND NOT EXISTS (SELECT FROM generate_series(1,retired_source-1) src(origin)
       WHERE moves[src.origin] IS NULL OR moves[src.origin]<0);
   scored:=0;
   scoring_players:=ARRAY[]::uuid[];
   IF confirmed_timing AND NOT forced_out THEN
     FOR i IN (retired_source+1)..3 LOOP
       IF moves[i]=0 THEN
         scored:=scored+1;
         scoring_players:=array_append(scoring_players,players[i]);
       END IF;
     END LOOP;
   END IF;
   new_occ:=ARRAY[false,false,false];
   new_players:=ARRAY[null,null,null]::uuid[];
 END IF;
 new_bases:=jsonb_build_object('first',new_occ[1],'second',new_occ[2],'third',new_occ[3]);
 PERFORM public.swl_v56_validate_base_players(new_occ,new_players);
 new_home:=g.home_runs+(CASE WHEN g.is_top THEN 0 ELSE scored END);
 new_away:=g.away_runs+(CASE WHEN g.is_top THEN scored ELSE 0 END);
 IF scored>0 THEN
   result:=public.swl_v53_inning_delta(g.home_innings,g.away_innings,g.inning,g.is_top,g.home_runs,g.away_runs,new_home,new_away);
 ELSE
   result:=jsonb_build_object('home_innings',g.home_innings,'away_innings',g.away_innings);
 END IF;
 SELECT pitcher_id INTO pitcher FROM public.swl_game_lineups WHERE game_id=g.id AND team_id=
   (CASE WHEN g.is_top THEN g.home_team_id ELSE g.away_team_id END);
 UPDATE public.swl_live_games SET
  outs=CASE WHEN terminal THEN 0 ELSE g.outs+outs_made END,
  inning=g.inning+CASE WHEN terminal AND NOT g.is_top THEN 1 ELSE 0 END,
  is_top=CASE WHEN terminal THEN NOT g.is_top ELSE g.is_top END,
  balls=0,strikes=0,
  home_runs=new_home,away_runs=new_away,
  home_errors=g.home_errors+(CASE WHEN g.is_top THEN 1 ELSE 0 END),
  away_errors=g.away_errors+(CASE WHEN g.is_top THEN 0 ELSE 1 END),
  home_innings=result->'home_innings',away_innings=result->'away_innings',
  bases_state=new_bases,version=g.version+1,updated_at=now()
 WHERE id=g.id;
 UPDATE public.swl_live_games SET swl_base_players=new_players,
  swl_ghost_player=CASE WHEN g.swl_ghost_player=ANY(new_players) THEN g.swl_ghost_player END WHERE id=g.id;
 INSERT INTO public.swl_game_batting_turns(game_id,team_id,next_order,updated_at)
 VALUES(g.id,team,(batting_order % jsonb_array_length(lineup))+1,now())
 ON CONFLICT(game_id,team_id) DO UPDATE SET next_order=excluded.next_order,updated_at=excluded.updated_at;
 INSERT INTO public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
 VALUES(g.id,(SELECT auth.uid()),team,g.inning,g.is_top,'ERROR',
 jsonb_build_object('scope','defensive_error','pitcher_id',pitcher,'plate_appearance_completed',true,'previous_version',g.version,'batter_id',p_batter_id,
 'batting_order',batting_order,'batter_base',bbase,'first_to',moves[1],'second_to',moves[2],
 'third_to',moves[3],'outs_added',outs_made,'runs',scored,'scoring_player_ids',to_jsonb(scoring_players),'rbi',0,
 'third_out',terminal,'out_at_base',-moves[retired_source],
 'out_runner_id',players[retired_source]::text,'out_runner_ids',to_jsonb(retired_players),
 'last_out_source',CASE WHEN terminal THEN retired_source END),g.version+1);
 IF pitcher IS NULL THEN RAISE EXCEPTION 'PITCHER_REQUIRED'; END IF;
 PERFORM public.swl_v56_accumulate_pitching(g,pitcher,'OUT'); -- Contacto sin hit ni ponche.
 PERFORM public.swl_v56_close_after_play(g);
 RETURN jsonb_build_object('id',g.id,'version',g.version+1,'action','ERROR','runs',scored,'outs_added',outs_made,'third_out',terminal,'bases',new_bases);
END $function$;

-- Superficie de lectura para el Box Score del fanático.
CREATE FUNCTION public.swl_v57_spectator_box_source(p_game_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $source$
  WITH lineups AS (
    SELECT jsonb_build_object('team_id', l.team_id, 'pitcher_id', l.pitcher_id,
      'defensive_positions', l.defensive_positions,
      'designated_hitter_id', l.designated_hitter_id,
      'lineup', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'player_id',s.slot->'player_id','order',s.slot->'order',
        'batting_order',s.slot->'batting_order','batting_role',s.slot->'batting_role')
        ORDER BY s.ord),'[]'::jsonb)
        FROM jsonb_array_elements(l.lineup) WITH ORDINALITY AS s(slot,ord))) AS data, l.team_id
    FROM public.swl_game_lineups l WHERE l.game_id=p_game_id
  ), events AS (
    SELECT e.id, e.version, jsonb_build_object('version', e.version,
             'inning', e.inning,
             'is_top', e.is_top,
             'batting_team_id', e.batting_team_id,
             'event_type', e.event_type,
       'event_data', (SELECT coalesce(jsonb_object_agg(f.key,f.value),'{}'::jsonb)
         FROM jsonb_each(CASE WHEN jsonb_typeof(e.event_data)='object'
              THEN e.event_data ELSE '{}'::jsonb END) f
         WHERE f.key IN ('advance_cause', 'batter_base', 'batter_id', 'incoming_player_id', 'outgoing_player_id', 'out_runner_id', 'out_runner_ids', 'outs', 'outs_added', 'pitcher_id', 'plate_appearance_completed', 'player_id', 'rbi', 'reverts_version', 'runner_id', 'runs', 'scope', 'scoring_player_ids'))) AS data
    FROM public.swl_game_events e WHERE e.game_id=p_game_id
  ), changes AS (
    SELECT c.version, c.team_id, jsonb_build_object('version', c.version,
             'team_id', c.team_id,
             'old_pitcher_id', c.old_pitcher_id,
             'new_pitcher_id', c.new_pitcher_id) AS data
    FROM public.swl_v56_pitcher_changes c WHERE c.game_id=p_game_id
  ), pitches AS (
    SELECT p.version, p.pitcher_id, jsonb_build_object('version', p.version,
             'pitcher_id', p.pitcher_id,
             'outs', p.outs,
             'hits', p.hits,
             'walks', p.walks,
             'strikes_out', p.strikes_out,
             'pitch_count', to_jsonb(p)->'pitch_count',
             'pitch_balls', to_jsonb(p)->'pitch_balls',
             'pitch_strikes', to_jsonb(p)->'pitch_strikes',
             'pitch_in_play', to_jsonb(p)->'pitch_in_play') AS data
    FROM public.swl_v56_pitching_events p WHERE p.game_id=p_game_id
  ), player_ids AS (
    SELECT slot->>'player_id' AS id
      FROM lineups l CROSS JOIN LATERAL jsonb_array_elements(l.data->'lineup') AS slot
    UNION SELECT jsonb_object_keys(CASE
      WHEN jsonb_typeof(data->'defensive_positions')='object'
        THEN data->'defensive_positions' ELSE '{}'::jsonb END) FROM lineups
    UNION SELECT data->>'designated_hitter_id' FROM lineups
    UNION SELECT data->>'pitcher_id' FROM lineups
    UNION SELECT data->>'old_pitcher_id' FROM changes
    UNION SELECT data->>'new_pitcher_id' FROM changes
    UNION SELECT pitcher_id::text FROM pitches
    UNION SELECT data->'event_data'->>'batter_id' FROM events
    UNION SELECT data->'event_data'->>'incoming_player_id' FROM events
    UNION SELECT data->'event_data'->>'outgoing_player_id' FROM events
    UNION SELECT scorer FROM events e CROSS JOIN LATERAL jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(e.data->'event_data'->'scoring_player_ids')='array'
        THEN e.data->'event_data'->'scoring_player_ids' ELSE '[]'::jsonb END) AS scorer
  )
  SELECT jsonb_build_object(
    'game', jsonb_build_object('id', g.id,
             'game_pin', g.game_pin,
             'status', g.status,
             'created_at', g.created_at,
             'version', g.version,
             'inning', g.inning,
             'is_top', g.is_top,
             'swl_finish_reason', g.swl_finish_reason,
             'swl_regulation_innings', g.swl_regulation_innings,
             'home_team_id', g.home_team_id,
             'away_team_id', g.away_team_id,
             'home_runs', g.home_runs,
             'away_runs', g.away_runs,
             'home_hits', g.home_hits,
             'away_hits', g.away_hits,
             'home_errors', g.home_errors,
             'away_errors', g.away_errors,
             'home_innings', g.home_innings,
             'away_innings', g.away_innings),
    'lineups', (SELECT coalesce(jsonb_agg(l.data ORDER BY l.team_id),'[]'::jsonb) FROM lineups l),
    'events', (SELECT coalesce(jsonb_agg(e.data ORDER BY e.version,e.id),'[]'::jsonb)
               FROM events e WHERE e.version<=g.version),
    'changes', (SELECT coalesce(jsonb_agg(c.data ORDER BY c.version,c.team_id),'[]'::jsonb)
                FROM changes c WHERE c.version<=g.version),
    'pitches', (SELECT coalesce(jsonb_agg(p.data ORDER BY p.version,p.pitcher_id),'[]'::jsonb)
                FROM pitches p WHERE p.version<=g.version),
    'players', (SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,
      'first_name',p.first_name,'last_name',p.last_name,'jersey_number',p.jersey_number) ORDER BY p.id),'[]'::jsonb)
      FROM player_ids i JOIN public.players p ON p.id=CASE
        WHEN i.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' THEN i.id::uuid END)
  )
  FROM public.swl_live_games g
  WHERE g.id=p_game_id AND (SELECT auth.uid()) IS NOT NULL
    AND g.status IN ('IN_PROGRESS','FINAL','OFFICIAL');
$source$;
REVOKE ALL ON FUNCTION public.swl_v57_spectator_box_source(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.swl_v57_spectator_box_source(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.swl_v57_double_play(p_game_id uuid, p_expected_version bigint, p_source integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE g public.swl_live_games%ROWTYPE; team uuid; lineup jsonb; turn_number integer; batter uuid; runner uuid; new_outs integer; new_inning integer; new_top boolean; pitcher uuid; occupied boolean[];
BEGIN
 IF p_source IS NULL OR p_source NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'INVALID_RUNNER_SOURCE'; END IF;
 g:=public.swl_v56_lock_batting_turn(p_game_id,p_expected_version);
 IF g.outs>1 THEN RAISE EXCEPTION 'DOUBLE_PLAY_REQUIRES_FEWER_THAN_TWO_OUTS'; END IF;
 occupied:=public.swl_v56_base_occupancy(g.bases_state);
 IF occupied[p_source] IS DISTINCT FROM true THEN RAISE EXCEPTION 'RUNNER_NOT_ON_BASE'; END IF;
 IF (SELECT count(*) FROM unnest(occupied) x WHERE x)=1 IS NOT TRUE THEN RAISE EXCEPTION 'DOUBLE_PLAY_OTHER_RUNNERS_NOT_SUPPORTED'; END IF;
 PERFORM public.swl_v56_validate_base_players(occupied,g.swl_base_players);
 runner:=g.swl_base_players[p_source];
 team:=CASE WHEN g.is_top THEN g.away_team_id ELSE g.home_team_id END;
 SELECT l.lineup INTO lineup FROM public.swl_game_lineups l WHERE l.game_id=g.id AND l.team_id=team;
 IF lineup IS NULL OR jsonb_typeof(lineup)<>'array' OR jsonb_array_length(lineup) NOT BETWEEN 9 AND 13 THEN RAISE EXCEPTION 'LINEUP_REQUIRED'; END IF;
 SELECT next_order INTO turn_number FROM public.swl_game_batting_turns WHERE game_id=g.id AND team_id=team FOR UPDATE;
 IF turn_number IS NULL OR turn_number NOT BETWEEN 1 AND jsonb_array_length(lineup) THEN RAISE EXCEPTION 'INVALID_BATTING_TURN'; END IF;
 batter:=(lineup->(turn_number-1)->>'player_id')::uuid;
 IF batter IS NULL OR batter=runner THEN RAISE EXCEPTION 'INVALID_BATTER'; END IF;
 new_outs:=g.outs+2;new_top:=g.is_top;new_inning:=g.inning;
 IF new_outs=3 THEN
   new_outs:=0;
   IF g.is_top THEN new_top:=false; ELSE new_top:=true;new_inning:=g.inning+1; END IF;
 END IF;
 INSERT INTO swl_private.v57_dp_undo_state(game_id,version,prior,cursor_before,runner_identity,snapshot_schema)
 VALUES(g.id,g.version+1,to_jsonb(g),(SELECT next_order FROM public.swl_game_batting_turns WHERE game_id=g.id AND team_id=team),
   (SELECT to_jsonb(r) FROM public.swl_v56_runner_identity r WHERE r.game_id=g.id),2);
 UPDATE public.swl_live_games SET outs=new_outs,balls=0,strikes=0,inning=new_inning,is_top=new_top,
 bases_state='{"first":false,"second":false,"third":false}'::jsonb,
 swl_base_players=ARRAY[NULL,NULL,NULL]::uuid[],swl_ghost_player=NULL,
 version=g.version+1,updated_at=now() WHERE id=g.id;
 UPDATE public.swl_game_batting_turns SET next_order=CASE WHEN turn_number=jsonb_array_length(lineup) THEN 1 ELSE turn_number+1 END,updated_at=now()
 WHERE game_id=g.id AND team_id=team;
 SELECT pitcher_id INTO pitcher FROM public.swl_game_lineups WHERE game_id=g.id AND team_id=(CASE WHEN g.is_top THEN g.home_team_id ELSE g.away_team_id END);
 INSERT INTO public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
 VALUES(g.id,auth.uid(),team,g.inning,g.is_top,'DOUBLE_PLAY',
 jsonb_build_object('scope','double_play','pitcher_id',pitcher,'previous_version',g.version,'batter_id',batter,'runner_id',runner,
 'source',p_source,'outs_added',2,'batting_order',turn_number,'runs',0),g.version+1);

 PERFORM public.swl_v56_accumulate_pitching(g,pitcher,'OUT');
 PERFORM public.swl_v56_close_after_play(g);
 RETURN jsonb_build_object('id',g.id,'version',g.version+1,'action','DOUBLE_PLAY','outs_added',2,'half_ended',g.outs=1);
END $function$;

CREATE OR REPLACE FUNCTION public.swl_v57_double_play_advanced(p_game_id uuid, p_expected_version bigint, p_source integer, p_advances jsonb, p_third_out text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

DECLARE g public.swl_live_games%ROWTYPE; team uuid; lineup jsonb; turn_number integer; batter uuid; runner uuid; new_outs integer; new_inning integer; new_top boolean; pitcher uuid; occupied boolean[]; i integer; dest integer; previous integer:=4; normalized integer;
 moved uuid[]:=array[null,null,null]::uuid[]; scorers uuid[]:=array[]::uuid[]; runs integer; half_ended boolean;
BEGIN
 IF p_source IS NULL OR p_source NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'INVALID_RUNNER_SOURCE'; END IF;
 g:=public.swl_v56_lock_batting_turn(p_game_id,p_expected_version);
 IF g.outs>1 THEN RAISE EXCEPTION 'DOUBLE_PLAY_REQUIRES_FEWER_THAN_TWO_OUTS'; END IF;
 occupied:=public.swl_v56_base_occupancy(g.bases_state);
 IF occupied[p_source] IS DISTINCT FROM true THEN RAISE EXCEPTION 'RUNNER_NOT_ON_BASE'; END IF;

 PERFORM public.swl_v56_validate_base_players(occupied,g.swl_base_players);
 runner:=g.swl_base_players[p_source];
 team:=CASE WHEN g.is_top THEN g.away_team_id ELSE g.home_team_id END;
 SELECT l.lineup INTO lineup FROM public.swl_game_lineups l WHERE l.game_id=g.id AND l.team_id=team;
 IF lineup IS NULL OR jsonb_typeof(lineup)<>'array' OR jsonb_array_length(lineup) NOT BETWEEN 9 AND 13 THEN RAISE EXCEPTION 'LINEUP_REQUIRED'; END IF;
 SELECT next_order INTO turn_number FROM public.swl_game_batting_turns WHERE game_id=g.id AND team_id=team FOR UPDATE;
 turn_number:=coalesce(turn_number,1);
 IF turn_number NOT BETWEEN 1 AND jsonb_array_length(lineup) THEN RAISE EXCEPTION 'INVALID_BATTING_TURN'; END IF;
 batter:=(lineup->(turn_number-1)->>'player_id')::uuid;
 IF batter IS NULL OR batter=ANY(g.swl_base_players) THEN RAISE EXCEPTION 'INVALID_BATTER'; END IF;
 IF jsonb_typeof(p_advances) IS DISTINCT FROM 'object' THEN
   RAISE EXCEPTION 'INVALID_DOUBLE_PLAY_ADVANCES';
 END IF;
 IF EXISTS (SELECT 1 FROM jsonb_each(p_advances) kv WHERE kv.key NOT IN ('1','2','3')
     OR jsonb_typeof(kv.value)<>'number' OR kv.value::text !~ '^[0-3]$')
 OR p_third_out IS NULL OR p_third_out NOT IN ('FORCE','TIME') THEN
   RAISE EXCEPTION 'INVALID_DOUBLE_PLAY_ADVANCES';
 END IF;
 half_ended:=g.outs=1;
 FOR i IN REVERSE 3..1 LOOP
   dest:=(p_advances->>i::text)::integer;
   IF NOT occupied[i] OR i=p_source THEN
     IF dest IS NOT NULL THEN RAISE EXCEPTION 'INVALID_RUNNER_SOURCE'; END IF;
     CONTINUE;
   END IF;
   IF dest IS NULL THEN dest:=i; END IF;
   normalized:=CASE WHEN dest=0 THEN 4 ELSE dest END;
   IF normalized<i OR normalized>previous OR (normalized=previous AND normalized<>4) THEN
     RAISE EXCEPTION 'INVALID_DOUBLE_PLAY_ADVANCE_ORDER';
   END IF;
   previous:=normalized;
   IF dest=0 THEN
     IF half_ended AND (p_third_out<>'TIME' OR i<p_source) THEN
       RAISE EXCEPTION 'DOUBLE_PLAY_RUN_CANNOT_SCORE_ON_THIRD_OUT';
     END IF;
     scorers:=array_append(scorers,g.swl_base_players[i]);
   ELSE
     moved[dest]:=g.swl_base_players[i];
   END IF;
 END LOOP;
 runs:=cardinality(scorers);
 IF half_ended THEN moved:=array[null,null,null]::uuid[]; END IF;
 new_outs:=g.outs+2;new_top:=g.is_top;new_inning:=g.inning;
 IF new_outs=3 THEN
   new_outs:=0;
   IF g.is_top THEN new_top:=false; ELSE new_top:=true;new_inning:=g.inning+1; END IF;
 END IF;
 INSERT INTO swl_private.v57_dp_undo_state(game_id,version,prior,cursor_before,runner_identity,snapshot_schema)
 VALUES(g.id,g.version+1,to_jsonb(g),(SELECT next_order FROM public.swl_game_batting_turns WHERE game_id=g.id AND team_id=team),
   (SELECT to_jsonb(r) FROM public.swl_v56_runner_identity r WHERE r.game_id=g.id),2);
 UPDATE public.swl_live_games SET outs=new_outs,balls=0,strikes=0,inning=new_inning,is_top=new_top,
 bases_state=jsonb_build_object('first',moved[1] is not null,'second',moved[2] is not null,'third',moved[3] is not null),
 swl_base_players=moved,swl_ghost_player=CASE WHEN g.swl_ghost_player=ANY(moved) THEN g.swl_ghost_player END,
 away_runs=g.away_runs+CASE WHEN g.is_top THEN runs ELSE 0 END,
 home_runs=g.home_runs+CASE WHEN g.is_top THEN 0 ELSE runs END,
 away_innings=CASE WHEN g.is_top THEN public.swl_v56_add_inning_runs(g.away_innings,g.inning,runs) ELSE g.away_innings END,
 home_innings=CASE WHEN g.is_top THEN g.home_innings ELSE public.swl_v56_add_inning_runs(g.home_innings,g.inning,runs) END,
 version=g.version+1,updated_at=now() WHERE id=g.id;
 INSERT INTO public.swl_game_batting_turns(game_id,team_id,next_order,updated_at)
 VALUES(g.id,team,turn_number%jsonb_array_length(lineup)+1,now())
 ON CONFLICT(game_id,team_id) DO UPDATE SET next_order=excluded.next_order,updated_at=excluded.updated_at;
 SELECT pitcher_id INTO pitcher FROM public.swl_game_lineups WHERE game_id=g.id AND team_id=(CASE WHEN g.is_top THEN g.home_team_id ELSE g.away_team_id END);
 INSERT INTO public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
 VALUES(g.id,auth.uid(),team,g.inning,g.is_top,'DOUBLE_PLAY',
 jsonb_build_object('scope','double_play','pitcher_id',pitcher,'previous_version',g.version,'batter_id',batter,'runner_id',runner,
 'source',p_source,'outs_added',2,'batting_order',turn_number,'runs',runs,'rbi',0,'advances',p_advances,
 'third_out_type',case when half_ended then p_third_out end,'scoring_player_ids',to_jsonb(scorers),
 'plate_appearance_completed',true,'ab',1),g.version+1);

 IF pitcher IS NULL THEN RAISE EXCEPTION 'PITCHER_REQUIRED'; END IF;
 PERFORM public.swl_v56_accumulate_pitching(g,pitcher,'OUT');
 PERFORM public.swl_v56_close_after_play(g);
 RETURN jsonb_build_object('id',g.id,'version',g.version+1,'action','DOUBLE_PLAY','outs_added',2,'half_ended',g.outs=1);
END;
$function$;

CREATE OR REPLACE FUNCTION swl_private.v57_undo_dp(g swl_live_games, e swl_game_events, v_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE saved swl_private.v57_dp_undo_state%ROWTYPE;
 prior public.swl_live_games%ROWTYPE;
 credit public.swl_v56_pitching_events%ROWTYPE;
 team uuid;
BEGIN
 SELECT * INTO saved FROM swl_private.v57_dp_undo_state
 WHERE game_id=g.id AND version=g.version;
 IF NOT FOUND THEN RAISE EXCEPTION 'DP_UNDO_SNAPSHOT_UNAVAILABLE'; END IF;
 IF saved.snapshot_schema NOT IN (1,2)
  OR NOT (saved.prior ?& ARRAY['id','version','is_top','inning','outs','bases_state',
    'swl_base_players','home_runs','away_runs','balls','strikes'])
 THEN RAISE EXCEPTION 'DP_UNDO_SNAPSHOT_INVALID'; END IF;
 prior:=jsonb_populate_record(NULL::public.swl_live_games,saved.prior);
 IF prior.id IS DISTINCT FROM g.id OR prior.version IS DISTINCT FROM e.version-1
 THEN RAISE EXCEPTION 'DP_UNDO_SNAPSHOT_INVALID'; END IF;
 team:=CASE WHEN prior.is_top THEN prior.away_team_id ELSE prior.home_team_id END;
 IF v_actor IS NULL OR g.status NOT IN ('IN_PROGRESS','FINAL')
 OR coalesce(g.swl_home_signed,false) OR coalesce(g.swl_away_signed,false)
 OR e.batting_team_id IS DISTINCT FROM team
 OR v_actor IS DISTINCT FROM (CASE WHEN prior.is_top THEN g.away_manager_id ELSE g.home_manager_id END)
 OR public.swl_can_manage_roster(team) IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'DP_UNDO_NOT_ALLOWED' USING ERRCODE='42501';
 END IF;
 IF g.swl_knockout_pending IS NOT NULL
 THEN RAISE EXCEPTION 'KNOCKOUT_DECISION_PENDING'; END IF;
 SELECT * INTO credit FROM public.swl_v56_pitching_events
 WHERE game_id=g.id AND version=g.version FOR UPDATE;
 IF NOT FOUND OR credit.outs<>2 OR credit.pitcher_id::text IS DISTINCT FROM e.event_data->>'pitcher_id' THEN
   RAISE EXCEPTION 'PITCHING_STATS_MISMATCH';
 END IF;
 UPDATE public.swl_live_games SET
   inning=prior.inning,is_top=prior.is_top,status=prior.status,
   outs=prior.outs,balls=prior.balls,strikes=prior.strikes,
   bases_state=prior.bases_state,swl_base_players=prior.swl_base_players,
   swl_ghost_player=prior.swl_ghost_player,home_runs=prior.home_runs,away_runs=prior.away_runs,
   home_innings=prior.home_innings,away_innings=prior.away_innings,
   swl_finish_reason=prior.swl_finish_reason,
   swl_final_half_completed=prior.swl_final_half_completed,
   version=g.version+1,updated_at=now() WHERE id=g.id;
 DELETE FROM public.swl_v56_runner_identity WHERE game_id=g.id;
 IF saved.runner_identity IS NOT NULL THEN
   INSERT INTO public.swl_v56_runner_identity
   SELECT * FROM jsonb_populate_record(NULL::public.swl_v56_runner_identity,
     saved.runner_identity || jsonb_build_object('game_version',g.version+1));
 END IF;
 IF saved.cursor_before IS NULL THEN
   DELETE FROM public.swl_game_batting_turns WHERE game_id=g.id AND team_id=team;
 ELSE
   UPDATE public.swl_game_batting_turns SET next_order=saved.cursor_before,updated_at=now()
   WHERE game_id=g.id AND team_id=team;
 END IF;
 DELETE FROM public.swl_v56_pitching_events WHERE game_id=g.id AND version=g.version;
 INSERT INTO public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
 VALUES(g.id,v_actor,team,prior.inning,prior.is_top,'UNDO_OUT',
   jsonb_build_object('reverts_version',g.version,'previous_version',g.version,
    'reverts_type','DOUBLE_PLAY','pitching_credit',to_jsonb(credit)),g.version+1);
 RETURN jsonb_build_object('id',g.id,'version',g.version+1,'action','UNDO_OUT','outs',prior.outs);
END;
$function$;

SAVEPOINT swl_v57_pruebas;

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

ROLLBACK TO SAVEPOINT swl_v57_pruebas;
RELEASE SAVEPOINT swl_v57_pruebas;

DO $verificacion$
BEGIN
 IF EXISTS (
   SELECT FROM pg_temp.swl_v57_dp_original o
   FULL JOIN swl_private.v57_dp_undo_state s USING(game_id,version)
   WHERE (to_jsonb(s)-'snapshot_schema') IS DISTINCT FROM o.payload
      OR s.snapshot_schema IS DISTINCT FROM 1
 ) OR (SELECT to_jsonb(a) FROM pg_temp.swl_v57_dp_acl a) IS DISTINCT FROM (
   SELECT to_jsonb(a) FROM (SELECT relowner,relacl,relrowsecurity,relforcerowsecurity
     FROM pg_class WHERE oid='swl_private.v57_dp_undo_state'::regclass) a
 )
 THEN RAISE EXCEPTION 'Cambió un snapshot histórico o la seguridad de su tabla'; END IF;
 IF (SELECT to_jsonb(h) FROM pg_temp.swl_v57_huellas h) IS DISTINCT FROM
    (SELECT to_jsonb(v) FROM pg_temp.swl_v57_integridad v)
 THEN RAISE EXCEPTION 'Cambió la huella de SWL-378859'; END IF;
 IF EXISTS (SELECT FROM public.swl_live_games WHERE game_pin='SWL-378859'
   AND (swl_knockout_mode<>'AUTO' OR swl_knockout_pending IS NOT NULL
        OR swl_knockout_waived_through<>0))
 THEN RAISE EXCEPTION 'Configuración inesperada del partido de referencia'; END IF;
 IF EXISTS (SELECT FROM pg_temp.swl_v57_funciones f
   LEFT JOIN pg_proc p ON p.oid=f.oid
   WHERE (f.proowner,f.proacl,f.prosecdef,f.proconfig)
     IS DISTINCT FROM (p.proowner,p.proacl,p.prosecdef,p.proconfig))
 THEN RAISE EXCEPTION 'Cambió un permiso o propiedad de las RPC existentes'; END IF;
END $verificacion$;
DROP VIEW pg_temp.swl_v57_integridad;
COMMIT;
