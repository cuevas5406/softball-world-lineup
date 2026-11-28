-- Propuesta para revisión. No ejecutar sin autorización.
BEGIN;
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
COMMIT;
