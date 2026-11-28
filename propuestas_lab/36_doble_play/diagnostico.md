# Doble play con corredores múltiples

El guardado actual en LAB llama a swl_v57_double_play(uuid,bigint,integer).
La función instalada rechaza ocupación distinta de un corredor mediante
DOUBLE_PLAY_OTHER_RUNNERS_NOT_SUPPORTED y pone las tres bases vacías.
La rama DOUBLE_PLAY de swl_v56_special_play elimina el corredor seleccionado,
pero no implementa avances ni carreras para esa acción. No se usa como
alternativa al flujo actual.

La migración propuesta crea una RPC independiente. Valida versión y turno
con la función existente, comprueba la identidad de los corredores y exige
destinos válidos, sin colisión, retroceso ni rebase. Una carrera con un out
previo exige que el mánager certifique que el tercer out fue de toque sin
fuerza y que la carrera entró antes del out. Nunca cuenta carreras de
corredores que siguen detrás del corredor del tercer out. El mánager debe
dejar la opción desactivada si el bateador es el tercer out antes de primera.
Registra el evento, el crédito de pitcheo, los cambios de marcador y bases
en una sola transacción. El flujo de un solo corredor conserva la RPC previa.

SQL pendiente de autorización. Antes de habilitar, probar en LAB con partidos
temporales las ocho ocupaciones con cero, uno y dos outs, cada corredor
seleccionable, avances válidos e inválidos, carreras con cero outs, tercer
out forzado, carreras por tiempo, versión obsoleta y mánager rival.
Verificar los UUID en bases y anotadores, dos outs de pitcheo, una aparición,
un lanzamiento en juego, cierre de mitad y estadísticas e historial en ambos
dispositivos. Revertir todas las jugadas de prueba. SWL-378859 queda fuera.
