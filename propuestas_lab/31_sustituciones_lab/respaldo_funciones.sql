-- Respaldo de las funciones instaladas antes de agregar las validaciones de participación.
-- Las funciones respaldadas se conservan sin cambios en esta instalación.
-- swl_v53_save_lineup_checked(uuid,uuid,uuid[],bigint) · MD5 c7461f50f8000fe285033d4ad09bdda1 · ACL {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.swl_v53_save_lineup_checked(p_game_id uuid, p_team_id uuid, p_player_ids uuid[], p_expected_revision bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare current_revision bigint; result jsonb; g public.swl_live_games%rowtype;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 select * into g from public.swl_live_games where id=p_game_id for update;
 if not found then raise exception 'GAME_NOT_FOUND'; end if;
 if p_team_id is distinct from g.home_team_id and p_team_id is distinct from g.away_team_id then
   raise exception 'TEAM_NOT_IN_GAME'; end if;
 if exists(select 1 from public.swl_game_events e
   where e.game_id=p_game_id and e.batting_team_id=p_team_id
     and e.event_data ? 'batter_id') then
   raise exception 'LINEUP_LOCKED_AFTER_FIRST_PLATE_ACTION' using errcode='23514';
 end if;
 select revision into current_revision from public.swl_game_lineups
 where game_id=p_game_id and team_id=p_team_id for update;
 if coalesce(current_revision,0) is distinct from p_expected_revision then
   raise exception 'STALE_LINEUP_REVISION' using errcode='40001'; end if;
 result:=public.swl_v53_save_lineup(p_game_id,p_team_id,p_player_ids);
 return result;
end $function$;

-- swl_v53_save_lineup(uuid,uuid,uuid[]) · MD5 b516fc0639ce1bd8184b31bfb943e287 · ACL {postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.swl_v53_save_lineup(p_game_id uuid, p_team_id uuid, p_player_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare g public.swl_live_games%rowtype; uid uuid:=auth.uid(); n integer; valid_n integer; new_revision bigint;
begin
 if uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 select * into g from public.swl_live_games where id=p_game_id for update;
 if not found then raise exception 'GAME_NOT_FOUND'; end if;
 if g.status in ('FINAL','OFFICIAL') then raise exception 'GAME_CLOSED'; end if;
 if not ((p_team_id=g.home_team_id and uid=g.home_manager_id) or (p_team_id=g.away_team_id and uid=g.away_manager_id)) then
 raise exception 'NOT_TEAM_MANAGER' using errcode='42501'; end if;
 if not (exists(select 1 from public.team_admins where team_id=p_team_id and user_id=uid and status='active')
 or exists(select 1 from public.team_managers where team_id=p_team_id and user_id=uid and status='active' and starts_at<=now() and (expires_at is null or expires_at>now()))) then
 raise exception 'TEAM_PERMISSION_REVOKED' using errcode='42501'; end if;
 n:=coalesce(array_length(p_player_ids,1),0);
 if n<9 or n>13 then raise exception 'LINEUP_SIZE_INVALID'; end if;
 if exists(select 1 from unnest(p_player_ids) p where p is null) or
 (select count(distinct p) from unnest(p_player_ids) p)<>n then raise exception 'LINEUP_DUPLICATE_OR_NULL'; end if;
 select count(distinct r.player_id) into valid_n from public.rosters r where r.team_id=p_team_id and r.removed_at is null and r.player_id=any(p_player_ids);
 if valid_n<>n then raise exception 'PLAYER_NOT_ACTIVE_ON_TEAM'; end if;
 insert into public.swl_game_lineups(game_id,team_id,lineup,submitted_by)
 values(p_game_id,p_team_id,(select jsonb_agg(jsonb_build_object('order',ord,'player_id',pid) order by ord) from unnest(p_player_ids) with ordinality as t(pid,ord)),uid)
 on conflict(game_id,team_id) do update set lineup=excluded.lineup,submitted_by=excluded.submitted_by,revision=public.swl_game_lineups.revision+1,updated_at=now()
 returning revision into new_revision;
 return jsonb_build_object('game_id',p_game_id,'team_id',p_team_id,'revision',new_revision,'count',n);
end $function$;

-- swl_v53_substitute_batter(uuid,uuid,integer,uuid,uuid,bigint,bigint) · MD5 f6c692905588b041e01eb7361f967b2b · ACL {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
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
 if not exists(select 1 from public.rosters r where r.team_id=p_team_id
    and r.player_id=p_incoming_id and r.removed_at is null) then
   raise exception 'INCOMING_PLAYER_NOT_ON_ACTIVE_ROSTER'; end if;
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

-- swl_v56_start_game(uuid,bigint) · MD5 af31a4839505a34ef5c0e174b0971f54 · ACL {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.swl_v56_start_game(p_game_id uuid, p_expected_version bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE g public.swl_live_games%rowtype; actor uuid:=auth.uid();
BEGIN
 SELECT * INTO g FROM public.swl_live_games WHERE id=p_game_id FOR UPDATE;
 IF NOT FOUND OR actor IS NULL OR g.home_manager_id IS DISTINCT FROM actor
   OR public.swl_can_manage_roster(g.home_team_id) IS DISTINCT FROM true
 THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='NOT_HOME_MANAGER'; END IF;
 IF g.status='IN_PROGRESS' THEN RETURN; END IF;
 IF g.status<>'SCHEDULED' OR g.version IS DISTINCT FROM p_expected_version
 THEN RAISE EXCEPTION 'GAME_STATUS_OR_VERSION_CHANGED'; END IF;
 IF g.away_manager_id IS NULL OR g.home_manager_id=g.away_manager_id
 THEN RAISE EXCEPTION 'BOTH_MANAGERS_REQUIRED'; END IF;
 IF (SELECT count(*) FROM public.swl_game_lineups l
  WHERE l.game_id=g.id AND l.team_id IN (g.home_team_id,g.away_team_id)
  AND l.pitcher_id IS NOT NULL AND jsonb_typeof(l.defensive_positions)='object'
  AND jsonb_array_length(l.lineup) BETWEEN 9 AND 13)<>2
 THEN RAISE EXCEPTION 'BOTH_LINEUPS_REQUIRED'; END IF;
 UPDATE public.swl_live_games SET status='IN_PROGRESS',version=g.version+1 WHERE id=g.id;
END;
$function$;

-- swl_v56_save_lineup(uuid,uuid,uuid[],integer,uuid,boolean,uuid,jsonb) · MD5 319a951a2d65a5e0d789ee2ff53826a6 · ACL {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.swl_v56_save_lineup(p_game_id uuid, p_team_id uuid, p_player_ids uuid[], p_expected_revision integer, p_pitcher_id uuid, p_pitcher_bats boolean, p_designated_hitter_id uuid, p_defensive_positions jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 g public.swl_live_games%rowtype;
 actor uuid := auth.uid();
 n integer;
 position_count integer;
BEGIN
 SELECT * INTO g FROM public.swl_live_games WHERE id=p_game_id FOR UPDATE;
 IF NOT FOUND OR actor IS NULL OR p_team_id IS NULL OR
  NOT ((p_team_id=g.home_team_id AND actor=g.home_manager_id)
       OR (p_team_id=g.away_team_id AND actor=g.away_manager_id))
  OR public.swl_can_manage_roster(p_team_id) IS DISTINCT FROM true
 THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='NOT_TEAM_MANAGER'; END IF;
 IF g.status NOT IN ('SCHEDULED','IN_PROGRESS') THEN RAISE EXCEPTION 'GAME_CLOSED'; END IF;
 IF p_pitcher_id IS NULL OR p_pitcher_bats IS NULL OR p_defensive_positions IS NULL
    OR jsonb_typeof(p_defensive_positions) <> 'object'
 THEN RAISE EXCEPTION 'INVALID_PITCHER_OR_POSITIONS'; END IF;
 n:=coalesce(array_length(p_player_ids,1),0);
 IF n < 9 OR n > 13 THEN RAISE EXCEPTION 'LINEUP_SIZE_INVALID'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.rosters r WHERE r.team_id=p_team_id
       AND r.player_id=p_pitcher_id AND r.removed_at IS NULL)
    OR (p_defensive_positions->>p_pitcher_id::text) IS DISTINCT FROM 'P'
    OR (p_pitcher_id=ANY(p_player_ids)) IS DISTINCT FROM p_pitcher_bats
 THEN RAISE EXCEPTION 'PITCHER_INVALID'; END IF;
 IF (p_pitcher_bats AND p_designated_hitter_id IS NOT NULL)
 OR (NOT p_pitcher_bats AND (p_designated_hitter_id IS NULL
   OR (p_designated_hitter_id=ANY(p_player_ids)) IS DISTINCT FROM true
   OR p_defensive_positions ? p_designated_hitter_id::text))
 THEN RAISE EXCEPTION 'DESIGNATED_HITTER_INVALID'; END IF;
 SELECT count(*) INTO position_count FROM jsonb_each_text(p_defensive_positions);
 IF position_count < 9 OR position_count > 10 THEN RAISE EXCEPTION 'DEFENSIVE_POSITIONS_INVALID'; END IF;
 IF EXISTS (
  SELECT 1 FROM jsonb_each_text(p_defensive_positions) x
  WHERE x.key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     OR x.value NOT IN ('P','C','1B','2B','3B','SS','LF','CF','RF','SF')
 ) THEN RAISE EXCEPTION 'DEFENSIVE_POSITION_FORMAT_INVALID'; END IF;
 IF EXISTS (
  SELECT 1 FROM jsonb_each_text(p_defensive_positions) x
  WHERE NOT ((x.key::uuid=ANY(p_player_ids)) OR x.key::uuid=p_pitcher_id)
    OR NOT EXISTS (SELECT 1 FROM public.rosters r WHERE r.team_id=p_team_id
       AND r.player_id=x.key::uuid AND r.removed_at IS NULL)
    OR (x.value='P' AND x.key::uuid<>p_pitcher_id)
 ) OR EXISTS (
  SELECT 1 FROM jsonb_each_text(p_defensive_positions) x
  GROUP BY x.value HAVING count(*)>1
 ) THEN RAISE EXCEPTION 'DEFENSIVE_POSITIONS_NOT_UNIQUE_OR_ACTIVE'; END IF;
 PERFORM public.swl_v53_save_lineup_checked(p_game_id,p_team_id,p_player_ids,p_expected_revision);
 UPDATE public.swl_game_lineups
 SET pitcher_id=p_pitcher_id,pitcher_bats=p_pitcher_bats,
 designated_hitter_id=p_designated_hitter_id,defensive_positions=p_defensive_positions
 WHERE game_id=p_game_id AND team_id=p_team_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'LINEUP_NOT_SAVED'; END IF;
END;
$function$;

-- swl_v56_substitute_batter(uuid,uuid,integer,uuid,uuid,bigint,bigint) · MD5 764217d81ed8c516d43766faa2758b1d · ACL {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.swl_v56_substitute_batter(p_game_id uuid, p_team_id uuid, p_batting_order integer, p_outgoing_id uuid, p_incoming_id uuid, p_expected_revision bigint, p_expected_game_version bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  g public.swl_live_games%rowtype;
  l public.swl_game_lineups%rowtype;
  position text;
  next_version bigint;
  actor uuid := auth.uid();
begin
  select * into g from public.swl_live_games where id = p_game_id for update;
  if not found or actor is null or p_team_id is null or
      ((g.home_team_id = p_team_id and g.home_manager_id = actor)
       or (g.away_team_id = p_team_id and g.away_manager_id = actor)) is not true
      or public.swl_can_manage_roster(p_team_id) is not true then
    raise exception using errcode = '42501', message = 'Solo puede sustituir el mánager de ese equipo.';
  end if;
  if g.status::text is distinct from 'IN_PROGRESS' or g.version is distinct from p_expected_game_version then
    raise exception 'El partido o su versión cambió.';
  end if;
  select * into l from public.swl_game_lineups
    where game_id = p_game_id and team_id = p_team_id for update;
  if not found then raise exception 'Alineación no disponible.'; end if;
  if l.pitcher_id = p_incoming_id then
    raise exception 'El pitcher de solo defensa no puede entrar por esta vía al orden al bate.';
  end if;
  perform public.swl_v53_substitute_batter(p_game_id => p_game_id, p_team_id => p_team_id,
    p_batting_order => p_batting_order, p_outgoing_id => p_outgoing_id, p_incoming_id => p_incoming_id,
    p_expected_revision => p_expected_revision, p_expected_game_version => p_expected_game_version);
  select version into next_version from public.swl_live_games where id = p_game_id;
  if next_version is distinct from g.version + 1 then
    raise exception 'La sustitución no generó la versión esperada.';
  end if;
  perform public.swl_v56_validate_base_players(public.swl_v56_base_occupancy(g.bases_state),g.swl_base_players);
  if exists (select 1 from public.swl_live_games latest where latest.id = g.id
      and (latest.bases_state is distinct from g.bases_state or latest.inning is distinct from g.inning
           or latest.is_top is distinct from g.is_top)) then
    raise exception 'La sustitución no puede cambiar bases ni media entrada.';
  end if;
  position := l.defensive_positions ->> p_outgoing_id::text;
  update public.swl_game_lineups set
    defensive_positions = (l.defensive_positions - p_outgoing_id::text)
      || case when position is null then '{}'::jsonb else jsonb_build_object(p_incoming_id::text, position) end,
    pitcher_id = case when l.pitcher_id = p_outgoing_id then p_incoming_id else l.pitcher_id end,
    designated_hitter_id = case when l.designated_hitter_id = p_outgoing_id then p_incoming_id else l.designated_hitter_id end
  where game_id = p_game_id and team_id = p_team_id;
  if p_incoming_id = any(g.swl_base_players) then
    raise exception 'El sustituto ya figura en una base.';
  end if;
  if p_outgoing_id = any(g.swl_base_players) then
    update public.swl_live_games set
      swl_base_players = array_replace(g.swl_base_players,p_outgoing_id,p_incoming_id),
      swl_ghost_player = case when g.swl_ghost_player = p_outgoing_id
        then p_incoming_id else g.swl_ghost_player end
      where id = g.id;
  end if;
  if l.pitcher_id = p_outgoing_id then
    insert into public.swl_v56_pitcher_changes(game_id,team_id,version,old_pitcher_id,new_pitcher_id,innings_number,actor_id)
      values (p_game_id, p_team_id, next_version, p_outgoing_id, p_incoming_id, g.inning, actor);
  end if;
end;
$function$;
