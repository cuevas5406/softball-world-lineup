-- PROPUESTA PARA LAB. NO APLICADA. Revisar firmas y publicación tras autorización.
begin;
create table public.swl_v56_challenges (
  id uuid primary key default gen_random_uuid(),
  home_team_id uuid not null references public.teams(id),
  away_team_id uuid references public.teams(id),
  external_team_name text,
  scheduled_at timestamptz not null,
  stadium text not null default '',
  status text not null check (status in ('SENT','ACCEPTED','REJECTED','CANCELLED','EXTERNAL')),
  game_id uuid unique references public.swl_live_games(id),
  check (home_team_id is distinct from away_team_id),
  check ((away_team_id is null) <> (external_team_name is null))
);

create unique index swl_v56_one_active_challenge
on public.swl_v56_challenges (
  least(home_team_id, away_team_id), greatest(home_team_id, away_team_id), scheduled_at
) where away_team_id is not null and status in ('SENT', 'ACCEPTED');

create unique index swl_v56_one_active_external
on public.swl_v56_challenges(home_team_id, lower(external_team_name), scheduled_at)
where status = 'EXTERNAL';

alter table public.swl_v56_challenges enable row level security;
revoke all on public.swl_v56_challenges from public, anon, authenticated;
grant select on public.swl_v56_challenges to authenticated;
create policy swl_v56_challenge_read on public.swl_v56_challenges for select to authenticated
  using (public.swl_can_manage_roster(home_team_id) is true
      or (away_team_id is not null and public.swl_can_manage_roster(away_team_id) is true));

create function public.swl_v56_send_challenge(
  p_home_team_id uuid, p_away_team_id uuid, p_external_team_name text,
  p_scheduled_at timestamptz, p_stadium text
) returns public.swl_v56_challenges
language plpgsql security definer set search_path = '' as $$
declare r public.swl_v56_challenges%rowtype;
begin
  if auth.uid() is null or public.swl_can_manage_roster(p_home_team_id) is not true then
    raise exception using errcode = '42501', message = 'Selecciona un equipo autorizado.';
  end if;
  if p_scheduled_at is null or p_scheduled_at <= now() or length(coalesce(p_stadium,'')) > 150
      or (p_away_team_id is null and (nullif(btrim(p_external_team_name), '') is null
          or length(p_external_team_name) > 100))
      or (p_away_team_id is not null and (p_home_team_id = p_away_team_id
          or p_external_team_name is not null)) then
    raise exception 'Verifica el rival, el estadio y la hora del encuentro.';
  end if;
  insert into public.swl_v56_challenges(
    home_team_id, away_team_id, external_team_name, scheduled_at, stadium, status
  ) values (
    p_home_team_id, p_away_team_id, btrim(p_external_team_name), p_scheduled_at,
    coalesce(btrim(p_stadium), ''), case when p_away_team_id is null then 'EXTERNAL' else 'SENT' end
  ) returning * into r;
  return r;
exception when unique_violation then
  raise exception 'Ya existe un encuentro activo entre esos equipos en ese horario.';
end;
$$;

create function public.swl_v56_act_challenge(p_id uuid, p_action text)
returns public.swl_v56_challenges
language plpgsql security definer set search_path = '' as $$
declare
  r public.swl_v56_challenges%rowtype;
  game jsonb;
  next_status text;
begin
  select * into r from public.swl_v56_challenges where id = p_id for update;
  if not found or auth.uid() is null then
    raise exception using errcode = '42501', message = 'Encuentro no disponible.';
  end if;
  if p_action in ('ACCEPT','REJECT') and r.status = 'SENT'
      and r.away_team_id is not null and public.swl_can_manage_roster(r.away_team_id) is true then
    next_status := case when p_action = 'ACCEPT' then 'ACCEPTED' else 'REJECTED' end;
  elsif p_action = 'CANCEL' and r.game_id is null and r.status in ('SENT','ACCEPTED','EXTERNAL')
      and public.swl_can_manage_roster(r.home_team_id) is true then
    next_status := 'CANCELLED';
  elsif p_action = 'PREPARE' and r.status = 'ACCEPTED'
      and public.swl_can_manage_roster(r.home_team_id) is true then
    if r.game_id is not null then return r; end if;
    select to_jsonb(public.swl_v5_create_game(r.home_team_id, r.away_team_id)) into game;
    if game ->> 'id' is null then raise exception 'La creación no devolvió un partido válido.'; end if;
    update public.swl_v56_challenges set game_id = (game ->> 'id')::uuid
      where id = r.id returning * into r;
    return r;
  else
    raise exception using errcode = '42501', message = 'La acción no está permitida para este equipo o estado.';
  end if;
  update public.swl_v56_challenges set status = next_status
    where id = r.id returning * into r;
  return r;
end;
$$;
revoke all on function public.swl_v56_send_challenge(uuid,uuid,text,timestamptz,text),
  public.swl_v56_act_challenge(uuid,text) from public, anon;
grant execute on function public.swl_v56_send_challenge(uuid,uuid,text,timestamptz,text),
  public.swl_v56_act_challenge(uuid,text) to authenticated;
commit;
