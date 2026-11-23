-- PROPUESTA SIN EJECUTAR. Basada en la función realmente instalada en LAB el 2026-11-23.
-- Requiere autorización explícita y pruebas transaccionales antes de aplicarse.
-- Permite un único out de corredor que complete el tercer out durante un hit.
-- En tercer out forzado nunca cuenta carreras. En jugada de tiempo exige
-- confirmación y solo acredita corredores delante del retirado.
-- Limpia las bases y cambia media entrada; preserva firma y permisos existentes.
BEGIN;
CREATE OR REPLACE FUNCTION public.swl_v57_batted_ball(p_game_id uuid, p_expected_version bigint, p_action text, p_batter_id uuid, p_data jsonb)
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
 terminal boolean:=false; retired_source integer; forced_out boolean:=false; confirmed_timing boolean:=false;
 new_bases jsonb; new_innings jsonb; new_home integer; new_away integer; result jsonb;
BEGIN
 IF p_action IS DISTINCT FROM 'HIT_WITH_OUT' OR p_data IS NULL OR jsonb_typeof(p_data)<>'object' THEN
   RAISE EXCEPTION 'V57_COMPLEX_PLAY_NOT_ENABLED'; END IF;
 IF p_batter_id IS NULL OR p_data->>'p_batter_id' IS DISTINCT FROM p_batter_id::text THEN
   RAISE EXCEPTION 'BATTER_ID_MISMATCH'; END IF;
 IF p_data->>'p_batter_base' !~ '^[1-4]$' THEN RAISE EXCEPTION 'INVALID_BATTER_BASE'; END IF;
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
 IF p_data ? 'p_last_out_source' AND p_data->'p_last_out_source' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'V57_COMPLEX_PLAY_NOT_ENABLED'; END IF;
 confirmed_timing:=coalesce((p_data->>'count_runs_on_third_out')::boolean,false);
 outs_made:=(SELECT count(*) FROM unnest(moves) x WHERE x<0);
 IF outs_made=0 THEN
   RETURN public.swl_v56_apply_hit(p_game_id,p_expected_version,p_batter_id,bbase,moves[1],moves[2],moves[3]);
 END IF;
 IF outs_made<>1 OR bbase=4 THEN RAISE EXCEPTION 'V57_COMPLEX_PLAY_NOT_ENABLED'; END IF;
 g:=public.swl_v56_lock_batting_turn(p_game_id,p_expected_version);
 terminal := g.outs=2;
 team:=CASE WHEN g.is_top THEN g.away_team_id ELSE g.home_team_id END;
 SELECT l.lineup INTO lineup FROM public.swl_game_lineups l WHERE l.game_id=g.id AND l.team_id=team;
 IF lineup IS NULL OR jsonb_typeof(lineup)<>'array' OR jsonb_array_length(lineup) NOT BETWEEN 9 AND 13 THEN
 RAISE EXCEPTION 'LINEUP_REQUIRED'; END IF;
 SELECT next_order INTO batting_order FROM public.swl_game_batting_turns WHERE game_id=g.id AND team_id=team FOR UPDATE;
 IF batting_order IS NULL OR batting_order NOT BETWEEN 1 AND jsonb_array_length(lineup)
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
     IF (i=1 AND d NOT IN (0,2,3,-2,-3,-4))
     OR (i=2 AND d NOT IN (0,3,-3,-4))
     OR (i=3 AND d NOT IN (0,-4)) THEN RAISE EXCEPTION 'INVALID_RUNNER_DESTINATION'; END IF;
     IF d<0 THEN
       retired_source:=i;
       IF -d<=i THEN RAISE EXCEPTION 'INVALID_OUT_BASE'; END IF;
     ELSE
       target:=CASE WHEN d=0 THEN 4 ELSE d END;
       IF target<last_target OR (target=last_target AND target<>4) THEN
         RAISE EXCEPTION 'RUNNER_ORDER_INVALID'; END IF;
       last_target:=target;
       IF d=0 THEN scored:=scored+1;
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
     AND (retired_source=1 OR (occ[1] AND (retired_source=2 OR occ[2])));
   scored:=0;
   IF confirmed_timing AND NOT forced_out THEN
     FOR i IN (retired_source+1)..3 LOOP
       IF moves[i]=0 THEN scored:=scored+1; END IF;
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
  outs=CASE WHEN terminal THEN 0 ELSE g.outs+1 END,
  inning=g.inning+CASE WHEN terminal AND NOT g.is_top THEN 1 ELSE 0 END,
  is_top=CASE WHEN terminal THEN NOT g.is_top ELSE g.is_top END,
  balls=0,strikes=0,
  home_runs=new_home,away_runs=new_away,
  home_hits=g.home_hits+(CASE WHEN g.is_top THEN 0 ELSE 1 END),
  away_hits=g.away_hits+(CASE WHEN g.is_top THEN 1 ELSE 0 END),
  home_innings=result->'home_innings',away_innings=result->'away_innings',
  bases_state=new_bases,version=g.version+1,updated_at=now()
 WHERE id=g.id;
 UPDATE public.swl_live_games SET swl_base_players=new_players,
  swl_ghost_player=CASE WHEN g.swl_ghost_player=ANY(new_players) THEN g.swl_ghost_player END WHERE id=g.id;
 UPDATE public.swl_game_batting_turns SET
  next_order=CASE WHEN batting_order=jsonb_array_length(lineup) THEN 1 ELSE batting_order+1 END,
  updated_at=now() WHERE game_id=g.id AND team_id=team;
 INSERT INTO public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
 VALUES(g.id,(SELECT auth.uid()),team,g.inning,g.is_top,'HIT',
 jsonb_build_object('scope','hit_with_runner_out','previous_version',g.version,'batter_id',p_batter_id,
 'batting_order',batting_order,'batter_base',bbase,'first_to',moves[1],'second_to',moves[2],
 'third_to',moves[3],'outs_added',1,'runs',scored,
 'third_out',terminal,'out_at_base',-moves[retired_source],
 'out_runner_id',players[(SELECT x.i FROM unnest(moves) WITH ORDINALITY AS x(destination,i) WHERE x.destination<0 LIMIT 1)]::text),g.version+1);
 PERFORM public.swl_v56_accumulate_pitching(g,pitcher,'HIT');
 PERFORM public.swl_v56_close_after_play(g);
 RETURN jsonb_build_object('id',g.id,'version',g.version+1,'action','HIT','runs',scored,'outs_added',1,'third_out',terminal,'bases',new_bases);
END $function$
;
REVOKE ALL ON FUNCTION public.swl_v57_batted_ball(uuid,bigint,text,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.swl_v57_batted_ball(uuid,bigint,text,uuid,jsonb) TO authenticated;
COMMIT;
