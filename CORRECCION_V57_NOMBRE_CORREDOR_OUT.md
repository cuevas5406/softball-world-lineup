# V5.7 — identificación de corredores retirados en el historial

El historial ahora consulta los IDs `batter_id`, `runner_id` y `last_out_player_id` presentes en los eventos, y para `RUNNER_OUT` o `DOUBLE_PLAY` prioriza al corredor retirado al mostrar el nombre. Antes podía mostrarse el bateador o «Partido» aunque el servidor tuviera identificado al corredor.

No se modifica la contabilización de outs ni carreras. La corrección se validó mediante pruebas estáticas de contrato; falta ejecutarla en Flutter y comprobar eventos reales en LAB. No se ejecutó SQL.
