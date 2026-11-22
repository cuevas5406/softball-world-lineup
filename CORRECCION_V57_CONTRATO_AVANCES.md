# Contrato RUNNER_MOVE — V5.7

Se corrigió una discrepancia entre el cliente y la RPC propuesta: el cliente aceptaba `source == destination` como jugada válida sin cambios, pero el servidor la rechaza. Ahora la previsualización también la rechaza y la prueba refleja el contrato.

Comprobación independiente en Supabase LAB: `swl_v56_special_play` y `swl_v57_batted_ball` aún no existen. No se ha instalado ninguna función ni probado una jugada transaccional.

Pendiente: instalación controlada de RPCs en LAB, pruebas con usuario mánager y APK. Producción no modificada.
