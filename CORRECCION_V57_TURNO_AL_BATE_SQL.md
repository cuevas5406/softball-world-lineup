# V5.7 — compatibilidad del turno al bate

**Error confirmado en el código:** Flutter genera alineaciones con `batting_order` y el lector admite `order` o `batting_order`, mientras la RPC `swl_v57_batted_ball` exigía exclusivamente `order`. Un batazo podía ser rechazado por «El bateador cambió» aunque el jugador fuera el correcto.

**Cambio:** la RPC acepta ambos nombres usando `coalesce(slot->>'order',slot->>'batting_order') = turn_index::text`, evitando también un cast innecesario. La validación de identidad `player_id` sigue siendo obligatoria.

**Pruebas:** 9 pruebas Python de contrato superadas; no se ejecutaron pruebas Dart, SQL ni APK. Funciones V5.7 sin instalar en LAB. Producción intacta.
