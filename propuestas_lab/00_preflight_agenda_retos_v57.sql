-- SOLO LECTURA. Ejecutar manualmente en LAB si se autoriza el diagnóstico.
-- No crea ni modifica objetos. No ejecutar en producción.
select 'tabla_retos' as verificacion,
       to_regclass('public.swl_v56_challenges')::text as resultado;
select p.proname as funcion,
       pg_get_function_identity_arguments(p.oid) as firma,
       p.prosecdef as security_definer
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('swl_can_manage_roster','swl_v5_create_game',
                   'swl_v56_send_challenge','swl_v56_act_challenge')
order by p.proname;
select tablename, policyname, roles, cmd
from pg_policies
where schemaname='public' and tablename in ('teams','swl_live_games','swl_v56_challenges')
order by tablename, policyname;
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema='public' and table_name in ('teams','swl_live_games','swl_v56_challenges')
  and column_name in ('id','created_by','home_team_id','away_team_id','game_id','status')
order by table_name,column_name;

-- Auditoría de permisos de ejecución y dueño de funciones sensibles (solo lectura).
select p.proname as funcion, pg_get_userbyid(p.proowner) as propietario,
       p.prosecdef as security_definer, p.proconfig as configuracion,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_puede_ejecutar,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as autenticado_puede_ejecutar
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname = 'public' and p.proname in (
  'swl_can_manage_roster', 'swl_v5_create_game',
  'swl_v56_send_challenge', 'swl_v56_act_challenge')
order by p.proname;
