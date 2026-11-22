-- SOLO LECTURA. Supabase LAB. No modifica datos.
SELECT 'rpc' AS tipo, required.name, EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname=required.name
) AS existe
FROM (VALUES
 ('swl_v56_lock_batting_turn'),('swl_v56_accumulate_pitching'),
 ('swl_v56_add_inning_runs'),('swl_v56_base_occupancy'),
 ('swl_v56_validate_base_players'),('swl_v56_close_after_play'),
 ('swl_v56_special_play'),('swl_v57_batted_ball')
) AS required(name)
UNION ALL
SELECT 'columna',required.name,EXISTS (
 SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public'
 AND c.table_name='swl_live_games' AND c.column_name=required.name
)
FROM (VALUES ('swl_base_players'),('swl_ghost_player'),
 ('swl_allow_roster_ghost'),('swl_regulation_innings'),
 ('swl_super_margin'),('swl_knockout_margin'),('swl_final_half_completed')) AS required(name)
UNION ALL
SELECT 'tabla',required.name,EXISTS (
 SELECT 1 FROM information_schema.tables t WHERE t.table_schema='public'
 AND t.table_name=required.name
)
FROM (VALUES ('swl_v56_pitching_events'),('swl_game_batting_turns'),
 ('swl_v56_match_decisions')) AS required(name)
ORDER BY tipo,name;
