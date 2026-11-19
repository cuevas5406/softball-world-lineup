-- BORRADOR PARA REVISIÓN, NO APLICAR. La función existente aún no fue inspeccionada.
-- Aplicar solo como parte del mismo cambio que adapta TODOS los escritores del código.
begin;
lock table public.players in access exclusive mode;
create sequence public.swl_v56_universal_id_seq as bigint;
revoke all on sequence public.swl_v56_universal_id_seq from public, anon, authenticated;
select setval('public.swl_v56_universal_id_seq',
  coalesce(max(substring(universal_id from '^SWL-([0-9]+)$')::bigint), 0) + 1, false)
from public.players
where universal_id ~ '^SWL-[0-9]+$';

create function public.swl_v56_next_universal_id()
returns text language sql volatile security definer set search_path = '' as $$
  select 'SWL-' || lpad(n, greatest(4, length(n)), '0')
  from (select nextval('public.swl_v56_universal_id_seq')::text as n) allocated;
$$;
revoke all on function public.swl_v56_next_universal_id() from public, anon, authenticated;
-- Pendiente incorporar aquí la definición REAL revisada de swl_register_player,
-- su default o su trigger de código. Revisar también importaciones y escritores alternos.
-- ROLLBACK intencional: este borrador por sí solo no corrige el registro.
rollback;
