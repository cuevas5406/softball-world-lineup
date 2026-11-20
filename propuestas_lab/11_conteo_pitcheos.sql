-- Propuesta para LAB, sin ejecutar. Requiere 06, 08 y las RPC de anotación vigentes.
-- Revisar compatibilidad de event_type con FOUL antes de aplicar.
begin;
alter table public.swl_v56_pitching_events
  add column pitch_count integer,
  add column pitch_balls integer,
  add column pitch_strikes integer,
  add column pitch_in_play integer,
  add constraint swl_pitch_total check (
    (pitch_count is null and pitch_balls is null and pitch_strikes is null and pitch_in_play is null) or
    (pitch_count between 0 and 1 and pitch_balls in (0,1) and pitch_strikes in (0,1)
      and pitch_count is not null and pitch_balls is not null and pitch_strikes is not null
      and pitch_in_play is not null and pitch_in_play in (0,1)
      and pitch_count = pitch_balls + pitch_strikes + pitch_in_play)
  );

create or replace function public.swl_v56_accumulate_pitching(
  prior public.swl_live_games, p_pitcher_id uuid, p_action text
) returns void language plpgsql set search_path = '' as $$
declare
  latest public.swl_live_games%rowtype;
  made integer;
  ball integer := case when p_action = 'BALL' then 1 else 0 end;
  strike integer := case when p_action in ('STRIKE','FOUL') then 1 else 0 end;
  in_play integer := case when p_action in ('HIT','OUT','SACRIFICE_FLY','DOUBLE_PLAY') then 1 else 0 end;
begin
  select * into strict latest from public.swl_live_games where id = prior.id;
  if latest.version is distinct from prior.version + 1 then
    raise exception 'La anotación no generó la versión esperada.';
  end if;
  if p_pitcher_id is null then return; end if;
  made := case when latest.is_top is distinct from prior.is_top or latest.inning is distinct from prior.inning
               then 3 - prior.outs else latest.outs - prior.outs end;
  insert into public.swl_v56_pitching_events(game_id, version, pitcher_id, outs, strikes_out, walks, hits, pitch_count, pitch_balls, pitch_strikes, pitch_in_play)
    values (prior.id, latest.version, p_pitcher_id, made,
            case when p_action = 'STRIKE' and prior.strikes = 2 then 1 else 0 end,
            case when p_action = 'BALL' and prior.balls = 3 then 1 else 0 end,
            case when p_action = 'HIT' then 1 else 0 end, ball + strike + in_play, ball, strike, in_play);
end;
$$;

create function public.swl_v56_record_foul(
  p_game_id uuid, p_expected_version bigint, p_action text, p_batter_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  team uuid;
  pitcher uuid;
begin
  if p_action is distinct from 'FOUL' then raise exception 'Jugada inválida.'; end if;
  g := public.swl_v56_lock_batting_turn(p_game_id,p_expected_version);
  team := case when g.is_top then g.away_team_id else g.home_team_id end;
  if p_batter_id is null or not exists (
    select 1 from public.swl_game_lineups l
    left join public.swl_game_batting_turns t on t.game_id = l.game_id and t.team_id = l.team_id
    cross join lateral jsonb_array_elements(l.lineup) slot
    where l.game_id = g.id and l.team_id = team
      and (slot ->> 'order')::integer = coalesce(t.next_order,1)
      and slot ->> 'player_id' = p_batter_id::text
  ) then raise exception 'El bateador cambió.'; end if;
  select pitcher_id into pitcher from public.swl_game_lineups where game_id = g.id
    and team_id = (case when g.is_top then g.home_team_id else g.away_team_id end);
  update public.swl_live_games set strikes = least(g.strikes + 1,2),
    version = g.version + 1, updated_at = now() where id = g.id;
  insert into public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
    values(g.id,auth.uid(),team,g.inning,g.is_top,'FOUL',
      jsonb_build_object('batter_id',p_batter_id,'plate_appearance_completed',false),g.version+1);
  perform public.swl_v56_accumulate_pitching(g,pitcher,'FOUL');
  perform public.swl_v56_close_after_play(g);
end;
$$;
revoke all on function public.swl_v56_record_foul(uuid,bigint,text,uuid) from public,anon;
grant execute on function public.swl_v56_record_foul(uuid,bigint,text,uuid) to authenticated;
commit;
