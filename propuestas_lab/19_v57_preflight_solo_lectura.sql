-- Diagnóstico seguro y de solo lectura para Supabase LAB.
-- No crea ni modifica tablas, funciones, permisos ni datos.
SELECT
  current_database() AS database_name,
  to_regprocedure('public.swl_v56_special_play(uuid,bigint,text,uuid,jsonb)') IS NOT NULL AS special_play_installed,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='swl_v57_batted_ball') AS batted_ball_installed,
  (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='public'
    AND table_name='swl_live_games' AND column_name IN
    ('swl_base_players','swl_ghost_player','swl_regulation_innings','swl_allow_roster_ghost')) AS required_game_columns,
  to_regprocedure('public.swl_v56_lock_batting_turn(uuid,bigint)') IS NOT NULL AS turn_lock_present,
  to_regprocedure('public.swl_v56_validate_base_players(boolean[],uuid[])') IS NOT NULL AS base_validation_present;
