# V5.7 — Bloque 07: aislamiento de Agenda por equipo y revisión LAB

## Cambios Flutter
- Al cambiar de equipo autorizado, se limpian los borradores de Agenda en memoria para que no se filtren al nuevo equipo.
- Una respuesta tardía de «enviar reto» ya no elimina borradores ni refresca la agenda del equipo nuevo.
- Las respuestas tardías a acciones de retos no refrescan ni muestran errores correspondientes a un equipo anterior.

## LAB — lectura únicamente (22 noviembre 2026)
- La tabla `public.swl_v56_challenges` no figura en la lista de tablas públicas.
- La función `public.swl_can_manage_roster(p_team_id uuid)` existe y devuelve boolean.
- La función `public.swl_v5_create_game(p_home_team_id uuid, p_away_team_id uuid)` existe y devuelve `swl_live_games`.
- No hay migración instalada de Agenda/Retos entre las migraciones listadas.
- La propuesta `propuestas_lab/02_retos.sql` usa esas firmas; **esto no demuestra** que sea segura para instalar sin pruebas de políticas, concurrencia y ciclo de vida de partidos.

## Pendientes
- Revisar detalladamente la migración de Retos y las políticas antes de solicitar autorización para ejecutarla.
- Revisar sustituciones en servidor y pantalla Mi Equipo (pendiente acordado).
- Compilar Flutter y ejecutar pruebas Dart, RPC y pruebas reales con dos teléfonos.
- No se aplicaron migraciones ni se modificaron datos en Supabase LAB o producción.
