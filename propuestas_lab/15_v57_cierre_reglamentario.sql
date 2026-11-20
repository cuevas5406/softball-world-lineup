-- Propuesta V5.7 sin ejecutar. Actualiza el evaluador y sus dos adaptadores.
-- Conserva los adaptadores de 09 y conecta la anotación al cierre en la misma
-- transacción. Verificar estas firmas, permisos y dependencias antes de aplicar.
-- No recalcula resultados históricos ni escribe firmas.
begin;
create or replace function public.swl_v56_close_after_play(prior public.swl_live_games)
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
  if threshold > 0 and
      (case when prior.is_top then half_ended and lead >= threshold
         else lead >= threshold or (half_ended and lead <= -threshold) end) then
    reason := case when prior.inning = 3 then 'Súper knockout' else 'Knockout' end;
  elsif prior.inning >= latest.swl_regulation_innings then
    -- La alta terminada puede cerrar el partido con ventaja local, sin
    -- abrir la baja. Una alta empatada o con ventaja visitante continúa.
    if (prior.is_top and half_ended and lead > 0)
        or (not prior.is_top and (lead > 0 or (half_ended and lead < 0))) then
      reason := 'Final reglamentario';
    end if;
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
  perform public.swl_v56_track_base_players(g,p_action,p_batter_id,null,null,null,null);
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
  perform public.swl_v56_track_base_players(g,'HIT',p_batter_id,p_batter_base,p_first_to,p_second_to,p_third_to);
  perform public.swl_v56_accumulate_pitching(g, pitcher, 'HIT');
  perform public.swl_v56_close_after_play(g);
end;
$$;

commit;
