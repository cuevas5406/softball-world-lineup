# V5.7 — Diagnóstico Agenda y Retos (sin cambios en LAB)

## Comprobaciones reales
- La lista de tablas de LAB no incluye `public.swl_v56_challenges`.
- La lista de migraciones aplicadas no incluye una migración de Agenda/Retos.
- Flutter consulta `swl_v56_challenges` y llama `swl_v56_send_challenge` / `swl_v56_act_challenge`.
- Existe propuesta local `propuestas_lab/02_retos.sql` (NO aplicada).

## Correcciones Flutter de este bloque
- Se reintenta leer la agenda periódicamente aun si previamente se detectó que faltaba la tabla.
- Al cambiar de equipo se reinicia el estado de disponibilidad y se invalidan respuestas anteriores.
- No se muestra el texto «Tu equipo aún no tiene encuentros» cuando la consulta falló: no hay evidencia de agenda vacía.

## Pendientes antes de instalar SQL
- Revisar firmas y permisos reales de `swl_can_manage_roster` y `swl_v5_create_game` y su compatibilidad con `02_retos.sql`.
- Revisar si `swl_v5_create_game` devuelve un objeto con `id` y admite los argumentos de la propuesta.
- Revisar el comportamiento de retos externos, permisos y el enlace con partidos en vivo.
- Obtener autorización explícita antes de cualquier migración.

## Alcance de pruebas
Inspección estática y consulta de metadatos LAB (tablas/migraciones). No se ejecutó SQL, no se aplicó migración, no se compiló APK ni se probó en teléfonos.
