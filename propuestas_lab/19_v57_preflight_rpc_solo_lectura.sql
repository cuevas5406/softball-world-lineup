-- Verificación SOLO LECTURA de dependencias de jugadas especiales.
-- Ejecutar exclusivamente en Supabase LAB; no crea ni altera objetos.
WITH expected(name, args) AS (
 VALUES
 ('swl_v56_lock_batting_turn','uuid,bigint'),
 ('swl_v56_validate_base_players','boolean[],uuid[]'),
 ('swl_v56_add_inning_runs','jsonb,integer,integer'),
 ('swl_v56_accumulate_pitching','swl_live_games,uuid,text'),
 ('swl_v56_close_after_play','swl_live_games'),
 ('swl_v53_substitute_batter','uuid,uuid,integer,uuid,uuid,bigint,bigint'),
 ('swl_v56_special_play','uuid,bigint,text,uuid,jsonb')
)
SELECT name, to_regprocedure('public.'||name||'('||args||')') IS NOT NULL AS installed
FROM expected ORDER BY name;
SELECT column_name, udt_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='swl_live_games'
AND column_name IN ('swl_base_players','swl_ghost_player','swl_regulation_innings',
 'swl_allow_roster_ghost','bases_state','home_runs','away_runs','outs','balls','strikes','version')
ORDER BY column_name;
-- Verificar que no se exponga EXECUTE a PUBLIC/anon al instalar la RPC.
SELECT p.proname, has_function_privilege('anon',p.oid,'EXECUTE') AS anon_can_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_can_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='swl_v56_special_play';
