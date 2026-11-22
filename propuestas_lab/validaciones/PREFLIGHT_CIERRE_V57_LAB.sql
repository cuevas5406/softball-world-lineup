-- Solo lectura: verificar contratos y dependencias antes de instalar cierre V5.7.
select 'rpc' as tipo, p.proname as objeto, pg_get_function_identity_arguments(p.oid) as detalle,
       pg_get_function_result(p.oid) as resultado
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
('swl_v56_lock_batting_turn','swl_v56_accumulate_pitching','swl_v56_track_base_players',
 'swl_v56_close_after_play','swl_v56_record_plate_action','swl_v56_apply_hit',
 'swl_v53_record_plate_action','swl_v53_apply_hit_for_player')
order by p.proname;
select c.column_name,c.data_type,c.is_nullable
from information_schema.columns c
where c.table_schema='public' and c.table_name='swl_live_games' and
c.column_name in ('swl_regulation_innings','swl_super_margin','swl_knockout_margin',
'swl_final_half_completed','swl_finish_reason','swl_finish_requested_by',
'swl_home_signed','swl_away_signed','swl_base_players')
order by c.column_name;
select conname,pg_get_constraintdef(oid) as definition
from pg_constraint where conrelid='public.swl_v56_match_decisions'::regclass;
