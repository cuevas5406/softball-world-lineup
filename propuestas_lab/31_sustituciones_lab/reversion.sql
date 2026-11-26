-- Reversión de esquema. Conservar altas, códigos y datos deportivos.
BEGIN;
DROP TRIGGER swl_v57_guard_participation_start ON public.swl_live_games;
DROP TRIGGER swl_v57_guard_participation_lineup ON public.swl_game_lineups;
DROP FUNCTION public.swl_v56_change_pitcher(uuid,bigint,uuid,uuid);
DROP FUNCTION swl_private.v57_guard_start();
DROP FUNCTION swl_private.v57_guard_lineup();
DROP FUNCTION swl_private.v57_check_participation(uuid,uuid,uuid[]);
DROP FUNCTION swl_private.v57_lineup_players(public.swl_game_lineups);
DROP TABLE swl_private.v57_participation, swl_private.v57_participation_gate;
COMMIT;
