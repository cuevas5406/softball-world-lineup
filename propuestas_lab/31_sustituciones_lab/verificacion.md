# Sustituciones V5.7 en LAB

La migración incluye la prueba reversible ejecutada en un partido nuevo.
Se verificaron el sexto turno, el hit del sustituto, la preservación de las
estadísticas del pitcher anterior, la atribución al nuevo pitcher en ambos
modos, los permisos y la conservación de DH. También se verificó el rechazo
de un UUID en ambos equipos y en otro partido activo. El pelotero sustituido
sigue reservado en FINAL y se libera en OFFICIAL.

La prueba de concurrencia corrió en dos sesiones del planificador de LAB el
26 de noviembre de 2026 a las 05:12 UTC. B observó A en curso, esperó su
confirmación y recibió PELOTERO_EN_OTRO_PARTIDO_O_EQUIPO. SWL-998191 pasó a
IN_PROGRESS con versión 1 y SWL-998192 quedó en SCHEDULED con versión 0.
Se retiraron ambos trabajos temporales. Las dos fixtures quedaron programadas
sin reservas activas y sus 18 fichajes sintéticos quedaron inactivos. Pendiente
la eliminación de esas filas sintéticas.

SWL-567892 y SWL-540617 conservaron sus versiones y huellas de estado,
alineaciones e historial. La guarda protege nuevas incorporaciones y valida
ambas alineaciones al iniciar. Para corregir el duplicado histórico de
SWL-567892, decidir a qué equipo corresponde SWL-0002 y sustituirlo en el
otro por un suplente elegible en una operación autorizada. La atribución
histórica requiere revisión separada.

Se registraron y ficharon con el generador oficial las reservas SWL-0023 a
SWL-0027 para Los Jodones y SWL-0028 a SWL-0032 para Los 300. Cada equipo
recibió dorsales 93 a 97 en posiciones P, 1B, 2B, SS y LF. El alta empleó
swl_register_player y swl_sign_player. La reversión de esquema preserva los
códigos asignados y los registros de partidos.

