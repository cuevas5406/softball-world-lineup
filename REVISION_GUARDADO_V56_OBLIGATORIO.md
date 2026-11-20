# Revisión V5.6: guardado completo obligatorio

## Hallazgo
El editor elegía la RPC antigua `swl_v53_save_lineup_checked` cuando la defensa estaba vacía. Eso permitía confirmar el orden al bate sin pitcher/defensa; luego `swl_v56_start_game` rechaza el inicio con `BOTH_LINEUPS_REQUIRED`.

## Cambio
El editor de partidos V5.6 ahora llama siempre a `swl_v56_save_lineup` y valida localmente el pitcher y entre 9 y 10 posiciones defensivas. La función antigua no se elimina de LAB ni de otros consumidores.

## Pendiente
Ejecutar `flutter test`, compilar APK y comprobar en dos teléfonos. No se ha modificado Supabase ni ejecutado SQL de escritura.
