# V5.7 — orden declarado en jugadas especiales y sustituciones

La función SQL `swl_v56_special_play` (propuesta 18) usaba la posición física del arreglo JSON para validar el bateador de `SACRIFICE_FLY` y `DOUBLE_PLAY`. Flutter, en cambio, utiliza el orden declarado en `order` o `batting_order`. Si los registros JSON estaban desordenados, la función rechazaba al bateador correcto.

También `RUNNER_REPLACE` derivaba la posición a sustituir de la posición física del arreglo, con riesgo de sustituir el turno equivocado.

Ahora ambos flujos utilizan el campo declarado `order` o `batting_order`, conforme al contrato de Flutter.

**Importante:** el cambio está preparado en el archivo SQL, **no instalado en LAB**. Pruebas de contrato Python no sustituyen pruebas SQL/Dart.
