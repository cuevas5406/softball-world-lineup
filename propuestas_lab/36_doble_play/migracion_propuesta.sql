-- PROPUESTA LAB. No ejecutada. Conserva la RPC anterior.
BEGIN;
CREATE FUNCTION public.swl_v57_double_play_advanced(
 p_game_id uuid,p_expected_version bigint,p_source integer,p_advances jsonb,p_third_out text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $dp$

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
 INSERT INTO public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
 VALUES(g.id,auth.uid(),team,g.inning,g.is_top,'DOUBLE_PLAY',
 jsonb_build_object('scope','double_play','previous_version',g.version,'batter_id',batter,'runner_id',runner,
 'source',p_source,'outs_added',2,'batting_order',turn_number,'runs',runs,'rbi',0,'advances',p_advances,
 'third_out_type',case when half_ended then p_third_out end,'scoring_player_ids',to_jsonb(scorers),
 'plate_appearance_completed',true,'ab',1),g.version+1);
 SELECT pitcher_id INTO pitcher FROM public.swl_game_lineups WHERE game_id=g.id AND team_id=(CASE WHEN g.is_top THEN g.home_team_id ELSE g.away_team_id END);
 IF pitcher IS NULL THEN RAISE EXCEPTION 'PITCHER_REQUIRED'; END IF;
 PERFORM public.swl_v56_accumulate_pitching(g,pitcher,'OUT');
 PERFORM public.swl_v56_close_after_play(g);
 RETURN jsonb_build_object('id',g.id,'version',g.version+1,'action','DOUBLE_PLAY','outs_added',2,'half_ended',g.outs=1);
END;
$dp$;
REVOKE ALL ON FUNCTION public.swl_v57_double_play_advanced(uuid,bigint,integer,jsonb,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.swl_v57_double_play_advanced(uuid,bigint,integer,jsonb,text) TO authenticated;
COMMIT;
