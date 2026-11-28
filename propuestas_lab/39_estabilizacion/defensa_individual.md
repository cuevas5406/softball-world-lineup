# Datos necesarios para estadísticas defensivas

La alineación identifica posiciones y cambios. El evento de error identifica
al bateador, al pitcher, las bases, los corredores y el error colectivo. Eso
no identifica al defensor responsable ni a quienes participaron en un out.
La posición, el pitcher activo y el destino del corredor no permiten deducir
un error, asistencia o putout individual. La duración de una aparición
defensiva tampoco se deduce solo del roster o de la alineación final.

## Registro propuesto para aprobación futura

- Guardar créditos explícitos por partido, versión de jugada, UUID del
  defensor y rol del crédito (PO, A o E). Vincular cada PO al out que lo
  produjo. Permitir varias asistencias cuando corresponda y distinguir los
  diferentes outs de una misma jugada.
- Ofrecer una anotación opcional desde la defensa activa que deje registrar
  el defensor, los participantes de una doble matanza y el orden de los
  tiros. Permitir «Sin atribución». Una omisión conserva el resultado
  colectivo y la jugada.
- Validar en la misma transacción equipo defensivo, posición y participación
  vigentes, identidad por UUID, número de outs y control de versiones.
  Excluir versiones anuladas, partidos cancelados y partidos sin oficializar
  de los acumulados oficiales.
- Reportar cobertura por tipo de crédito y período antes de ordenar rankings.
  Calcular porcentaje defensivo con PO, A y E observados solo cuando se
  conozcan las oportunidades que integran su denominador. Conservar
  el dato histórico desconocido como desconocido.
