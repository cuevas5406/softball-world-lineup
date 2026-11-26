-- PROPUESTA PARA LAB. NO APLICADA. Requiere autorización específica.
-- Conserva el cursor, la versión, el permiso del mánager y las estadísticas previas.
-- La función de pitcher usa la bitácora ya instalada en LAB.
-- La guarda de UUID también cubre a los clientes que llaman directamente
-- a la función heredada. Solo comprueba al entrante en una alineación rival.
-- Las filas existentes, incluido SWL-567892, quedan fuera de esta propuesta.
begin;

CREATE OR REPLACE FUNCTION public.swl_v53_substitute_batter(p_game_id uuid, p_team_id uuid, p_batting_order integer, p_outgoing_id uuid, p_incoming_id uuid, p_expected_revision bigint, p_expected_game_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 g public.swl_live_games%rowtype; l public.swl_game_lineups%rowtype;
 uid uuid:=auth.uid(); n integer; slot jsonb; new_revision bigint; new_version bigint;
begin
 if uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 select * into g from public.swl_live_games where id=p_game_id for update;
 if not found then raise exception 'GAME_NOT_FOUND'; end if;
 if g.status in ('FINAL','OFFICIAL') then raise exception 'GAME_CLOSED'; end if;
 if g.version is distinct from p_expected_game_version then
   raise exception 'STALE_GAME_VERSION' using errcode='40001'; end if;
 if not ((p_team_id=g.home_team_id and uid=g.home_manager_id) or
         (p_team_id=g.away_team_id and uid=g.away_manager_id)) then
   raise exception 'NOT_TEAM_MANAGER' using errcode='42501'; end if;
 if not (exists(select 1 from public.team_admins where team_id=p_team_id and user_id=uid and status='active')
   or exists(select 1 from public.team_managers where team_id=p_team_id and user_id=uid
      and status='active' and starts_at<=now() and (expires_at is null or expires_at>now()))) then
   raise exception 'TEAM_PERMISSION_REVOKED' using errcode='42501'; end if;
 select * into l from public.swl_game_lineups where game_id=p_game_id and team_id=p_team_id for update;
 if not found then raise exception 'LINEUP_REQUIRED'; end if;
 if l.revision is distinct from p_expected_revision then
   raise exception 'STALE_LINEUP_REVISION' using errcode='40001'; end if;
 n:=jsonb_array_length(l.lineup);
 if p_batting_order not between 1 and n then raise exception 'INVALID_BATTING_SLOT'; end if;
 slot:=l.lineup->(p_batting_order-1);
 if (slot->>'player_id')::uuid is distinct from p_outgoing_id then
   raise exception 'OUTGOING_PLAYER_NOT_IN_SLOT'; end if;
 if p_incoming_id is null or p_incoming_id=p_outgoing_id then raise exception 'INVALID_INCOMING_PLAYER'; end if;
 if exists(select 1 from jsonb_array_elements(l.lineup) s where s->>'player_id'=p_incoming_id::text) then
   raise exception 'INCOMING_PLAYER_ALREADY_IN_LINEUP'; end if;
 if p_incoming_id in (l.pitcher_id,l.designated_hitter_id)
    or l.defensive_positions ? p_incoming_id::text then
   raise exception 'INCOMING_PLAYER_ALREADY_IN_LINEUP';
 end if;
 if not exists(select 1 from public.rosters r where r.team_id=p_team_id
    and r.player_id=p_incoming_id and r.removed_at is null) then
   raise exception 'INCOMING_PLAYER_NOT_ON_ACTIVE_ROSTER'; end if;
  if exists (
    select 1
    from public.swl_game_lineups rival
    where rival.game_id = p_game_id and rival.team_id <> p_team_id
      and (p_incoming_id in (rival.pitcher_id, rival.designated_hitter_id)
        or rival.defensive_positions ? p_incoming_id::text
        or exists (
          select 1 from jsonb_array_elements(rival.lineup) as slot(item)
          where slot.item->>'player_id' = p_incoming_id::text
        ))
  ) then
    raise exception 'PELOTERO_EN_AMBOS_EQUIPOS';
  end if;
 if exists(select 1 from public.swl_game_events e where e.game_id=p_game_id
    and e.batting_team_id=p_team_id and e.event_type='SUBSTITUTION'
    and e.event_data->>'outgoing_player_id'=p_incoming_id::text) then
   raise exception 'REENTRY_NOT_SUPPORTED'; end if;
 update public.swl_game_lineups set
    lineup=jsonb_set(l.lineup,array[(p_batting_order-1)::text,'player_id'],to_jsonb(p_incoming_id::text)),
    revision=revision+1,submitted_by=uid,updated_at=now()
 where game_id=p_game_id and team_id=p_team_id returning revision into new_revision;
 update public.swl_live_games set version=version+1,updated_at=now()
 where id=p_game_id returning version into new_version;
 insert into public.swl_game_events(game_id,actor_id,batting_team_id,inning,is_top,event_type,event_data,version)
 values(p_game_id,uid,p_team_id,g.inning,g.is_top,'SUBSTITUTION',
 jsonb_build_object('batting_order',p_batting_order,'outgoing_player_id',p_outgoing_id,
 'incoming_player_id',p_incoming_id,'lineup_revision',new_revision),new_version);
 return jsonb_build_object('game_id',p_game_id,'team_id',p_team_id,
 'batting_order',p_batting_order,'revision',new_revision,'version',new_version);
end $function$;

create or replace function public.swl_v56_change_pitcher(
  p_game_id uuid, p_expected_version bigint, p_team_id uuid, p_player_id uuid
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  l public.swl_game_lineups%rowtype;
  actor uuid := auth.uid();
  previous_position text;
  current_pitcher_position text;
  candidate_in_order boolean;
  current_pitcher_in_order boolean;
begin
  select * into g from public.swl_live_games where id = p_game_id for update;
  if not found or actor is null or g.is_top is null or p_team_id is null
      or (case when g.is_top then g.home_team_id else g.away_team_id end) is distinct from p_team_id
      or (case when g.is_top then g.home_manager_id else g.away_manager_id end) is distinct from actor
      or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Cambio reservado al mánager del equipo a la defensa.';
  end if;
  if g.status::text is distinct from 'IN_PROGRESS' or g.version is distinct from p_expected_version
      or g.balls is distinct from 0 or g.strikes is distinct from 0 then
    raise exception 'Cambia el pitcher entre bateadores, con la versión actual del marcador.';
  end if;
  select * into l from public.swl_game_lineups
    where game_id = p_game_id and team_id = p_team_id for update;
  if not found or l.pitcher_id is null or l.pitcher_id = p_player_id
      or not exists (select 1 from public.rosters where team_id = p_team_id
                    and player_id = p_player_id and removed_at is null) then
    raise exception 'El nuevo pitcher debe pertenecer al roster activo y ser distinto del actual.';
  end if;
  previous_position := l.defensive_positions ->> p_player_id::text;
  current_pitcher_position := l.defensive_positions ->> l.pitcher_id::text;
  if current_pitcher_position is distinct from 'P' then
    raise exception 'La defensa actual no identifica al pitcher en P.';
  end if;
  select exists(select 1 from jsonb_array_elements(l.lineup) s
                where s ->> 'player_id' = p_player_id::text) into candidate_in_order;
  select exists(select 1 from jsonb_array_elements(l.lineup) s
                where s ->> 'player_id' = l.pitcher_id::text) into current_pitcher_in_order;
  if current_pitcher_in_order is distinct from l.pitcher_bats
      or candidate_in_order is distinct from l.pitcher_bats
      or (l.pitcher_bats and previous_position is null)
      or (not l.pitcher_bats and previous_position is not null)
      or previous_position = 'P'
      or p_player_id = l.designated_hitter_id then
    raise exception 'El cambio de pitcher debe preservar el orden de bateo y el DH.';
  end if;
  if exists (
    select 1
    from public.swl_game_lineups rival
    where rival.game_id = p_game_id and rival.team_id <> p_team_id
      and (p_player_id in (rival.pitcher_id, rival.designated_hitter_id)
        or rival.defensive_positions ? p_player_id::text
        or exists (
          select 1 from jsonb_array_elements(rival.lineup) as slot(item)
          where slot.item->>'player_id' = p_player_id::text
        ))
  ) then
    raise exception 'PELOTERO_EN_AMBOS_EQUIPOS';
  end if;

  if exists (
    select 1 from public.swl_game_events e
    where e.game_id=p_game_id and e.batting_team_id=p_team_id
      and e.event_type='SUBSTITUTION' and e.event_data->>'outgoing_player_id'=p_player_id::text
  ) then
    raise exception 'REENTRY_NOT_SUPPORTED';
  end if;
  update public.swl_game_lineups
    set pitcher_id = p_player_id, revision = l.revision + 1, updated_at = now(),
        defensive_positions = (l.defensive_positions - l.pitcher_id::text)
          || jsonb_build_object(p_player_id::text, 'P')
          || case when previous_position is not null
               then jsonb_build_object(l.pitcher_id::text, previous_position)
               else '{}'::jsonb end
    where game_id = p_game_id and team_id = p_team_id;
  insert into public.swl_v56_pitcher_changes
    (game_id, team_id, version, old_pitcher_id, new_pitcher_id, innings_number, actor_id)
    values (p_game_id, p_team_id, g.version + 1, l.pitcher_id, p_player_id, g.inning, actor);
  update public.swl_live_games set version = g.version + 1 where id = p_game_id;
end;
$$;
revoke all on function public.swl_v56_change_pitcher(uuid,bigint,uuid,uuid) from public, anon;
grant execute on function public.swl_v56_change_pitcher(uuid,bigint,uuid,uuid) to authenticated;

commit;
