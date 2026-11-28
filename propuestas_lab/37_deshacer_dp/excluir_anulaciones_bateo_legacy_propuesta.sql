-- Propuesta adicional. Pendiente de autorización exclusiva para LAB.
CREATE OR REPLACE FUNCTION public.swl_v53_batting_stats(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); g public.swl_live_games%rowtype; output jsonb;
begin
 if uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 select * into g from public.swl_live_games where id=p_game_id;
 if not found then raise exception 'GAME_NOT_FOUND'; end if;
 if uid is distinct from g.home_manager_id and uid is distinct from g.away_manager_id then
 raise exception 'NOT_GAME_MANAGER' using errcode='42501'; end if;
 with tagged as (
 select e.event_type,e.event_data, e.batting_team_id,
 (e.event_data->>'batter_id')::uuid as player_id,
 coalesce((e.event_data->>'plate_appearance_completed')::boolean,false) as completed,
 (e.event_data->>'batter_base')::int as hit_bases
 from public.swl_game_events e
 where e.game_id=p_game_id and e.event_data ? 'batter_id'
   and e.version <= g.version
   and not exists (
     select 1 from public.swl_game_events correction
     where correction.game_id=e.game_id
       and correction.event_type='UNDO_OUT'
       and correction.version<=g.version
       and correction.event_data->>'reverts_version'=e.version::text
   )
 ), grouped as (
 select player_id,batting_team_id,
 count(*) filter(where event_type='HIT' and hit_bases between 1 and 4)::int as hits,
 count(*) filter(where event_type='HIT' and hit_bases=1)::int as singles,
 count(*) filter(where event_type='HIT' and hit_bases=2)::int as doubles,
 count(*) filter(where event_type='HIT' and hit_bases=3)::int as triples,
 count(*) filter(where event_type='HIT' and hit_bases=4)::int as home_runs,
 count(*) filter(where event_type='BALL' and completed)::int as walks,
 count(*) filter(where event_type='STRIKE' and completed)::int as strikeouts,
 count(*) filter(where event_type='HIT' or (event_type in ('STRIKE','OUT') and completed))::int as at_bats,
 count(*) filter(where event_type='HIT' or completed)::int as plate_appearances
 from tagged group by player_id,batting_team_id
 )
 select coalesce(jsonb_agg(to_jsonb(grouped) order by batting_team_id,player_id),'[]'::jsonb)
 into output from grouped;
 return output;
end $function$;
