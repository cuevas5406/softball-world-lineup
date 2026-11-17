# V5.3 — Protección local de operaciones simultáneas

- Se bloquean las acciones de anotación mientras está abierto el proceso de sustitución, incluso durante la selección de jugadores.
- Se bloquean nuevas sustituciones mientras hay una jugada, confirmación o sustitución pendiente.
- Si una RPC de sustitución devuelve un error o agota el tiempo de espera después de enviarse, se bloquea el nuevo intento hasta consultar el estado remoto.
- La reconciliación consulta directamente la versión del partido y las revisiones de alineación, y comprueba la actualización local.
- El servidor LAB ya dispone de control de versión del partido y revisión de alineación en la función `swl_v53_substitute_batter`; no se cambió SQL en esta entrega.

## Limitaciones

Esto protege la interfaz local y aprovecha la concurrencia optimista del servidor. No sustituye las pruebas entre dos dispositivos ni asegura que las estadísticas estén completas. No se ejecutó `flutter analyze` ni `flutter test` porque Flutter no está disponible en este entorno.
