-- Preparado, no ejecutado. Inspección exclusiva de LAB.
begin read only;
select game_pin, status, version, inning, is_top, home_team_id, away_team_id,
       home_manager_id is not null as local_asignado,
       away_manager_id is not null as visitante_asignado,
       home_manager_id is distinct from away_manager_id as cuentas_distintas
from public.swl_live_games where game_pin = 'SWL-266746';

select g.game_pin, l.team_id, l.revision,
       case when jsonb_typeof(l.lineup) = 'array' then jsonb_array_length(l.lineup) end as bateadores
from public.swl_live_games g left join public.swl_game_lineups l on l.game_id = g.id
where g.game_pin = 'SWL-266746';

select table_name, column_name, data_type, udt_name, column_default
from information_schema.columns
where table_schema = 'public' and table_name in ('players','teams','rosters','swl_live_games','swl_game_lineups','swl_game_events')
order by table_name, ordinal_position;

select p.oid::regprocedure as signature, p.prosecdef, p.proacl, pg_get_functiondef(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prokind = 'f'
  and p.proname ~ '^swl_.*(register_player|universal_id|sign_player|can_manage_roster|create_game|join_game|start_game|record_plate_action|apply_hit_for_player|save_lineup_checked|final|result|approve)';

select tgname, pg_get_triggerdef(oid) from pg_trigger
where tgrelid = 'public.players'::regclass and not tgisinternal;
select count(*) as swl_numericos,
       max(substring(universal_id from '^SWL-([0-9]+)$')::numeric) as mayor_sufijo,
       count(*) filter (where universal_id = 'SWL-0009') as codigo_0009
from public.players where universal_id ~ '^SWL-[0-9]+$';
select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies where (schemaname = 'public' and tablename like 'swl_%')
   or (schemaname = 'storage' and tablename = 'objects');
select * from pg_publication_tables where pubname = 'supabase_realtime';
rollback;
