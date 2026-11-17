# V5.3 — Consistencia de sustituciones en dos dispositivos

## Corrección
- Si una actualización Realtime llega mientras se lee el historial de sustituciones, se encola una nueva consulta en vez de descartarla.
- La cola se vacía únicamente después de terminar la lectura y si el partido sigue siendo el mismo.
- El polling de respaldo de 3 segundos también vuelve a consultar sustituciones, para cubrir eventos Realtime perdidos.
- Al salir o cambiar de partido se cancela la cola pendiente y se invalidan las respuestas anteriores.

## Pruebas pendientes
- Flutter SDK no disponible en este entorno. No se ejecutó compilación ni prueba real entre teléfono y tablet.
- El historial conserva un límite de 500 eventos con aviso.
- No se alteraron bases de datos ni se ejecutó SQL en esta entrega.
