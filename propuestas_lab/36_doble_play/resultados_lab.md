# Verificación de doble play en LAB

La RPC publicada es exactamente la propuesta de 1d76835. La instalación
y la prueba se ejecutaron en una sola transacción. La prueba corrió con
SAVEPOINT y ROLLBACK TO SAVEPOINT antes de confirmar únicamente el DDL.
Después se comprobó EXECUTE para authenticated, ausencia de EXECUTE para
anon y cero partidos o peloteros temporales. La huella de la RPC anterior
coincidió. La huella del partido SWL-378859, versión 47, coincidió dentro
de la transacción. En las lecturas externas se observaron un hit y un
avance registrados por mánagers, versiones 47 y 48 respectivamente.

## Escenarios ejecutados

- 72 casos de ocupación (8 máscaras × 3 cantidades de outs × 3 orígenes).
  Se comprobaron resultado o rechazo, los UUID de los corredores que quedan,
  el contador de outs, el bateador, el siguiente turno y el evento DP.
- 9 escenarios adicionales: avance y carrera, dos casos de carrera con
  cero outs, rechazo por tercer out forzado, carrera de tiempo con tercer
  out, compatibilidad de la RPC anterior, rechazo de versión repetida,
  rechazo al mánager que no está al bate y rechazo de Deshacer.
- Cada DP válido acreditó dos outs al pitcher activo en la fila de
  pitcheo de la misma versión. La prueba de Flutter confirmó 0.2 IP, un
  lanzamiento en juego, una PA y C/CL para un corredor de un pitcher
  anterior. Total Flutter: 193 pruebas aprobadas.

## Límites de la instalación autorizada

La fila de pitcheo acredita el UUID y se puede unir al evento por partido
y versión. El JSON de historial de la propuesta autorizada no guarda
pitcher_id. Deshacer último OUT acepta solo OUT básico. Se probó que
rechaza un DP y no cambia la versión ni elimina la jugada. Para deshacer
un DP habría que autorizar una extensión que conserve y restaure el
estado previo completo, incluida la mitad, las bases, las carreras, el
cursor al bate y el crédito de pitcheo, con control de versión y permisos.
