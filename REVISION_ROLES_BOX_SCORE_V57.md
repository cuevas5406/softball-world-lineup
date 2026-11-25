# V5.7 · Roles y Box Score

Base revisada: commit 8497203deb88596611df13e41f2b278d391ce511, rama pruebas-de-V5.7.

## Estado y alcance

- Mánager usa el mismo Hub y los mismos permisos comprobados contra Supabase. El menú cambia la experiencia de la sesión. La preferencia no altera el rol de la cuenta ni los equipos administrados.
- Pelotero reutiliza el UUID y el código de la ficha histórica. La identidad de cuenta usa un vínculo uno a uno independiente de las preferencias y de profiles.player_id, cuyo origen y verificación requieren una auditoría. La foto anterior de players se excluye mientras su visibilidad no esté verificada.
- Un administrador debe verificar al atleta por un canal independiente y confirmar el UID de su cuenta. Luego puede emitir en el servidor una invitación para ese UID y el UUID histórico. Generar 32 bytes aleatorios, codificarlos como 64 caracteres hexadecimales en minúsculas, guardar SHA-256 del texto UTF-8 y fijar un vencimiento corto. Entregar el token al titular verificado. El cliente únicamente consume la invitación. Renovaciones y resolución de vínculos existentes corresponden al administrador. Auditar el emisor y conservar registro de la verificación fuera del token.
- El perfil permite cambiar biografía y una foto JPEG privada. El historial muestra actuaciones oficiales acreditadas. Las fichas, equipos y estadísticas se leen de los registros existentes. El historial de apariciones sin bateo ni pitcheo acreditado queda fuera.
- Fanático abre En vivo, Resultados oficiales y Favoritos. Los favoritos se guardan por cuenta y dispositivo. Realtime provoca una relectura del marcador y existe respaldo periódico. La lectura de alineaciones requiere el nuevo RPC. La política existente del marcador sigue siendo la fuente de Postgres Changes. Validar volumen y privacidad de esas emisiones antes de producción.
- La exportación requiere una lectura nueva con estado OFFICIAL. Los resultados muestran PNG y PDF mediante el selector nativo de Android. PNG incorpora el icono de la app, equipos, escudos legibles, columnas por entradas y totales. El PDF diferencia los equipos al bate y muestra pitcheo acreditado. Los datos ausentes se marcan o se omiten. La fecha corresponde al registro de creación del partido.
- Sin instalar SQL, funciona la navegación, la lista de partidos que permite la RLS instalada y el PNG de resultados OFFICIAL visibles. El PDF aún puede generarse con el marcador y el pitcheo que la sesión tenga autorizado. El desglose de bateo, las alineaciones públicas y el perfil vinculado requieren la propuesta del servidor.
- La app conserva las reglas deportivas existentes. LAB presenta el atributo de posición secundaria como ausente en players y se mostrará vacío hasta habilitarlo. Las reglas transaccionales de refuerzos se mantienen en la propuesta 26 y su instalación requiere revisión y autorización separadas.

## Dependencias y verificación

La inspección de LAB de solo lectura revisó columnas, políticas, RPC, Storage y publicación Realtime. Los marcadores y eventos están publicados. Las alineaciones y el pitcheo son restrictivos para el espectador. Los resultados incluyen el historial UNDO_OUT y se omite la jugada revertida del cómputo de bateo. El pitcheo ya retira la fila revertida en la operación existente. Verificar en un entorno autorizado los cambios de identidad, los actores de RLS, los permisos de Storage, cargas concurrentes, datos históricos y los cómputos deportivos con partidos desechables. Para adopción masiva conviene medir coste de las consultas por historial y añadir índices según el plan real. Revisar limpieza de fotos sustituidas y los archivos temporales de exportación.

Propuesta sin ejecutar: propuestas_lab/28_v57_roles_box_score.sql. Las comprobaciones estáticas y de Flutter no sustituyen pruebas con cuentas independientes, dos Android y WhatsApp. No se escribió en Supabase ni en SWL-540617.
