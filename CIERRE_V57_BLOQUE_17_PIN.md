# Bloque 17 — conexión por PIN

Se reforzó `_joinFromPin` en `lib/swl_live_lobby.dart`:
- valida PIN SWL de seis dígitos;
- comprueba autorización del equipo visitante antes de intentar reclamar una plaza visible;
- mantiene la ruta RPC para partidos ocultos por RLS (la autorización definitiva corresponde al servidor);
- impide que el modo espectador invoque la RPC de unión;
- rechaza respuestas que no sean un mapa o que contengan un PIN diferente.

**Limitaciones:** no se compiló Flutter/Dart ni se probó en dos dispositivos. El servidor debe aplicar sus propias políticas de permisos. No se modificó Supabase.
