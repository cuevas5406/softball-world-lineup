# V5.3 — Sustituciones de bateadores (LAB)

Se instaló la RPC `swl_v53_substitute_batter` en LAB. Requiere sesión autenticada, mánager del equipo con permiso vigente, partido no cerrado, revisión de alineación y versión del partido vigentes, turno existente, pelotero saliente en ese turno y entrante en roster activo. No permite duplicados ni reingreso de peloteros previamente sustituidos. La transacción actualiza el mismo turno en `swl_game_lineups`, incrementa la revisión y versión, e inserta un evento `SUBSTITUTION` con los IDs de ambos peloteros, el orden y el autor. Las estadísticas previas siguen asociadas al `batter_id` de cada evento, no al puesto del orden al bate.

Flutter incluye un diálogo de sustitución para cada equipo, accesible solo al mánager correspondiente; el servidor vuelve a verificar todos los permisos. Después de guardar vuelve a consultar partido y alineaciones.

**Límites importantes:** No implementa cambios defensivos, sustitución de lanzadores, reingreso reglamentario ni reemplazos temporales. Tampoco se han probado sustituciones reales con una sesión de mánager autenticada ni compilado Flutter. Las reglas de reingreso varían por torneo y deben definirse antes de habilitarlas. No usar como acta oficial.

**Comprobado:** RPC instalada, acceso anónimo bloqueado, validación de autenticación sin sesión, cero eventos de sustitución existentes. Producción no modificada.
