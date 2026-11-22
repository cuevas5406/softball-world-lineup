# V5.7 — último out en jugadas con varios outs

**Hallazgo:** La propuesta `13_v57_batazos_y_defensa.sql` guardaba `last_out_player_id` únicamente si `made = 1`. Si el anotador registraba dos outs en una misma jugada, el evento quedaba sin identificación del último corredor retirado. Esto podía impedir que `GHOST_RUNNER` con `LAST_OUT` recuperara correctamente el jugador del historial.

**Corrección:** Guardar el último corredor retirado cuando `made >= 1`. La variable `last_out` se actualiza por cada out registrado, en el orden de procesamiento del servidor.

**Límite importante:** Cuando se registran varios outs en una misma jugada, el orden real de los outs puede diferir del orden de bases procesadas por el servidor. Para garantizar el último out real en esas jugadas, será necesario enviar una secuencia cronológica explícita desde Flutter. Hasta entonces, el último corredor procesado es una aproximación y no debe asumirse que representa necesariamente el último out cronológico.

No se instaló SQL ni se modificó producción.
