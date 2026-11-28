# Dependencia del almacenamiento de deshacer DP

La auditoría de solo lectura en LAB encontró una única columna material
dependiente del tipo compuesto de `public.swl_live_games`:
`swl_private.v57_dp_undo_state.prior`. PostgreSQL rechazó añadir columnas
a la tabla porque hacerlo cambia ese tipo compuesto. Las referencias en
firmas de funciones siguen apuntando al mismo tipo y no son columnas
persistentes. Las dos RPC que crean snapshots y el ayudante que los lee se
identificaron en `pg_proc`. La RPC pública de deshacer sigue delegando al
ayudante con la misma firma.

LAB tenía dos snapshots, ambos de SWL-378859. La tabla era propiedad de
postgres, con RLS activado y sin permisos para anon o authenticated.
La migración toma ambos bloqueos en el orden que usa la anotación,
convierte la columna en sitio con `to_jsonb` y conserva cada fila,
clave primaria, clave foránea y metadatos. Los snapshots convertidos son
v1 y las dos RPC escriben v2 de manera explícita. Este diseño evita mantener
un segundo tipo compuesto acoplado al partido y preserva campos históricos
que las operaciones de deshacer no consumen.

Al deshacer se valida la identidad y versión del snapshot. La reconstrucción
tipada se limita a la lectura y el UPDATE restaura campos de la jugada por
nombre. El modo, las exenciones, los votos y las decisiones de knockout
no se copian desde el pasado. Una consulta pendiente impide deshacer y los
votos ya resueltos avanzan la versión. El cierre automático puede
deshacerse antes de las firmas bajo los permisos vigentes, conservando el
registro histórico AUTO y añadiendo el evento UNDO_OUT. Una solicitud de
cierre ya invalidada no se resucita.

La transacción comprueba las huellas de las tres funciones auditadas,
la ausencia de columnas que sigan dependiendo del compuesto, la igualdad
de todos los snapshots previos y los permisos y RLS antes del COMMIT.
Conserva la verificación de SWL-378859 y revierte los datos de prueba
mediante savepoint. No usa DROP CASCADE.
