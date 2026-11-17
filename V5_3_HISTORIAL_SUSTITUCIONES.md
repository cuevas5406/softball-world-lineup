# V5.3 — Historial de sustituciones y nombres históricos

- El historial muestra eventos `SUBSTITUTION` con orden al bate, jugador saliente y entrante.
- La resolución de nombres incluye IDs de eventos y estadísticas, no solo la alineación actual.
- Los nombres ya cargados no se eliminan al actualizar la alineación.
- Las consultas comprueban el partido y generación antes de aplicar resultados atrasados.
- Las estadísticas se mantienen agrupadas por `batter_id` y no se trasladan al reemplazo.
- No se modificó el backend en esta entrega. La lista de eventos sigue limitada a los últimos 20.
- No se compiló Flutter ni se realizaron pruebas autenticadas de sustituciones en dos dispositivos.
