# V5.3 — Protección del orden al bate durante el partido

- La RPC swl_v53_save_lineup_checked rechaza la edición de la alineación de un equipo si ya existe un evento con `batter_id` de ese equipo.
- La comprobación se ejecuta después de bloquear la fila del partido, antes de invocar la RPC interna de guardado.
- Se conserva la comprobación de revisión esperada y los permisos existentes de la RPC interna.
- Flutter avisa antes de guardar y muestra un mensaje claro si el servidor devuelve LINEUP_LOCKED_AFTER_FIRST_PLATE_ACTION.
- **No se han implementado sustituciones en juego.** El bloqueo es temporal para evitar reasignaciones incorrectas del orden y de las estadísticas.
- No se hicieron pruebas autenticadas con dos dispositivos ni compilación Flutter.
- Solo LAB. Producción no se modificó.
