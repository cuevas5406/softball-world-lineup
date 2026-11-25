-- PROPUESTA LAB SIN EJECUTAR. Verificar que el tipo y los checks de status
-- acepten CANCELLED. Si no, adaptar al esquema LAB antes de aplicar.
begin;
alter table public.swl_live_games add column swl_cancel_requested_by uuid;
create table public.swl_v57_cancel_decisions (
  game_id uuid not null references public.swl_live_games(id),
  version bigint not null,
  actor_id uuid not null,
  action text not null check (action in ('CANCEL_REQUEST','CANCEL_ACCEPT','CANCEL_REJECT')),
  recorded_at timestamptz not null default now(),
  primary key(game_id,version)
);
alter table public.swl_v57_cancel_decisions enable row level security;
revoke all on public.swl_v57_cancel_decisions from public, anon, authenticated;

create function public.swl_v57_cancel_game(p_game_id uuid, p_expected_version bigint, p_action text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  g public.swl_live_games%rowtype;
  actor uuid := auth.uid();
begin
  select * into strict g from public.swl_live_games where id = p_game_id for update;
  if actor is null or g.home_manager_id is null or g.away_manager_id is null
      or g.home_manager_id = g.away_manager_id
      or (actor is distinct from g.home_manager_id and actor is distinct from g.away_manager_id)
      or public.swl_can_manage_roster(case when actor = g.home_manager_id then g.home_team_id else g.away_team_id end) is not true then
    raise exception using errcode = '42501', message = 'Acción reservada a los dos mánagers autorizados.';
  end if;
  if g.status::text not in ('SCHEDULED','IN_PROGRESS') or g.version is distinct from p_expected_version then
    raise exception 'El partido cambió o ya no admite cancelación.';
  end if;
  if p_action = 'CANCEL_REQUEST' and g.swl_cancel_requested_by is null then
    update public.swl_live_games set swl_cancel_requested_by = actor, version = g.version + 1 where id = g.id;
  elsif p_action in ('CANCEL_ACCEPT','CANCEL_REJECT')
      and g.swl_cancel_requested_by = (case when actor = g.home_manager_id then g.away_manager_id else g.home_manager_id end) then
    if p_action = 'CANCEL_ACCEPT' then
      update public.swl_live_games set status = 'CANCELLED',
        swl_cancel_requested_by = null, version = g.version + 1 where id = g.id;
    else
      update public.swl_live_games set swl_cancel_requested_by = null, version = g.version + 1 where id = g.id;
    end if;
  else
    raise exception 'No hay una solicitud válida para esta acción.';
  end if;
  insert into public.swl_v57_cancel_decisions(game_id,version,actor_id,action)
    values(g.id,g.version + 1,actor,p_action);
end;
$$;
revoke all on function public.swl_v57_cancel_game(uuid,bigint,text) from public, anon;
grant execute on function public.swl_v57_cancel_game(uuid,bigint,text) to authenticated;
commit;
