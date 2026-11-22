# V5.7 — Bloque 08: auditoría de Agenda y Retos (sin cambios en LAB)

## Verificado mediante consultas de solo lectura a LAB (2026-11-22)

- Existen `public.swl_can_manage_roster(p_team_id uuid)` y `public.swl_v5_create_game(p_home_team_id uuid, p_away_team_id uuid)`.
- Ambas funciones existentes están definidas como `SECURITY DEFINER`.
- No existen aún `swl_v56_send_challenge` ni `swl_v56_act_challenge`.
- La lista de tablas de `public` no contiene `swl_v56_challenges`.

## Contrato de Flutter y propuesta

- `lib/main.dart` consulta `swl_v56_challenges`, llama a `swl_v56_send_challenge` para enviar y a `swl_v56_act_challenge` para aceptar/rechazar/cancelar/preparar.
- `propuestas_lab/02_retos.sql` contiene la tabla, las políticas de lectura y las dos funciones, pero NO se ejecutó.
- La propuesta incluye `begin`/`commit`, `create table` y `create function` sin cláusulas de existencia; **no ejecutarla sin verificar dependencias y estado de instalación**.
- Antes de autorizar su instalación, revisar en una transacción de pruebas: permisos de lectura por equipo, validación de mánager local/visitante, ausencia de duplicados, `PREPARE` y la creación del partido, estado de retos externos y restricciones de borrado/cancelación.
- La función `swl_v5_create_game` es `SECURITY DEFINER`: revisar su definición y permisos reales antes de permitir que otra función `SECURITY DEFINER` la invoque.

## Cambio Flutter en este bloque

- `_sendChallenge` solo muestra errores al equipo que inició la operación. Evita mensajes cruzados cuando el usuario cambia de equipo durante la petición.
- Añadidas dos pruebas de contrato en `test/test_v57_agenda_async_feedback.py`.

## Pendientes

1. Revisión detallada de seguridad y permisos de las funciones existentes.
2. Aprobación específica del usuario antes de instalar SQL en LAB.
3. Pruebas Dart y compilación Flutter (SDK no disponible en este entorno).
4. Pruebas reales entre dos teléfonos y cierre de la pantalla Mi Equipo.

**No se modificó Supabase LAB ni producción.**
