-- Propuesta para LAB. No ejecutar sin autorización.
BEGIN;
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
COMMIT;
