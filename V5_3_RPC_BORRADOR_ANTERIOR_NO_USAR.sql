-- PROPUESTA PARA REVISIÓN Y APROBACIÓN. NO EJECUTADA.
-- SOLO LAB. No habilitar Flutter hasta aplicar y probar en dos sesiones reales.
-- Implementación mínima de contadores; NO incluye avance automático de corredores,
-- boletos, ponches, anotación por bateador ni reglas completas de sóftbol.
BEGIN;
CREATE OR REPLACE FUNCTION public.swl_v53_record_play(
  p_game_id uuid, p_expected_version bigint, p_action text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  g public.swl_live_games%ROWTYPE;
  uid uuid := (SELECT auth.uid());
  action text := upper(trim(p_action));
  next_balls integer;
  next_strikes integer;
  next_outs integer;
  next_inning integer;
  next_top boolean;
  next_home_runs integer;
  next_away_runs integer;
  next_home_hits integer;
  next_away_hits integer;
  next_home_errors integer;
  next_away_errors integer;
  next_bases jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Sesión requerida' USING ERRCODE = '28000'; END IF;
  IF action NOT IN ('BALL','STRIKE','OUT','RUN','HIT','ERROR') THEN
    RAISE EXCEPTION 'Acción no permitida';
  END IF;
  SELECT * INTO g FROM public.swl_live_games WHERE id = p_game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Partido inexistente'; END IF;
  IF uid IS DISTINCT FROM g.home_manager_id AND uid IS DISTINCT FROM g.away_manager_id THEN
    RAISE EXCEPTION 'Solo mánagers vinculados pueden anotar' USING ERRCODE = '42501';
  END IF;
  IF g.home_manager_id IS NULL OR g.away_manager_id IS NULL THEN
    RAISE EXCEPTION 'Ambos mánagers deben estar vinculados';
  END IF;
  IF g.status IN ('FINAL','OFFICIAL') THEN RAISE EXCEPTION 'Partido cerrado'; END IF;
  IF g.version <> p_expected_version THEN
    RAISE EXCEPTION 'Marcador cambió; actualiza y vuelve a intentar' USING ERRCODE = '40001';
  END IF;
  next_balls := g.balls; next_strikes := g.strikes; next_outs := g.outs;
  next_inning := g.inning; next_top := g.is_top;
  next_home_runs := g.home_runs; next_away_runs := g.away_runs;
  next_home_hits := g.home_hits; next_away_hits := g.away_hits;
  next_home_errors := g.home_errors; next_away_errors := g.away_errors;
  next_bases := g.bases_state;
  IF action = 'BALL' THEN
    IF next_balls = 3 THEN RAISE EXCEPTION 'Base por bolas aún no implementada'; END IF;
    next_balls := next_balls + 1;
  ELSIF action = 'STRIKE' THEN
    IF next_strikes = 2 THEN RAISE EXCEPTION 'Ponche aún no implementado'; END IF;
    next_strikes := next_strikes + 1;
  ELSIF action = 'OUT' THEN
    next_balls := 0; next_strikes := 0;
    IF next_outs = 2 THEN
      next_outs := 0;
      IF next_top THEN next_top := false;
      ELSE next_top := true; next_inning := next_inning + 1; END IF;
      next_bases := '{"first":false,"second":false,"third":false}'::jsonb;
    ELSE next_outs := next_outs + 1; END IF;
  ELSIF action = 'RUN' THEN
    IF g.is_top THEN next_away_runs := next_away_runs + 1;
    ELSE next_home_runs := next_home_runs + 1; END IF;
  ELSIF action = 'HIT' THEN
    IF g.is_top THEN next_away_hits := next_away_hits + 1;
    ELSE next_home_hits := next_home_hits + 1; END IF;
  ELSIF action = 'ERROR' THEN
    IF g.is_top THEN next_home_errors := next_home_errors + 1;
    ELSE next_away_errors := next_away_errors + 1; END IF;
  END IF;
  UPDATE public.swl_live_games SET
    balls=next_balls,strikes=next_strikes,outs=next_outs,
    inning=next_inning,is_top=next_top,
    home_runs=next_home_runs,away_runs=next_away_runs,
    home_hits=next_home_hits,away_hits=next_away_hits,
    home_errors=next_home_errors,away_errors=next_away_errors,
    bases_state=next_bases,status='IN_PROGRESS',
    version=g.version+1,updated_at=now()
  WHERE id=g.id;
  INSERT INTO public.swl_game_events
    (game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
  VALUES (g.id,uid,CASE WHEN g.is_top THEN g.away_team_id ELSE g.home_team_id END,
          g.inning,g.is_top,action,
          jsonb_build_object('previous_version',g.version),g.version+1);
  RETURN jsonb_build_object('id',g.id,'version',g.version+1,'action',action);
END;
$$;
REVOKE ALL ON FUNCTION public.swl_v53_record_play(uuid,bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.swl_v53_record_play(uuid,bigint,text) TO authenticated;
COMMIT;
