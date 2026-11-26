# Cancelación conjunta en Supabase LAB

Proyecto LAB `wgeziptdoabyicufnrfk`. La inspección fue de solo lectura. Faltan
`public.swl_v57_cancel_game(uuid,bigint,text)`, la columna de solicitud y
la tabla de auditoría. El check `swl_live_games_status_check` admite
SCHEDULED, IN_PROGRESS, FINAL y OFFICIAL. La fila de SWL-567892 estaba
IN_PROGRESS, versión 22. La tabla de partidos ya publica sus cambios
en Supabase Realtime.

La propuesta `../27_v57_cancelar_partido.sql` añade CANCELLED al check, la
columna y una auditoría con RLS. La RPC bloquea la fila, comprueba la identidad
de los dos mánagers, el permiso vigente del equipo, el estado y la versión.
Solo el otro mánager puede responder. Cada decisión actualiza la versión y
se registra en la misma transacción. El otro dispositivo muestra la solicitud
en la lista de partidos y en la pizarra mientras la aplicación está abierta.

La protección de participación vigente ignora los partidos CANCELLED al
buscar vínculos con otros encuentros. Se conservan la alineación, el historial
y el registro de participación, incluidos sustituidos. El bloqueo de
anotación exige IN_PROGRESS. Bateo y pitcheo oficiales exigen OFFICIAL.

Antes de instalar, verificar nuevamente el proyecto, el check, los permisos
y la huella del partido, alineaciones e historial de SWL-567892. Aplicar la
propuesta solo con autorización. Ejecutar `pruebas.sql` en una transacción que
revierte todos sus datos de prueba y comprobar las huellas del partido original.
Validar en dos Android y una vista de fanático que la solicitud, el rechazo
y la aceptación se reflejan automáticamente.

El ALTER TABLE requiere un bloqueo y validar el check existente. La tabla de
auditoría no concede lectura ni escritura a clientes. Si falla la instalación,
la transacción revierte el DDL. Si falla la validación posterior, retirar la
habilitación antes de que los mánagers usen la función. Una vez registrada
cualquier decisión, conservar la columna y la tabla de auditoría. En ese
caso, para detener nuevas decisiones, revocar EXECUTE de authenticated en la
RPC, previa autorización.
