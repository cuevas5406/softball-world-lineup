-- Requiere dos partidos programados de prueba con alineaciones confirmadas
-- que comparten UUID. Abrir dos conexiones PostgreSQL independientes.
-- Sesión A. Sustituir el PIN de la primera fixture si se recrea.
BEGIN;
SELECT set_config('request.jwt.claim.sub',home_manager_id::text,true)
  FROM public.swl_live_games WHERE game_pin='SWL-998191';
SELECT public.swl_v56_start_game(id,0) FROM public.swl_live_games WHERE game_pin='SWL-998191';
SELECT pg_sleep(6);
COMMIT;
-- Ejecutar B durante la pausa de A. El inicio debe esperar y ser rechazado.
DO $test$
DECLARE g public.swl_live_games%rowtype;
BEGIN
  SELECT * INTO STRICT g FROM public.swl_live_games WHERE game_pin='SWL-998192';
  PERFORM set_config('request.jwt.claim.sub',g.home_manager_id::text,true);
  BEGIN
    PERFORM public.swl_v56_start_game(g.id,0);
    RAISE SQLSTATE 'ZX013' USING MESSAGE='Ambos partidos aceptaron los mismos UUID';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO' THEN RAISE; END IF;
  END;
END
$test$;
