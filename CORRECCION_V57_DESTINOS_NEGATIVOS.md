# V5.7 — outs de corredores rechazados por validación previa

**Hallazgo crítico:** La validación JSON introducida en la propuesta `13_v57_batazos_y_defensa.sql` exigía el patrón `^-?[0-4]$`, que en principio permite negativos, pero no restringía específicamente la base del bateador. Se ha separado expresamente la validación de destinos (`-1` a `-4` para outs, `0` home, `1` a `3` bases, `4` sujeto a regla posterior) y de la base del bateador (`1` a `3`).

**Resultado:** Los destinos negativos de out se aceptan sintácticamente antes de pasar a la lógica de validación de jugada; `p_batter_base` no admite valores negativos ni cero. El resto de reglas de avance y out permanece intacto.

**Pruebas:** Se agregó comprobación Python de contrato. No se ejecutó Dart ni se aplicó SQL a LAB. Producción intacta.
