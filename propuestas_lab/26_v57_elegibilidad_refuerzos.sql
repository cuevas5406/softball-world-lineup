-- PROPUESTA LAB SIN EJECUTAR. Requiere alineaciones extendidas V5.6 y swl_base_players de las jugadas especiales.
-- Ensayar con partidos desechables. Si hay conflictos históricos, la migración
-- falla completa para que se revisen los datos sin corregirlos por inferencia.
begin;
lock table public.swl_live_games, public.swl_game_lineups, public.rosters
  in share row exclusive mode;

create unique index if not exists swl_v57_one_active_root
  on public.rosters(player_id) where removed_at is null and not is_refuerzo;

create table public.swl_v57_active_participant (
  player_id uuid primary key references public.players(id),
  game_id uuid not null references public.swl_live_games(id) on delete cascade,
  team_id uuid not null references public.teams(id)
);
create index swl_v57_active_participant_game on public.swl_v57_active_participant(game_id);
alter table public.swl_v57_active_participant enable row level security;
revoke all on public.swl_v57_active_participant from public, anon, authenticated;

create function public.swl_v57_lineup_player_ids(p_lineup jsonb, p_defense jsonb, p_pitcher uuid, p_dh uuid)
returns table(player_id uuid) language sql immutable set search_path = '' as $$
  select (slot->>'player_id')::uuid from jsonb_array_elements(coalesce(p_lineup,'[]'::jsonb)) slot
    where slot->>'player_id' is not null
  union select key::uuid from jsonb_object_keys(coalesce(p_defense,'{}'::jsonb)) as keys(key)
  union select p_pitcher where p_pitcher is not null
  union select p_dh where p_dh is not null;
$$;

create function public.swl_v57_check_lineup_players(l public.swl_game_lineups, p_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  athlete uuid;
begin
  for athlete in select player_id from public.swl_v57_lineup_player_ids(
    l.lineup, l.defensive_positions, l.pitcher_id, l.designated_hitter_id) order by player_id loop
    if not exists (select 1 from public.rosters r where r.player_id = athlete
        and r.team_id = l.team_id and r.removed_at is null) then
      raise exception 'PELOTERO_FUERA_DEL_ROSTER';
    end if;
    if exists (select 1 from public.swl_game_lineups other
        cross join lateral public.swl_v57_lineup_player_ids(
          other.lineup, other.defensive_positions, other.pitcher_id, other.designated_hitter_id) entry
        where other.game_id = l.game_id and other.team_id <> l.team_id and entry.player_id = athlete) then
      raise exception 'PELOTERO_EN_AMBOS_EQUIPOS';
    end if;
    if p_active then
      insert into public.swl_v57_active_participant as existing(player_id, game_id, team_id)
        values(athlete, l.game_id, l.team_id)
        on conflict(player_id) do update set game_id = excluded.game_id
        where existing.game_id = excluded.game_id and existing.team_id = excluded.team_id;
      if not found then raise exception 'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO'; end if;
    elsif exists (select 1 from public.swl_v57_active_participant a where a.player_id = athlete
        and (a.game_id <> l.game_id or a.team_id <> l.team_id)) then
      raise exception 'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO';
    end if;
  end loop;
end;
$$;

create function public.swl_v57_check_lineup_write()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  game public.swl_live_games%rowtype;
begin
  select * into strict game from public.swl_live_games where id = new.game_id for update;
  if tg_op = 'UPDATE' then
    if old.game_id is distinct from new.game_id or old.team_id is distinct from new.team_id then
      raise exception 'No se puede trasladar la alineación a otro equipo o juego.';
    end if;
  end if;
  if game.status::text in ('SCHEDULED','IN_PROGRESS') then
    if new.team_id is distinct from game.home_team_id and new.team_id is distinct from game.away_team_id then
      raise exception 'La alineación no corresponde a los equipos del partido.';
    end if;
    perform public.swl_v57_check_lineup_players(new, game.status::text = 'IN_PROGRESS');
  end if;
  return new;
end;
$$;

create function public.swl_v57_sync_game_participants()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  lineup_row public.swl_game_lineups%rowtype;
begin
  if new.status::text = 'IN_PROGRESS' then
    for lineup_row in select * from public.swl_game_lineups where game_id = new.id order by team_id loop
      perform public.swl_v57_check_lineup_players(lineup_row, true);
    end loop;
  elsif old.status::text = 'IN_PROGRESS' then
    delete from public.swl_v57_active_participant where game_id = new.id;
  end if;
  return new;
end;
$$;

create trigger swl_v57_check_lineup_write before insert or update on public.swl_game_lineups
  for each row execute function public.swl_v57_check_lineup_write();
create trigger swl_v57_sync_game_participants after update of status on public.swl_live_games
  for each row when (old.status is distinct from new.status)
  execute function public.swl_v57_sync_game_participants();

-- Los corredores que entran desde el roster sin pasar por un cambio de
-- alineación (por ejemplo, corredor fantasma) reservan la misma identidad.
create function public.swl_v57_reserve_new_base_players()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  athlete uuid;
  batting_team uuid;
begin
  batting_team := case when new.is_top then new.away_team_id else new.home_team_id end;
  for athlete in select distinct player from unnest(new.swl_base_players) as base(player)
    where player is not null
      and not coalesce(player = any(old.swl_base_players), false)
    order by player loop
    if not exists (select 1 from public.rosters r where r.player_id = athlete
        and r.team_id = batting_team and r.removed_at is null) then
      raise exception 'PELOTERO_FUERA_DEL_ROSTER';
    end if;
    if exists (select 1 from public.swl_game_lineups other
        cross join lateral public.swl_v57_lineup_player_ids(
          other.lineup, other.defensive_positions, other.pitcher_id, other.designated_hitter_id) entry
        where other.game_id = new.id and other.team_id <> batting_team and entry.player_id = athlete) then
      raise exception 'PELOTERO_EN_AMBOS_EQUIPOS';
    end if;
    insert into public.swl_v57_active_participant as existing(player_id, game_id, team_id)
      values(athlete, new.id, batting_team)
      on conflict(player_id) do update set game_id = excluded.game_id
      where existing.game_id = excluded.game_id and existing.team_id = excluded.team_id;
    if not found then raise exception 'PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO'; end if;
  end loop;
  return new;
end;
$$;
create trigger swl_v57_reserve_new_base_players after update of swl_base_players on public.swl_live_games
  for each row when (new.status::text = 'IN_PROGRESS' and old.swl_base_players is distinct from new.swl_base_players)
  execute function public.swl_v57_reserve_new_base_players();

-- Las reservas de quienes ya participaron se conservan hasta el cierre.
-- Para partidos existentes, verificar los relevos históricos antes de usar en LAB.
select public.swl_v57_check_lineup_players(l,true)
  from public.swl_game_lineups l join public.swl_live_games g on g.id = l.game_id
  where g.status::text = 'IN_PROGRESS' order by g.id,l.team_id;
revoke all on function
  public.swl_v57_lineup_player_ids(jsonb,jsonb,uuid,uuid),
  public.swl_v57_check_lineup_players(public.swl_game_lineups,boolean),
  public.swl_v57_check_lineup_write(), public.swl_v57_sync_game_participants(),
  public.swl_v57_reserve_new_base_players()
  from public, anon, authenticated;
commit;
