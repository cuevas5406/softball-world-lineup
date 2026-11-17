# V5.3 — Validación de innings en Supabase LAB

Se instaló en LAB (proyecto wgeziptdoabyicufnrfk) la función interna `public.swl_v53_inning_delta(jsonb,jsonb,integer,boolean,integer,integer,integer,integer)`.

## Prueba efectuada

`select public.swl_v53_inning_delta('[0,2]'::jsonb,'[1,0]'::jsonb,2,false,2,1,4,1);`

Resultado verificado: `{"home_innings":[0,4],"away_innings":[1,0],"runs_added":2}`.

Permisos verificados: `anon_execute=false`, `authenticated_execute=false`. La función no modifica partidas ni es un RPC público. **Aún NO está conectada a `swl_v53_record_play`**; los contadores básicos existentes no actualizan los innings. No habilitar marcador oficial basándose en esta prueba aislada.

## Pendientes

Conectar el cálculo al registro transaccional de jugadas completas, persistir `home_innings` y `away_innings` junto con bases/outs/estadísticas y evento, y probar con sesiones autenticadas de ambos mánagers. No se ha compilado Flutter ni probado APK.
