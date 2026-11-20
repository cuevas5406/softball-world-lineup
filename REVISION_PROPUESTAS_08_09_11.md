# Revisión técnica de SWL V5.6

Base de trabajo: `softball-world-lineup-v5-6-conteo-pitcheos(1).zip`. Su SHA-256 coincide con el ZIP sin el sufijo `(1)`.

| Propuesta | Corrección |
| --- | --- |
| 08 · Cierre | Valida que la anotación haya generado exactamente una versión y que la media entrada cambie según la secuencia alta → baja → alta siguiente. Conserva la entrada y mitad terminales y el estado posterior a la jugada. Se probaron seis entradas, empate y extras, ventaja decisiva del local, cierre de la baja para victoria visitante y los límites inclusivos de 15 y 10. Si el visitante alcanza el margen en alta, el local conserva su oportunidad de batear. |
| 09 · Corredores | Comprueba ocupación e identidades por separado, incluso en bases ocupadas legadas cuyo corredor se desconoce. Una identidad conocida exige una base ocupada y puede aparecer una sola vez. Rechaza colisiones, retrocesos y rebasamientos en hits. Mantiene la ocupación y los avances calculados por la RPC legada y revierte la jugada si el resultado legado discrepa del mapa esperado. Los boletos trasladan solo a los corredores forzados. Las sustituciones conservan la ocupación. El cambio de media entrada limpia las identidades. |
| 11 · Lanzamientos | `PITCHES = B + S + en juego`. BALL suma a B. STRIKE y FOUL suman a S. HIT, OUT de bateador, SACRIFICE_FLY y DOUBLE_PLAY cuentan una sola vez como bolas en juego. Los movimientos y outs independientes de corredores no suman lanzamientos. El registro conserva la versión única de la jugada y el pitcher asignado antes de anotarla. La app identifica los datos antiguos y los totales parciales. |

La clasificación supone que OUT de bateador representa una bola en juego en esta pizarra. Si LAB contempla outs de bateador sin lanzamiento, su contrato debe distinguirlos antes de atribuirles PITCHES. El foul conserva el comportamiento propuesto de sumar un lanzamiento aun con dos strikes, sin convertirlo en ponche.

## Compatibilidad revisada

- **06 → 08 → 09 → 11.** El registro de bola, strike y out de 08 y 09 mantiene la llamada nombrada a `swl_v53_record_plate_action`. El hit mantiene `swl_v53_apply_hit_for_player`. La 09 también usa `swl_v53_substitute_batter` y presupone 07. Las llamadas registran la jugada una vez, sincronizan las identidades, acreditan el pitcheo y evalúan el cierre. La 11 conserva la firma de `swl_v56_accumulate_pitching` que usan ambos archivos.
- **Contrato por confirmar en LAB.** Una anotación incrementa la versión exactamente en uno. HIT debe devolver la ocupación correspondiente a sus destinos explícitos y el boleto, el movimiento forzado. Deben comprobarse los estados, tipos, permisos efectivos, restricciones de `event_type` (en particular FOUL), estructura de bases y firmas realmente instaladas. Esta entrega revisó el código del proyecto sin consultar el catálogo de LAB. Si se aplicó una versión previa de 11, se requiere revisar sus columnas, su restricción y los datos históricos antes de preparar una migración incremental. Los valores antiguos sin categoría «en juego» se excluyen del nuevo desglose.

## Pruebas ejecutadas

- **104 pruebas Flutter aprobadas.** Incluyen la matriz de umbrales en alta y baja, empate y victoria en extras, conservación del desglose de pitcheo y rechazo de la clasificación obsoleta. La suite existente de avances automáticos y del historial también pasó.
- **4 pruebas estáticas de contrato aprobadas.** Comprueban las categorías del SQL, el orden de llamadas, el cierre de la media entrada y las protecciones de identidades y ocupación.
- **Análisis Flutter sin errores**, con 2 advertencias heredadas y 16 avisos informativos.
- **Sintaxis de las tres propuestas verificada** con el parser PostgreSQL y PL/pgSQL de pglast. Las evidencias están en `evidencias/revision-*`.

No se ejecutó SQL ni se modificó Supabase. Tampoco se generó una APK de esta revisión. Queda pendiente validar la integración en LAB y la sincronización en dos teléfonos.
