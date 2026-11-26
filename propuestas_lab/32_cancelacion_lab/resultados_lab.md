# Resultado en LAB — 26 de noviembre de 2026

Proyecto `wgeziptdoabyicufnrfk`. Migración de cancelación conjunta instalada en una
transacción. Los escenarios de cancelación y la regresión de sustituciones
corrieron bajo savepoints y todos sus datos de prueba se revirtieron antes
del commit. Se repitió la prueba ampliada en una transacción independiente
con ROLLBACK. El respaldo de estructuras y huellas precedió la ejecución.

- Solicitud local y rechazo del visitante. El partido continuó y aceptó una jugada.
- Solicitud visitante y aceptación del local. Se registraron ambas identidades y
  la secuencia completa de solicitudes y decisiones en la auditoría.
- Rechazo de autoaceptación, autorrechazo, tercero no autorizado y versión obsoleta.
- Bloqueo del jugador sustituido mientras el partido seguía activo. Confirmación
  de disponibilidad de los 20 participantes históricos tras cancelar, incluido
  el saliente y el entrante. Inicio efectivo de otro encuentro con las
  alineaciones que incluyen al sustituido.
- Historial de jugadas idéntico tras cancelar, con cero estadísticas oficiales de
  bateo y pitcheo para el partido cancelado y rechazo de una jugada posterior.
- Regresión aprobada para sustitución del sexto turno, atribución del hit,
  cambio de pitcher bateador y de solo defensa con DH, y bloqueo por UUID
  entre equipos y partidos activos.

La comprobación posterior confirmó RPC accesible para authenticated, sin
EXECUTE para anon, RLS habilitada en auditoría, cero decisiones reales y
cero partidos o jugadores de la prueba. SWL-567892 siguió IN_PROGRESS
versión 22. Marcador, alineaciones, jugadas y huellas de reservas y fichajes
coincidieron. La secuencia SWL permaneció en 32.

## Reversión

Antes del primer uso real y con autorización, ejecutar `reversion.sql` solo
en LAB. Su guardia cancela la operación si hay decisiones o cancelaciones.
Restaura la restricción registrada en `respaldo_previo_lab.json`.

Si ya hay decisiones, conservar el esquema, los estados y los registros
de auditoría. Con autorización independiente, se puede suspender el uso
desde Flutter ejecutando `REVOKE EXECUTE ON FUNCTION public.swl_v57_cancel_game(uuid,bigint,text) FROM authenticated;`
y verificando que el rol ya no tenga EXECUTE. Esta suspensión no revierte
partidos ni elimina registros. Ninguna reversión se ejecutó.

Pendiente de prueba física: entrega del aviso al otro Android y actualización de
la vista de fanáticos al aceptar. La acción sobre SWL-567892 corresponde a sus
mánagers desde sus dispositivos.
