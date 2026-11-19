-- PROPUESTA PARA LAB. NO APLICADA. Requiere 01 e inspección de las RPC V5.3.
begin;
create table public.swl_v56_pitching_events (
  game_id uuid not null references public.swl_live_games(id),
  version bigint not null,
  pitcher_id uuid not null references public.players(id),
  outs integer not null check (outs between 0 and 3),
  strikes_out integer not null check (strikes_out between 0 and 1),
  walks integer not null check (walks between 0 and 1),
  hits integer not null check (hits between 0 and 1),
  primary key (game_id, version)
);
alter table public.swl_v56_pitching_events enable row level security;
revoke all on public.swl_v56_pitching_events from public, anon, authenticated;
grant select on public.swl_v56_pitching_events to authenticated;
create policy swl_v56_pitching_events_read on public.swl_v56_pitching_events
for select to authenticated using (
  exists (select 1 from public.swl_game_lineups l where l.game_id = swl_v56_pitching_events.game_id)
);

create function public.swl_v56_lock_batting_turn(p_game_id uuid, p_expected_version bigint)
returns public.swl_live_games
language plpgsql set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  actor uuid := auth.uid();
  batting_team uuid;
begin
  select * into g from public.swl_live_games where id = p_game_id for update;
  if not found or actor is null or g.is_top is null or g.home_manager_id is null
      or g.away_manager_id is null or g.home_manager_id = g.away_manager_id
      or g.home_team_id is null or g.away_team_id is null or g.home_team_id = g.away_team_id
      or (case when g.is_top then g.away_manager_id else g.home_manager_id end) is distinct from actor then
    raise exception using errcode = '42501', message = 'Solo anota el mánager del equipo al bate.';
  end if;
  batting_team := case when g.is_top then g.away_team_id else g.home_team_id end;
  if public.swl_can_manage_roster(batting_team) is not true then
    raise exception using errcode = '42501', message = 'La autorización del equipo ya no está vigente.';
  end if;
  if g.status::text is distinct from 'IN_PROGRESS' or g.version is distinct from p_expected_version then
    raise exception 'El partido o la versión cambió antes de anotar.';
  end if;
  return g;
end;
$$;

create function public.swl_v56_accumulate_pitching(
  prior public.swl_live_games, p_pitcher_id uuid, p_action text
) returns void language plpgsql set search_path = '' as $$
declare
  latest public.swl_live_games%rowtype;
  made integer;
begin
  select * into strict latest from public.swl_live_games where id = prior.id;
  if latest.version is distinct from prior.version + 1 then
    raise exception 'La anotación no generó la versión esperada.';
  end if;
  if p_pitcher_id is null then return; end if;
  made := case when latest.is_top is distinct from prior.is_top or latest.inning is distinct from prior.inning
               then 3 - prior.outs else latest.outs - prior.outs end;
  insert into public.swl_v56_pitching_events(game_id, version, pitcher_id, outs, strikes_out, walks, hits)
    values (prior.id, latest.version, p_pitcher_id, made,
            case when p_action = 'STRIKE' and prior.strikes = 2 then 1 else 0 end,
            case when p_action = 'BALL' and prior.balls = 3 then 1 else 0 end,
            case when p_action = 'HIT' then 1 else 0 end);
end;
$$;

create function public.swl_v56_record_plate_action(
  p_game_id uuid, p_expected_version bigint, p_action text, p_batter_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  pitcher uuid;
begin
  g := public.swl_v56_lock_batting_turn(p_game_id, p_expected_version);
  if p_action is null or p_action not in ('BALL','STRIKE','OUT') then raise exception 'Jugada inválida.'; end if;
  select pitcher_id into pitcher from public.swl_game_lineups where game_id = p_game_id
    and team_id = (case when g.is_top then g.home_team_id else g.away_team_id end);
  perform public.swl_v53_record_plate_action(p_game_id => p_game_id, p_expected_version => p_expected_version,
      p_action => p_action, p_batter_id => p_batter_id);
  perform public.swl_v56_accumulate_pitching(g, pitcher, p_action);
end;
$$;

create function public.swl_v56_apply_hit(
  p_game_id uuid, p_expected_version bigint, p_batter_id uuid, p_batter_base integer,
  p_first_to integer, p_second_to integer, p_third_to integer
) returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  pitcher uuid;
begin
  g := public.swl_v56_lock_batting_turn(p_game_id, p_expected_version);
  select pitcher_id into pitcher from public.swl_game_lineups where game_id = p_game_id
    and team_id = (case when g.is_top then g.home_team_id else g.away_team_id end);
  perform public.swl_v53_apply_hit_for_player(p_game_id => p_game_id, p_expected_version => p_expected_version,
    p_batter_id => p_batter_id, p_batter_base => p_batter_base,
    p_first_to => p_first_to, p_second_to => p_second_to, p_third_to => p_third_to);
  perform public.swl_v56_accumulate_pitching(g, pitcher, 'HIT');
end;
$$;

revoke all on function public.swl_v56_lock_batting_turn(uuid,bigint),
  public.swl_v56_accumulate_pitching(public.swl_live_games,uuid,text),
  public.swl_v56_record_plate_action(uuid,bigint,text,uuid),
  public.swl_v56_apply_hit(uuid,bigint,uuid,integer,integer,integer,integer) from public, anon, authenticated;
grant execute on function public.swl_v56_record_plate_action(uuid,bigint,text,uuid),
  public.swl_v56_apply_hit(uuid,bigint,uuid,integer,integer,integer,integer) to authenticated;
-- Tras probar los contratos y planificar la retirada de APK anteriores,
-- revocar el acceso público a rutas V5.3 de escritura que la revisión confirme redundantes.
commit;
