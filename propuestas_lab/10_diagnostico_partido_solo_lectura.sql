-- Diagnóstico preparado y no ejecutado. Requiere autorización para consultar LAB.
begin read only;
select id, game_pin, version, status, inning, is_top, outs, home_runs, away_runs,
       home_innings, away_innings
from public.swl_live_games where game_pin = 'SWL-095994';

select e.inning,e.is_top,e.event_type,count(*) as cantidad,
       min(e.version) as primera_version,max(e.version) as ultima_version
from public.swl_game_events e join public.swl_live_games g on g.id = e.game_id
where g.game_pin = 'SWL-095994'
group by e.inning,e.is_top,e.event_type
order by e.inning,e.is_top desc,e.event_type;

select e.version,count(*) as cantidad
from public.swl_game_events e join public.swl_live_games g on g.id = e.game_id
where g.game_pin = 'SWL-095994'
group by e.version having count(*) > 1
order by e.version;
rollback;
