-- Propuesta LAB sin ejecutar.
BEGIN;
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
COMMIT;
