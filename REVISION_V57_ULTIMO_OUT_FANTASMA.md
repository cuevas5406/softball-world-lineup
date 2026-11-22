# Corrección del último out para corredor fantasma

- En RUNNER_OUT y DOUBLE_PLAY se prioriza el corredor retirado (`last_out_player_id` / `runner_id`) y no el bateador.
- Los datos JSON se validan antes de convertirlos a enteros.
- El estado de bases se valida como objeto antes de invocar `jsonb_object_keys`.
- La migración permanece propuesta, sin ejecutar. No se realizaron pruebas Flutter ni APK.
