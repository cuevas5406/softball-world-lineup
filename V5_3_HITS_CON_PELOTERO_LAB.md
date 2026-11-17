# V5.3 — Hits asociados a pelotero (LAB)
La RPC swl_v53_apply_hit_for_player comprueba que el pelotero pertenece a la alineación del equipo que batea.
Invoca la RPC de hit y anexa batter_id al evento en la misma transacción.
Flutter solicita seleccionar el bateador de la alineación guardada.
Pendiente: validar turno secuencial, calcular estadísticas, compilar y probar con dos usuarios autenticados.
