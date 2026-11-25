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
returns table(player_id uuid,team_id uuid,ab bigint,h bigint,doubles bigint,triples bigint,hr bigint,bb bigint,k bigint,sf bigint)
language sql stable set search_path = '' as $$
  select p.id,e.batting_team_id,
    count(*) filter(where event_type in ('HIT','ERROR','DOUBLE_PLAY','OUT')
       or (event_type='STRIKE' and event_data->>'plate_appearance_completed'='true')),
    count(*) filter(where event_type='HIT'),
    count(*) filter(where event_type='HIT' and event_data->>'batter_base'='2'),
    count(*) filter(where event_type='HIT' and event_data->>'batter_base'='3'),
    count(*) filter(where event_type='HIT' and event_data->>'batter_base'='4'),
    count(*) filter(where event_type='BALL' and event_data->>'plate_appearance_completed'='true'),
    count(*) filter(where event_type='STRIKE' and event_data->>'plate_appearance_completed'='true'),
    count(*) filter(where event_type='SACRIFICE_FLY')
  from public.swl_game_events e
  join public.swl_live_games g on g.id=e.game_id
  join public.players p on p.id::text=e.event_data->>'batter_id'
  where e.game_id=p_game and e.version <= g.version
    and g.status='OFFICIAL' and (p_player is null or p.id=p_player)
    and not exists (select 1 from public.swl_game_events correction
      where correction.game_id=e.game_id and correction.event_type='UNDO_OUT'
        and correction.event_data->>'reverts_version'=e.version::text)
    and (event_type in ('HIT','ERROR','DOUBLE_PLAY','OUT','SACRIFICE_FLY')
      or (event_type in ('STRIKE','BALL') and event_data->>'plate_appearance_completed'='true'))
  group by p.id,e.batting_team_id;
$$;
revoke all on function swl_private.game_batting(uuid,uuid) from public, authenticated, anon;

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
      select g.created_at as date,g.game_pin as code,t.id as team_id,t.name as team_name,b.ab,b.h,b.hr,b.bb,b.k,b.sf
      from public.swl_live_games g
      join lateral swl_private.game_batting(g.id,p.id) b on true
      join public.teams t on t.id=b.team_id
      where g.status='OFFICIAL'
    ) rows),'[]'::jsonb),
    'pitching',coalesce((select jsonb_agg(to_jsonb(rows) order by rows.date desc, rows.code) from (
      select g.created_at as date,g.game_pin as code,t.id as team_id,t.name as team_name,
        sum(stats.outs) as outs,sum(stats.hits) as h,sum(stats.walks) as bb,sum(stats.strikes_out) as k
      from public.swl_v56_pitching_events stats join public.swl_live_games g on g.id=stats.game_id
      left join lateral (
        select batting_team_id from public.swl_game_events e
        where e.game_id=g.id and e.version=stats.version
          and e.batting_team_id in (g.home_team_id,g.away_team_id)
        order by e.id desc limit 1
      ) event on true
      left join public.teams t on t.id=case when event.batting_team_id=g.home_team_id then g.away_team_id
        when event.batting_team_id=g.away_team_id then g.home_team_id end
      where stats.pitcher_id=p.id and g.status='OFFICIAL'
      group by g.id,g.created_at,g.game_pin,t.id,t.name
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
      select jsonb_agg(to_jsonb(summary) order by summary.name) from (
        select p.id,concat_ws(' ',p.first_name,p.last_name) as name,
          sum(e.outs) as outs,sum(e.hits) as h,sum(e.walks) as bb,sum(e.strikes_out) as k
        from public.swl_v56_pitching_events e join public.players p on p.id=e.pitcher_id
        where e.game_id=g.id and e.version<=g.version group by p.id,p.first_name,p.last_name
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
