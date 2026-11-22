# V5.7 — historial del último out con campos vacíos

En `swl_v56_special_play`, la selección `LAST_OUT` ahora trata las cadenas vacías como datos ausentes antes de aplicar `coalesce`. Si `last_out_player_id` es `""` pero existe un `runner_id` o `batter_id` válido, se utiliza la identidad correspondiente. Se conserva la validación estricta del UUID y la prohibición de cambiar el marcador cuando la identidad es inválida.

**Verificación:** comprobación estática de reemplazo y de integridad ZIP. No se ejecutaron pruebas Flutter ni migraciones en LAB o producción.
