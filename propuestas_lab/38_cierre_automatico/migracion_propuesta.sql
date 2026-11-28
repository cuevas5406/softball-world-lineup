-- Propuesta para LAB. Pendiente de autorización. No altera filas existentes.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE public.swl_v56_match_decisions
  DROP CONSTRAINT swl_v56_match_decisions_action_check,
  ADD CONSTRAINT swl_v56_match_decisions_action_check
    CHECK (action IN ('REQUEST','ACCEPT','REJECT','SIGN','AUTO','INVALIDATED'));

CREATE OR REPLACE FUNCTION public.swl_v56_match_decision(p_game_id uuid, p_expected_version bigint, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE g public.swl_live_games%ROWTYPE; actor uuid := auth.uid(); is_home boolean;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Debes iniciar sesión.'; END IF;
 SELECT * INTO g FROM public.swl_live_games WHERE id=p_game_id FOR UPDATE;
 IF NOT FOUND OR g.home_manager_id IS NULL OR g.away_manager_id IS NULL
 OR g.home_manager_id=g.away_manager_id
 OR actor NOT IN (g.home_manager_id,g.away_manager_id) THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Acción reservada a ambos mánagers.';
 END IF;
 is_home := actor=g.home_manager_id;
 IF public.swl_can_manage_roster(CASE WHEN is_home THEN g.home_team_id ELSE g.away_team_id END) IS NOT TRUE THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Permiso de equipo no vigente.';
 END IF;
 IF g.version IS DISTINCT FROM p_expected_version THEN
  RAISE EXCEPTION 'El partido cambió. Actualiza antes de continuar.';
 END IF;
 IF p_action='SIGN' AND g.status='FINAL' THEN
  IF (CASE WHEN is_home THEN g.swl_home_signed ELSE g.swl_away_signed END) THEN RETURN; END IF;
  UPDATE public.swl_live_games SET
   swl_home_signed=g.swl_home_signed OR is_home,
   swl_away_signed=g.swl_away_signed OR NOT is_home,
   status=CASE WHEN (is_home AND g.swl_away_signed) OR (NOT is_home AND g.swl_home_signed) THEN 'OFFICIAL' ELSE status END,
   version=g.version+1 WHERE id=g.id;
 ELSIF g.status='IN_PROGRESS' AND g.inning>=5 AND g.home_runs<>g.away_runs AND p_action='REQUEST' AND g.swl_finish_requested_by IS NULL THEN
  UPDATE public.swl_live_games SET swl_finish_requested_by=actor,version=g.version+1 WHERE id=g.id;
 ELSIF g.status='IN_PROGRESS' AND p_action IN ('ACCEPT','REJECT') AND g.swl_finish_requested_by IS NOT NULL AND g.swl_finish_requested_by<>actor THEN
  UPDATE public.swl_live_games SET
   swl_finish_requested_by=NULL,
   swl_finish_reason=CASE WHEN p_action='ACCEPT' THEN 'Acuerdo de ambos mánagers (cierre anticipado)' ELSE swl_finish_reason END,
   status=CASE WHEN p_action='ACCEPT' THEN 'FINAL' ELSE status END,
   version=g.version+1 WHERE id=g.id;
 ELSE
  RAISE EXCEPTION 'El partido no admite esta acción.';
 END IF;
 INSERT INTO public.swl_v56_match_decisions(game_id,version,action,actor_id) VALUES(g.id,g.version+1,p_action,actor);
END $function$;
COMMIT;
