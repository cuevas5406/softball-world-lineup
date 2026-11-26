-- Solo LAB, con autorización de reversión. Si ya existe auditoría,
-- usar el procedimiento de deshabilitación descrito en resultados_lab.md.
BEGIN;
SET LOCAL lock_timeout = '5s';
LOCK TABLE public.swl_live_games, public.swl_v57_cancel_decisions IN ACCESS EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM public.swl_v57_cancel_decisions)
     OR EXISTS (SELECT 1 FROM public.swl_live_games
                WHERE status = 'CANCELLED' OR swl_cancel_requested_by IS NOT NULL) THEN
    RAISE EXCEPTION 'Hay solicitudes o cancelaciones. Conservar el esquema y la auditoría.';
  END IF;
END;
$guard$;
DROP FUNCTION public.swl_v57_cancel_game(uuid,bigint,text);
DROP TABLE public.swl_v57_cancel_decisions;
ALTER TABLE public.swl_live_games
  DROP CONSTRAINT swl_live_games_status_check,
  ADD CONSTRAINT swl_live_games_status_check
    CHECK (status IN ('SCHEDULED','IN_PROGRESS','FINAL','OFFICIAL')),
  DROP COLUMN swl_cancel_requested_by;
COMMIT;
