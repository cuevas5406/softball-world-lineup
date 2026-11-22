# V5.7 — último out cronológico, interfaz y servidor

**Cambio integrado:** Cuando un batazo retira a dos o más corredores, el mánager debe indicar en la pantalla de anotación cuál corredor fue el último out. El botón Confirmar permanece inhabilitado hasta elegirlo. Flutter envía `p_last_out_source` (1, 2 o 3); la función SQL valida que el origen seleccionado corresponde a un corredor realmente retirado y lo registra en `last_out_player_id` para que el corredor fantasma `LAST_OUT` use la identidad correcta.

No cambia el flujo de un solo out. Si un cliente antiguo intenta registrar varios outs sin indicar el último, el servidor rechazará la jugada (una vez instalada la propuesta), evitando una identidad incorrecta.

**Verificación:** pruebas Python de contrato; no ejecuta Flutter/Dart ni PostgreSQL. La función SQL sigue sin instalarse en LAB. Producción intacta.

**Otro pendiente observado:** el selector Flutter ofrece jonrón (base 4) pero la RPC de batazos de la propuesta 13 solo acepta bases 1–3. Requiere una corrección específica antes de instalar.
