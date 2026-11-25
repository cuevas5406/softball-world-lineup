-- Propuesta para LAB. Revisar y autorizar antes de aplicar.
begin;
create schema if not exists swl_private;
revoke all on schema swl_private from public, anon, authenticated;

create table swl_private.player_identity (
  account_id uuid primary key references auth.users(id) on delete cascade,
  player_id uuid not null unique references public.players(id),
  claimed_at timestamptz not null default now(),
  bio text check (length(bio) <= 300),
  photo_path text
);
create table swl_private.player_invitation (
  account_id uuid primary key references auth.users(id) on delete cascade,
  player_id uuid not null unique references public.players(id),
  token_hash bytea not null unique check (octet_length(token_hash) = 32),
  expires_at timestamptz not null
);
alter table swl_private.player_identity enable row level security;
alter table swl_private.player_invitation enable row level security;
-- El operador verifica la identidad por un canal independiente y genera un
-- token aleatorio de 32 bytes. Guarda solo SHA-256 y vincula la invitación al UID
-- verificado y al registro original. No se importa profiles.player_id sin auditoría.
create function public.swl_v57_claim_player(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  player uuid;
  account uuid := auth.uid();
begin
  if account is null or coalesce(p_token,'') !~ '^[a-f0-9]{64}$' then
    raise exception 'Invitación inválida o vencida.';
  end if;
  delete from swl_private.player_invitation
    where account_id = account and expires_at > now()
      and token_hash = pg_catalog.sha256(pg_catalog.convert_to(p_token,'UTF8'))
    returning player_id into player;
  if not found then raise exception 'Invitación inválida o vencida.'; end if;
  insert into swl_private.player_identity(account_id,player_id) values (account,player);
end;
$$;

create function swl_private.can_store_player_photo(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and split_part(p_name,'/',1) = auth.uid()::text
    and p_name ~ '^[0-9a-f-]+/[0-9]+[.]jpg$'
    and exists(select 1 from swl_private.player_identity where account_id = auth.uid());
$$;
grant usage on schema swl_private to authenticated;
revoke all on function swl_private.can_store_player_photo(text) from public;
grant execute on function swl_private.can_store_player_photo(text) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('swl-player-photos','swl-player-photos',false,2097152,array['image/jpeg']);
create policy swl_v57_insert_player_photo on storage.objects for insert to authenticated
  with check (bucket_id = 'swl-player-photos' and swl_private.can_store_player_photo(name));
create policy swl_v57_read_player_photo on storage.objects for select to authenticated
  using (bucket_id = 'swl-player-photos' and swl_private.can_store_player_photo(name));

create function public.swl_v57_update_my_player(p_bio text,p_photo_path text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or char_length(p_bio) > 300 then raise exception 'Perfil inválido.'; end if;
  if p_photo_path is not null and (not swl_private.can_store_player_photo(p_photo_path)
      or not exists(select 1 from storage.objects where bucket_id='swl-player-photos' and name=p_photo_path)) then
    raise exception 'Foto inválida.';
  end if;
  update swl_private.player_identity set bio=case when p_photo_path is null then nullif(btrim(p_bio),'') else bio end,
    photo_path=coalesce(p_photo_path,photo_path) where account_id=auth.uid();
  if not found then raise exception 'Primero vincula tu perfil.'; end if;
end;
$$;

create function swl_private.game_batting(p_game uuid,p_player uuid default null)
returns table(player_id uuid,team_id uuid,ab bigint,h bigint,doubles bigint,triples bigint,hr bigint,rbi bigint,bb bigint,k bigint,sf bigint,r bigint)
language sql stable set search_path = '' as $$
  with official_game as (
    select * from public.swl_live_games where id=p_game and status='OFFICIAL'
  ), active_events as (
    select e.* from public.swl_game_events e join official_game g on g.id=e.game_id
    where e.version <= g.version
      and e.batting_team_id in (g.home_team_id,g.away_team_id)
      and not exists (select 1 from public.swl_game_events correction
        where correction.game_id=e.game_id and correction.event_type='UNDO_OUT'
          and correction.version <= g.version
          and correction.event_data->>'reverts_version'=e.version::text)
  ), batting as (
    select p.id as player_id,e.batting_team_id as team_id,
      count(*) filter(where event_type in ('HIT','ERROR','DOUBLE_PLAY','OUT')
         or (event_type='STRIKE' and event_data->>'plate_appearance_completed'='true')) as ab,
      count(*) filter(where event_type='HIT') as h,
      count(*) filter(where event_type='HIT' and event_data->>'batter_base'='2') as doubles,
      count(*) filter(where event_type='HIT' and event_data->>'batter_base'='3') as triples,
      count(*) filter(where event_type='HIT' and event_data->>'batter_base'='4') as hr,
      case when count(*) filter (where credit.rbi is null and event_type in
          ('HIT','BALL','SACRIFICE_FLY')) = 0
        then coalesce(sum(credit.rbi),0)::bigint end as rbi,
      count(*) filter(where event_type='BALL' and event_data->>'plate_appearance_completed'='true') as bb,
      count(*) filter(where event_type='STRIKE' and event_data->>'plate_appearance_completed'='true') as k,
      count(*) filter(where event_type='SACRIFICE_FLY') as sf
    from active_events e
    join public.players p on p.id::text=e.event_data->>'batter_id'
    cross join lateral (
      select coalesce(
        case when jsonb_typeof(e.event_data->'rbi')='number'
          and e.event_data->>'rbi' ~ '^[0-4]$' then (e.event_data->>'rbi')::int end,
        case when jsonb_typeof(e.event_data->'rbis')='number'
          and e.event_data->>'rbis' ~ '^[0-4]$' then (e.event_data->>'rbis')::int end,
        case when e.event_data->>'runs'='0' then 0 end
      ) as rbi
    ) credit
    where (p_player is null or p.id=p_player)
      and (event_type in ('HIT','ERROR','DOUBLE_PLAY','OUT','SACRIFICE_FLY')
        or (event_type in ('STRIKE','BALL') and event_data->>'plate_appearance_completed'='true'))
    group by p.id,e.batting_team_id
  ), runs_by_player as (
    select p.id as player_id,e.batting_team_id as team_id,count(*) as runs
    from active_events e
    cross join lateral (
      select distinct value as player_id
      from jsonb_array_elements_text(case
        when jsonb_typeof(e.event_data->'scoring_player_ids')='array'
          then e.event_data->'scoring_player_ids'
        else '[]'::jsonb end)
    ) scorer
    join public.players p on p.id::text=scorer.player_id
    where e.event_type in ('HIT','ERROR','BALL','RUNNER_MOVE','SACRIFICE_FLY')
    group by p.id,e.batting_team_id
  ), team_totals as (
    select team_id,sum(runs) as attributed_runs from runs_by_player group by team_id
  )
  select coalesce(b.player_id,r.player_id),coalesce(b.team_id,r.team_id),
    coalesce(b.ab,0),coalesce(b.h,0),coalesce(b.doubles,0),coalesce(b.triples,0),
    coalesce(b.hr,0),case when b.player_id is null then 0 else b.rbi end,coalesce(b.bb,0),coalesce(b.k,0),coalesce(b.sf,0),
    case when coalesce(t.attributed_runs,0) =
      case when coalesce(b.team_id,r.team_id)=g.home_team_id then g.home_runs else g.away_runs end
      then coalesce(r.runs,0) end
  from batting b full join runs_by_player r using (player_id,team_id)
  cross join official_game g
  left join team_totals t on t.team_id=coalesce(b.team_id,r.team_id)
  where p_player is null or coalesce(b.player_id,r.player_id)=p_player;
$$;
revoke all on function swl_private.game_batting(uuid,uuid) from public, authenticated, anon;

-- El equipo que defendía se obtiene de la versión exacta de la jugada.
-- Si falta el evento o hay equipos al bate contradictorios, queda sin asignar.
create function swl_private.game_pitching(p_game uuid,p_player uuid default null)
returns table(player_id uuid,team_id uuid,outs bigint,h bigint,bb bigint,k bigint)
language sql stable set search_path = '' as $$
  select stats.pitcher_id,defense.team_id,
    sum(stats.outs),sum(stats.hits),sum(stats.walks),sum(stats.strikes_out)
  from public.swl_live_games g
  join public.swl_v56_pitching_events stats on stats.game_id=g.id
  cross join lateral (
    select case
      when bool_and(e.batting_team_id=g.home_team_id) then g.away_team_id
      when bool_and(e.batting_team_id=g.away_team_id) then g.home_team_id
    end as team_id
    from public.swl_game_events e
    where e.game_id=g.id and e.version=stats.version
      and e.batting_team_id in (g.home_team_id,g.away_team_id)
  ) defense
  where g.id=p_game and g.status='OFFICIAL' and stats.version<=g.version
    and (p_player is null or stats.pitcher_id=p_player)
  group by stats.pitcher_id,defense.team_id;
$$;
revoke all on function swl_private.game_pitching(uuid,uuid) from public, authenticated, anon;

create function public.swl_v57_my_player() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'name',concat_ws(' ',p.first_name,p.last_name),'code',p.universal_id,
    'number',p.jersey_number,'position',p.primary_position,
    'secondary_position',to_jsonb(p)->>'secondary_position','bio',i.bio,'photo_path',i.photo_path,
    'teams',coalesce((select jsonb_agg(jsonb_build_object('name',t.name,'refuerzo',r.is_refuerzo)
      order by r.is_refuerzo,t.name) from public.rosters r join public.teams t on t.id=r.team_id
      where r.player_id=p.id and r.removed_at is null),'[]'::jsonb),
    'games',coalesce((select jsonb_agg(to_jsonb(rows) order by rows.date desc,rows.code) from (
      select g.created_at as date,g.game_pin as code,t.id as team_id,t.name as team_name,b.ab,b.h,b.doubles,b.triples,b.hr,b.bb,b.k,b.sf,b.r,b.rbi
      from public.swl_live_games g
      join lateral swl_private.game_batting(g.id,p.id) b on true
      join public.teams t on t.id=b.team_id
      where g.status='OFFICIAL'
    ) rows),'[]'::jsonb),
    'pitching',coalesce((select jsonb_agg(to_jsonb(rows) order by rows.date desc, rows.code) from (
      select g.created_at as date,g.game_pin as code,t.id as team_id,t.name as team_name,
        stats.outs,stats.h,stats.bb,stats.k
      from public.swl_live_games g
      join lateral swl_private.game_pitching(g.id,p.id) stats on true
      left join public.teams t on t.id=stats.team_id
      where g.status='OFFICIAL'
    ) rows),'[]'::jsonb))
  from swl_private.player_identity i join public.players p on p.id=i.player_id
  where i.account_id=auth.uid();
$$;

-- La respuesta enumera campos públicos. Los UUID de mánagers, teléfonos,
-- invitaciones, fotos privadas y registros de eventos no salen de esta RPC.
create function public.swl_v57_spectator_game(p_game_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id',g.id,'code',g.game_pin,'status',g.status,'date',g.created_at,'version',g.version,
    'inning',g.inning,'finish',g.swl_finish_reason,
    'home',jsonb_build_object('id',home.id,'name',home.name,'logo_path',home.logo_path,
      'logo_url',home.logo_url,'runs',g.home_runs,'hits',g.home_hits,'errors',g.home_errors,'innings',g.home_innings),
    'away',jsonb_build_object('id',away.id,'name',away.name,'logo_path',away.logo_path,
      'logo_url',away.logo_url,'runs',g.away_runs,'hits',g.away_hits,'errors',g.away_errors,'innings',g.away_innings),
    'lineups',coalesce((select jsonb_agg(jsonb_build_object('team_id',l.team_id,'order',coalesce(slots.slot->>'order',slots.slot->>'batting_order',slots.ord::text),
      'id',p.id,'name',concat_ws(' ', p.first_name,p.last_name),'number',p.jersey_number,
      'position',l.defensive_positions->>p.id::text) order by l.team_id,slots.ord)
      from public.swl_game_lineups l
      cross join lateral jsonb_array_elements(l.lineup) with ordinality as slots(slot,ord)
      join public.players p on p.id::text=slots.slot->>'player_id' where l.game_id=g.id),'[]'::jsonb),
    'batting',case when g.status='OFFICIAL' then coalesce((
      select jsonb_agg(to_jsonb(b)||jsonb_build_object('name',concat_ws(' ',p.first_name,p.last_name))
        order by b.team_id,p.last_name,p.first_name)
      from swl_private.game_batting(g.id) b join public.players p on p.id=b.player_id),'[]'::jsonb) end,
    'pitching',case when g.status='OFFICIAL' then coalesce((
      select jsonb_agg(to_jsonb(summary) order by summary.team_name nulls last,summary.name,summary.id) from (
        select p.id,concat_ws(' ',p.first_name,p.last_name) as name,
          stats.team_id,t.name as team_name,stats.outs,stats.h,stats.bb,stats.k
        from swl_private.game_pitching(g.id) stats
        join public.players p on p.id=stats.player_id
        left join public.teams t on t.id=stats.team_id
      ) summary),'[]'::jsonb) end
  )
  from public.swl_live_games g join public.teams home on home.id=g.home_team_id
  join public.teams away on away.id=g.away_team_id
  where auth.uid() is not null and g.id=p_game_id and g.status in ('IN_PROGRESS','OFFICIAL');
$$;
revoke all on function public.swl_v57_claim_player(text),public.swl_v57_update_my_player(text,text),
  public.swl_v57_my_player(),public.swl_v57_spectator_game(uuid) from public, anon, authenticated;
grant execute on function public.swl_v57_claim_player(text),public.swl_v57_update_my_player(text,text),
  public.swl_v57_my_player(),public.swl_v57_spectator_game(uuid) to authenticated;
commit;
