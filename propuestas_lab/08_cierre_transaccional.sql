-- PROPUESTA SIN EJECUTAR. Requiere 06 y revisión del esquema real de LAB.
begin;
alter table public.swl_live_games
  add column swl_regulation_innings integer not null default 6 check (swl_regulation_innings between 1 and 30),
  add column swl_super_margin integer default 15 check (swl_super_margin > 0),
  add column swl_knockout_margin integer default 10 check (swl_knockout_margin > 0),
  add column swl_final_half_completed boolean not null default false,
  add column swl_finish_reason text,
  add column swl_finish_requested_by uuid,
  add column swl_home_signed boolean not null default false,
  add column swl_away_signed boolean not null default false;
create table public.swl_v56_match_decisions (
  game_id uuid not null references public.swl_live_games(id),
  version bigint not null,
  action text not null check (action in ('REQUEST','ACCEPT','REJECT','SIGN','AUTO','INVALIDATED')),
  actor_id uuid not null,
  recorded_at timestamptz not null default now(),
  primary key (game_id, version, action)
);
alter table public.swl_v56_match_decisions enable row level security;
revoke all on public.swl_v56_match_decisions from public, anon, authenticated;

create function public.swl_v56_close_after_play(prior public.swl_live_games)
returns void language plpgsql set search_path = '' as $$
declare
  latest public.swl_live_games%rowtype;
  half_ended boolean;
  lead integer;
  threshold integer;
  reason text;
begin
  select * into strict latest from public.swl_live_games where id = prior.id for update;
  if latest.version is distinct from prior.version + 1 then
    raise exception 'La jugada no generó la versión esperada.';
  end if;
  if latest.status::text is distinct from 'IN_PROGRESS' then return; end if;
  if prior.is_top is null or latest.is_top is null or prior.inning is null or latest.inning is null then
    raise exception 'No se pudo identificar la media entrada.';
  end if;
  half_ended := latest.is_top <> prior.is_top;
  if latest.inning <> prior.inning + (case when half_ended and not prior.is_top then 1 else 0 end) then
    raise exception 'Transición de media entrada incompatible con el marcador.';
  end if;
  lead := latest.home_runs - latest.away_runs;
  threshold := case prior.inning when 3 then latest.swl_super_margin when 4 then latest.swl_knockout_margin end;
  if threshold is not null and
      (case when prior.is_top then half_ended and lead >= threshold
         else lead >= threshold or (half_ended and lead <= -threshold) end) then
    reason := case when prior.inning = 3 then 'Súper knockout' else 'Knockout' end;
  elsif prior.inning >= latest.swl_regulation_innings and
      (case when prior.is_top then half_ended and lead > 0
         else lead > 0 or (half_ended and lead < 0) end) then
    reason := 'Final reglamentario';
  end if;
  if reason is not null then
    update public.swl_live_games
      set status = 'FINAL', inning = prior.inning, is_top = prior.is_top,
          swl_finish_reason = reason, swl_final_half_completed = half_ended,
          swl_finish_requested_by = null
      where id = prior.id;
    insert into public.swl_v56_match_decisions(game_id,version,action,actor_id)
      values (prior.id,latest.version,'AUTO',auth.uid());
  elsif latest.swl_finish_requested_by is not null then
    update public.swl_live_games set swl_finish_requested_by = null where id = prior.id;
    insert into public.swl_v56_match_decisions(game_id,version,action,actor_id)
      values (prior.id,latest.version,'INVALIDATED',auth.uid());
  end if;
end;
$$;
revoke all on function public.swl_v56_close_after_play(public.swl_live_games) from public, anon, authenticated;

create function public.swl_v56_match_decision(p_game_id uuid, p_expected_version bigint, p_action text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  actor uuid := auth.uid();
  is_home boolean;
begin
  select * into g from public.swl_live_games where id = p_game_id for update;
  if not found or actor is null or g.home_manager_id is null or g.away_manager_id is null or
      g.home_manager_id = g.away_manager_id or
      (actor is distinct from g.home_manager_id and actor is distinct from g.away_manager_id) then
    raise exception using errcode = '42501', message = 'Acción reservada a los dos mánagers del partido.';
  end if;
  is_home := actor = g.home_manager_id;
  if public.swl_can_manage_roster(case when is_home then g.home_team_id else g.away_team_id end) is not true then
    raise exception using errcode = '42501', message = 'El permiso del equipo ya no está vigente.';
  end if;
  if g.version is distinct from p_expected_version then
    raise exception 'El partido cambió. Actualiza antes de continuar.';
  end if;
  if p_action = 'SIGN' and g.status::text = 'FINAL' then
    if (case when is_home then g.swl_home_signed else g.swl_away_signed end) then return; end if;
    update public.swl_live_games set swl_home_signed = g.swl_home_signed or is_home,
      swl_away_signed = g.swl_away_signed or not is_home, version = g.version + 1
      where id = g.id;
    if (is_home and g.swl_away_signed) or (not is_home and g.swl_home_signed) then
      update public.swl_live_games set status = 'OFFICIAL' where id = g.id;
    end if;
  elsif g.status::text = 'IN_PROGRESS' and g.inning >= 5 and g.home_runs <> g.away_runs then
    if p_action = 'REQUEST' and g.swl_finish_requested_by is null then
      update public.swl_live_games set swl_finish_requested_by = actor, version = g.version + 1 where id = g.id;
    elsif p_action in ('ACCEPT','REJECT') and g.swl_finish_requested_by is not null and
        g.swl_finish_requested_by <> actor then
      update public.swl_live_games set swl_finish_requested_by = null, version = g.version + 1 where id = g.id;
      if p_action = 'ACCEPT' then
        update public.swl_live_games set status = 'FINAL', swl_finish_reason = 'Acuerdo de ambos mánagers'
          where id = g.id;
      end if;
    else
      raise exception 'No hay una solicitud válida para esta acción.';
    end if;
  else
    raise exception 'El partido no admite esta acción.';
  end if;
  insert into public.swl_v56_match_decisions(game_id,version,action,actor_id)
    values (g.id,g.version+1,p_action,actor);
end;
$$;
revoke all on function public.swl_v56_match_decision(uuid,bigint,text) from public, anon;
grant execute on function public.swl_v56_match_decision(uuid,bigint,text) to authenticated;

-- Los wrappers se reemplazan en la misma migración. Se conserva la jugada y se
-- acredita el pitcheo antes de corregir la media entrada terminal.
create or replace function public.swl_v56_record_plate_action(
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
  perform public.swl_v56_close_after_play(g);
end;
$$;

create or replace function public.swl_v56_apply_hit(
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
  perform public.swl_v56_close_after_play(g);
end;
$$;

commit;
