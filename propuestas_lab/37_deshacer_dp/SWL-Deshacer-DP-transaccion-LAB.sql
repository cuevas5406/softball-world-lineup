-- Propuesta para revisión. No ejecutar sin autorización.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- Proteger SWL-378859 durante la comprobación de huellas.
SELECT id FROM public.swl_live_games WHERE game_pin='SWL-378859' FOR SHARE;
CREATE TEMP TABLE swl_dp_revision_guard ON COMMIT DROP AS
SELECT g.id, md5(to_jsonb(g)::text) AS hash_partido,
 (SELECT md5(jsonb_agg(to_jsonb(e) ORDER BY e.id)::text) FROM public.swl_game_events e WHERE e.game_id=g.id) AS hash_eventos,
 (SELECT md5(jsonb_agg(to_jsonb(l) ORDER BY l.team_id)::text) FROM public.swl_game_lineups l WHERE l.game_id=g.id) AS hash_alineaciones,
 (SELECT md5(jsonb_agg(to_jsonb(c) ORDER BY c.version)::text) FROM public.swl_v56_pitching_events c WHERE c.game_id=g.id) AS hash_pitcheo
FROM public.swl_live_games g WHERE g.game_pin='SWL-378859';

CREATE TABLE swl_private.v57_dp_undo_state (
  game_id uuid NOT NULL REFERENCES public.swl_live_games(id) ON DELETE CASCADE,
  version bigint NOT NULL,
  prior public.swl_live_games NOT NULL,
  cursor_before integer,
  runner_identity jsonb,
  PRIMARY KEY (game_id,version)
);
REVOKE ALL ON swl_private.v57_dp_undo_state FROM PUBLIC, anon, authenticated;
ALTER TABLE swl_private.v57_dp_undo_state ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION swl_private.v57_undo_dp(
  g public.swl_live_games,e public.swl_game_events,v_actor uuid
) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $undo$
DECLARE saved swl_private.v57_dp_undo_state%ROWTYPE;
 prior public.swl_live_games%ROWTYPE;
 credit public.swl_v56_pitching_events%ROWTYPE;
 team uuid;
BEGIN
 SELECT * INTO saved FROM swl_private.v57_dp_undo_state
 WHERE game_id=g.id AND version=g.version;
 IF NOT FOUND THEN RAISE EXCEPTION 'DP_UNDO_SNAPSHOT_UNAVAILABLE'; END IF;
 prior:=saved.prior;
 team:=CASE WHEN prior.is_top THEN prior.away_team_id ELSE prior.home_team_id END;
 IF v_actor IS NULL OR g.status NOT IN ('IN_PROGRESS','FINAL')
 OR coalesce(g.swl_home_signed,false) OR coalesce(g.swl_away_signed,false)
 OR e.batting_team_id IS DISTINCT FROM team
 OR v_actor IS DISTINCT FROM (CASE WHEN prior.is_top THEN g.away_manager_id ELSE g.home_manager_id END)
 OR public.swl_can_manage_roster(team) IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'DP_UNDO_NOT_ALLOWED' USING ERRCODE='42501';
 END IF;
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
   swl_finish_requested_by=prior.swl_finish_requested_by,
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
$undo$;
REVOKE ALL ON FUNCTION swl_private.v57_undo_dp(public.swl_live_games,public.swl_game_events,uuid)
 FROM PUBLIC, anon, authenticated;
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
 INSERT INTO swl_private.v57_dp_undo_state(game_id,version,prior,cursor_before,runner_identity)
 VALUES(g.id,g.version+1,g,(SELECT next_order FROM public.swl_game_batting_turns WHERE game_id=g.id AND team_id=team),
   (SELECT to_jsonb(r) FROM public.swl_v56_runner_identity r WHERE r.game_id=g.id));
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
 INSERT INTO swl_private.v57_dp_undo_state(game_id,version,prior,cursor_before,runner_identity)
 VALUES(g.id,g.version+1,g,(SELECT next_order FROM public.swl_game_batting_turns WHERE game_id=g.id AND team_id=team),
   (SELECT to_jsonb(r) FROM public.swl_v56_runner_identity r WHERE r.game_id=g.id));
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
CREATE OR REPLACE FUNCTION public.swl_v57_undo_last_out(p_game_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE g public.swl_live_games%ROWTYPE; e public.swl_game_events%ROWTYPE; t integer; p public.swl_v56_pitching_events%ROWTYPE; v_actor uuid := (SELECT auth.uid()); v_team uuid;
BEGIN
 SELECT * INTO g FROM public.swl_live_games WHERE id=p_game_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'GAME_NOT_FOUND'; END IF;
 IF v_actor IS NOT NULL AND g.version IS NOT DISTINCT FROM p_expected_version THEN
   SELECT * INTO e FROM public.swl_game_events WHERE game_id=g.id AND version=g.version;
   IF FOUND AND e.event_type='DOUBLE_PLAY' THEN
     RETURN swl_private.v57_undo_dp(g,e,v_actor);
   END IF;
 END IF;
 IF v_actor IS NULL OR g.status<>'IN_PROGRESS' OR g.version IS DISTINCT FROM p_expected_version THEN RAISE EXCEPTION 'GAME_STATE_CHANGED'; END IF;
 v_team:=CASE WHEN g.is_top THEN g.away_team_id ELSE g.home_team_id END;
 IF v_actor IS DISTINCT FROM (CASE WHEN g.is_top THEN g.away_manager_id ELSE g.home_manager_id END)
 OR public.swl_can_manage_roster(v_team) IS DISTINCT FROM true THEN
 RAISE EXCEPTION 'NOT_BATTING_MANAGER' USING ERRCODE='42501'; END IF;
 SELECT * INTO e FROM public.swl_game_events WHERE game_id=g.id AND version=g.version FOR UPDATE;
 IF NOT FOUND OR e.event_type<>'OUT' OR e.event_data->>'scope'<>'basic_counters'
 OR e.inning IS DISTINCT FROM g.inning OR e.is_top IS DISTINCT FROM g.is_top
 OR g.outs NOT BETWEEN 1 AND 2 OR g.balls<>0 OR g.strikes<>0
 OR (e.event_data->>'batting_order') !~ '^[0-9]+$' THEN
 RAISE EXCEPTION 'ONLY_LAST_SIMPLE_OUT_CAN_BE_UNDONE'; END IF;
 SELECT next_order INTO t FROM public.swl_game_batting_turns WHERE game_id=g.id AND team_id=v_team FOR UPDATE;
 IF t IS DISTINCT FROM (
   SELECT CASE WHEN (e.event_data->>'batting_order')::integer=jsonb_array_length(l.lineup)
   THEN 1 ELSE (e.event_data->>'batting_order')::integer+1 END
   FROM public.swl_game_lineups l WHERE l.game_id=g.id AND l.team_id=v_team
 ) THEN
 RAISE EXCEPTION 'BATTING_TURN_CHANGED'; END IF;
 SELECT * INTO p FROM public.swl_v56_pitching_events WHERE game_id=g.id AND version=g.version FOR UPDATE;
 IF NOT FOUND OR p.outs<>1 OR p.strikes_out<>0 OR p.hits<>0 OR p.walks<>0 THEN
 RAISE EXCEPTION 'PITCHING_STATS_MISMATCH'; END IF;
 UPDATE public.swl_live_games SET outs=g.outs-1,version=g.version+1,updated_at=now() WHERE id=g.id;
 UPDATE public.swl_game_batting_turns SET next_order=(e.event_data->>'batting_order')::integer,updated_at=now() WHERE game_id=g.id AND team_id=v_team;
 DELETE FROM public.swl_v56_pitching_events WHERE game_id=g.id AND version=g.version;
 INSERT INTO public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
 VALUES(g.id,v_actor,v_team,g.inning,g.is_top,'UNDO_OUT',jsonb_build_object('reverts_version',g.version,'previous_version',g.version,'restored_batting_order',(e.event_data->>'batting_order')::integer,'outs_before',g.outs,'outs_after',g.outs-1),g.version+1);
 RETURN jsonb_build_object('id',g.id,'version',g.version+1,'action','UNDO_OUT','outs',g.outs-1);
END $function$;

-- Propuesta adicional. Pendiente de autorización exclusiva para LAB.
CREATE OR REPLACE FUNCTION public.swl_v53_batting_stats(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); g public.swl_live_games%rowtype; output jsonb;
begin
 if uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 select * into g from public.swl_live_games where id=p_game_id;
 if not found then raise exception 'GAME_NOT_FOUND'; end if;
 if uid is distinct from g.home_manager_id and uid is distinct from g.away_manager_id then
 raise exception 'NOT_GAME_MANAGER' using errcode='42501'; end if;
 with tagged as (
 select e.event_type,e.event_data, e.batting_team_id,
 (e.event_data->>'batter_id')::uuid as player_id,
 coalesce((e.event_data->>'plate_appearance_completed')::boolean,false) as completed,
 (e.event_data->>'batter_base')::int as hit_bases
 from public.swl_game_events e
 where e.game_id=p_game_id and e.event_data ? 'batter_id'
   and e.version <= g.version
   and not exists (
     select 1 from public.swl_game_events correction
     where correction.game_id=e.game_id
       and correction.event_type='UNDO_OUT'
       and correction.version<=g.version
       and correction.event_data->>'reverts_version'=e.version::text
   )
 ), grouped as (
 select player_id,batting_team_id,
 count(*) filter(where event_type='HIT' and hit_bases between 1 and 4)::int as hits,
 count(*) filter(where event_type='HIT' and hit_bases=1)::int as singles,
 count(*) filter(where event_type='HIT' and hit_bases=2)::int as doubles,
 count(*) filter(where event_type='HIT' and hit_bases=3)::int as triples,
 count(*) filter(where event_type='HIT' and hit_bases=4)::int as home_runs,
 count(*) filter(where event_type='BALL' and completed)::int as walks,
 count(*) filter(where event_type='STRIKE' and completed)::int as strikeouts,
 count(*) filter(where event_type='HIT' or (event_type in ('STRIKE','OUT') and completed))::int as at_bats,
 count(*) filter(where event_type='HIT' or completed)::int as plate_appearances
 from tagged group by player_id,batting_team_id
 )
 select coalesce(jsonb_agg(to_jsonb(grouped) order by batting_team_id,player_id),'[]'::jsonb)
 into output from grouped;
 return output;
end $function$;

SAVEPOINT swl_pruebas_temporales;
DO $test$
DECLARE
  g public.swl_live_games%rowtype;
  before_dp jsonb;
  legacy_leak boolean:=false;
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
              (scenario='undo' AND mask IN (3,7) AND src=1 AND o<2) OR
              (scenario IN ('duplicate','wrong_manager') AND mask=3 AND src=1 AND o=0)
            ) THEN CONTINUE; END IF;
            BEGIN
              ids:=ARRAY[NULL,NULL,NULL]::uuid[];
              FOR b IN 1..3 LOOP
                IF (mask & (1 << (b-1))) <> 0 THEN ids[b]:=away_players[b+1]; END IF;
              END LOOP;
              UPDATE public.swl_live_games SET outs=o,
                bases_state=jsonb_build_object('first',ids[1] IS NOT NULL,'second',ids[2] IS NOT NULL,'third',ids[3] IS NOT NULL),
                swl_base_players=ids,balls=2,strikes=1 WHERE id=fixture;
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
                IF ids[3] IS NOT NULL THEN
                  moves:='{"3":0}'; mode:='TIME'; scorers:=ARRAY[ids[3]];
                  expected[3]:=NULL;
                END IF;
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
                BEGIN
                  PERFORM public.swl_v57_undo_last_out(fixture,1);
                  RAISE SQLSTATE 'ZX001' USING MESSAGE='Deshacer obsoleto aceptado';
                EXCEPTION WHEN raise_exception THEN
                  IF SQLERRM<>'GAME_STATE_CHANGED' THEN RAISE; END IF;
                END;
                PERFORM set_config('request.jwt.claim.sub',source_game.home_manager_id::text,true);
                BEGIN
                  PERFORM public.swl_v57_undo_last_out(fixture,2);
                  RAISE SQLSTATE 'ZX001' USING MESSAGE='Deshacer por rival aceptado';
                EXCEPTION WHEN insufficient_privilege THEN NULL;
                END;
                PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
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
                BEGIN
                  PERFORM public.swl_v57_undo_last_out(fixture,3);
                  RAISE SQLSTATE 'ZX001' USING MESSAGE='Deshacer duplicado aceptado';
                EXCEPTION WHEN raise_exception THEN
                  IF SQLERRM NOT IN ('ONLY_LAST_SIMPLE_OUT_CAN_BE_UNDONE','GAME_STATE_CHANGED') THEN RAISE; END IF;
                END;
                IF EXISTS (SELECT FROM jsonb_array_elements(public.swl_v53_batting_stats(fixture)) stats
                  WHERE (stats->>'plate_appearances')::integer>0) THEN legacy_leak:=true; END IF;
                UPDATE public.swl_live_games SET status='OFFICIAL' WHERE id=fixture;
                IF EXISTS(SELECT FROM swl_private.game_batting(fixture,NULL::uuid))
                   OR EXISTS(SELECT FROM swl_private.game_pitching(fixture,NULL::uuid))
                THEN RAISE EXCEPTION 'Estadísticas oficiales conservan el DP anulado'; END IF;
              END IF;
              RAISE SQLSTATE 'ZX002' USING MESSAGE='Revertir escenario probado';
            EXCEPTION WHEN SQLSTATE 'ZX002' THEN NULL;
            END;
          END LOOP;
        END LOOP;
      END LOOP;
    END LOOP;
    PERFORM set_config('request.jwt.claim.sub',source_game.away_manager_id::text,true);
    PERFORM public.swl_v56_record_plate_action(fixture,1,'OUT',away_players[1]);
    PERFORM public.swl_v57_undo_last_out(fixture,2);
    IF NOT EXISTS (SELECT FROM public.swl_live_games WHERE id=fixture AND version=3 AND outs=0)
      OR EXISTS (SELECT FROM public.swl_v56_pitching_events WHERE game_id=fixture)
    THEN RAISE EXCEPTION 'Regresión de deshacer OUT básico'; END IF;
    RAISE SQLSTATE 'ZX003' USING MESSAGE='Revertir preparación';
  EXCEPTION WHEN SQLSTATE 'ZX003' THEN NULL;
  END;
  IF EXISTS (SELECT FROM public.swl_live_games WHERE id IN (fixture,other_game)) THEN RAISE EXCEPTION 'Fixture persistente'; END IF;
  IF legacy_leak THEN
    RAISE EXCEPTION 'DP_UNDO_LEGACY_STATS_LEAK: swl_v53_batting_stats conserva una PA anulada. Pasaron las demás verificaciones.';
  END IF;
END;
$test$;

ROLLBACK TO SAVEPOINT swl_pruebas_temporales;
RELEASE SAVEPOINT swl_pruebas_temporales;

DO $integrity$
BEGIN
  IF (SELECT count(*) FROM pg_temp.swl_dp_revision_guard) <> 1 OR NOT EXISTS (
    SELECT 1 FROM pg_temp.swl_dp_revision_guard h
    JOIN public.swl_live_games g ON g.id=h.id AND g.game_pin='SWL-378859'
    WHERE h.hash_partido=md5(to_jsonb(g)::text)
    AND h.hash_eventos IS NOT DISTINCT FROM
      (SELECT md5(jsonb_agg(to_jsonb(e) ORDER BY e.id)::text) FROM public.swl_game_events e WHERE e.game_id=g.id)
    AND h.hash_alineaciones IS NOT DISTINCT FROM
      (SELECT md5(jsonb_agg(to_jsonb(l) ORDER BY l.team_id)::text) FROM public.swl_game_lineups l WHERE l.game_id=g.id)
    AND h.hash_pitcheo IS NOT DISTINCT FROM
      (SELECT md5(jsonb_agg(to_jsonb(c) ORDER BY c.version)::text) FROM public.swl_v56_pitching_events c WHERE c.game_id=g.id)
  ) THEN
    RAISE EXCEPTION 'La huella de SWL-378859 cambió o el partido no existe';
  END IF;
END;
$integrity$;

COMMIT;
