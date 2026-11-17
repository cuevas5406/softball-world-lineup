# V5.3 — validación de alineaciones

- Editor local de 9–13 bateadores por equipo, incluido en la entrega previa.
- Nuevo: rechazo de nombres duplicados (ignorando mayúsculas/minúsculas).
- Nuevo: rechazo de números de uniforme duplicados cuando se especifican.
- No incluye todavía DH, AH, sustituciones ni persistencia.
- La pizarra local no sincroniza jugadas con Supabase.
- No se ejecutó Flutter analyze ni compilación APK.
- No se modificó Supabase.

## Incremento: roles de bateo
- Se añade selección por bateador: Normal, DH y AH en el editor local.
- Se impide asignar más de un DH por alineación.
- El rol se conserva al copiar instantáneas del partido.
- Estos roles son etiquetas de configuración, NO sustituyen al lanzador automáticamente ni asignan defensa.
- Pendiente: reglas completas de DH/pitcher, posiciones defensivas, sustituciones, sincronización y pruebas Flutter.

## Incremento: defensa inicial local
- Posiciones P, C, 1B, 2B, 3B, SS, LF, CF, RF y SIN (sin asignar).
- Validación contra posiciones duplicadas dentro del mismo equipo.
- AH no puede tener posición defensiva inicial en este editor.
- La asignación defensiva es opcional por ahora; no se considera una alineación defensiva completa ni se aplica al pitcher de estadísticas.
- No se han implementado sustituciones, sincronización, persistencia ni reglas completas del DH.
- No se ha ejecutado Flutter analyze ni compilación APK.

## Validaciones DH/pitcher (incremento)
- DH no puede ocupar una posición defensiva inicial.
- Con DH, ningún bateador puede estar marcado como pitcher (P).
- Sin DH, el pitcher puede aparecer como bateador.
- No se exige completar nueve defensores: el lanzador puede estar fuera del orden al bate.
- Aún no se asigna automáticamente un lanzador fuera del orden ni se sincroniza.

## Ajuste de interfaz (siguiente incremento)
- El editor de bateadores utiliza desplazamiento horizontal por fila para evitar desbordamientos en pantallas estrechas.
- Sigue pendiente verificar compilación y comportamiento en dispositivo.

## Sustituciones locales (incremento)
- Menú para sustituir bateador en Home o Visitante.
- Se mantiene el turno al bate y el rol/posición del jugador reemplazado.
- Se validan nombre y uniforme para evitar duplicaciones.
- Se guarda instantánea para DESHACER.
- Limitación: no registra un historial formal de sustituciones ni sincroniza con Supabase.
- No se compiló ni se ejecutaron pruebas Flutter.

## Integración incremental: nombres en lobby
- Tras crear o unirse al partido se consultan ambos equipos por ID.
- Se almacenan los nombres recuperados para mostrar Home y Visitante correctamente incluso si el usuario no administra el equipo contrario.
- Solo consultas SELECT: sin escritura de marcador ni de alineaciones.
- No se ha habilitado la anotación sincronizada; pendiente verificar permisos RLS y protocolo de concurrencia antes de cualquier escritura.
- No se ha compilado ni ejecutado Flutter analyze.

## V5.3: protección de lectura del partido compartido
- Evita consultas simultáneas de refresco del mismo lobby.
- Ignora respuestas Realtime y SELECT con versión inferior a la ya mostrada.
- Limpia caché de nombres al salir del partido.
- No activa escrituras de jugadas ni cambia permisos.
- Pendiente: validar compilación Flutter y sincronización en dispositivos.

## Lectura ampliada del marcador
- La pantalla compartida muestra hits, errores, bolas, strikes, outs, estado y versión.
- Se mantienen los nombres de equipos, carreras, entrada y turno.
- No se permite editar estos valores desde el lobby: solo lectura.
- No se ha conectado aún el editor local de alineaciones con Supabase.
- No se ha ejecutado Flutter analyze ni compilación APK.

## Visibilidad de sincronización (solo lectura)
- Se muestra la hora local de la última actualización recibida.
- Si falla la consulta periódica, se muestra una advertencia y se conserva el PIN y el estado anterior.
- La advertencia desaparece tras una consulta o evento Realtime satisfactorio.
- No se habilitan escrituras de jugadas ni se modifica Supabase.
- La hora no garantiza conexión activa: es solo la última actualización recibida.
- Sin pruebas de compilación Flutter en este entorno.

## Lectura de bases ocupadas
- El lobby muestra 1B, 2B y 3B según `bases_state` de `swl_live_games`.
- Un estado ausente o inválido se muestra como libre; no implica confirmación del servidor.
- Solo visualización; no se escribe en Supabase.
- Pendiente: escritura de jugadas segura, verificación de permisos, análisis Flutter y compilación.

## V5.3 — Protección contra consulta bloqueada
- La lectura periódica de `swl_live_games` tiene timeout de 12 segundos.
- El estado de última actualización solo avanza cuando se acepta una versión no anterior.
- Un fallo de red mantiene el marcador anterior y muestra aviso.
- No hay escritura sincronizada de jugadas ni cambios en Supabase.
- Validación estática parcial, sin SDK Flutter disponible para compilar.

## V5.3: Realtime autoritativo y cola de refresco
- El evento UPDATE ya no reemplaza directamente el estado local con un payload posiblemente parcial.
- Cada evento solicita una lectura SELECT versionada del partido activo.
- Si llega un evento mientras hay una consulta en curso, se programa otra lectura al finalizar.
- Se conserva el control de versiones y la protección de cambio de partido.
- Pendiente: escritura atómica de jugadas y autorización de mánagers.
- Sin SQL, sin cambios remotos y sin compilación Flutter.

## Historial de jugadas (solo lectura)
- Botón para consultar los últimos 20 registros de swl_game_events.
- Muestra tipo de jugada, entrada, mitad y versión.
- No registra jugadas ni modifica Supabase.
- Sin compilación ni pruebas Flutter.

## Corrección de historial
- Evita que una consulta del partido anterior libere el indicador de carga del nuevo.
- El aviso de historial vacío aparece solo después de consultar.
- Sin cambios en Supabase; compilación Flutter pendiente.

## Protección de consultas entre partidos
- Generación de sesión para descartar respuestas de un partido anterior.
- Al cerrar o cambiar el partido se invalida la lectura pendiente y se libera el estado de actualización.
- Las consultas del historial también tienen generación propia para evitar respuestas obsoletas.
- No modifica la base de datos ni habilita escrituras de jugadas.
- Sin pruebas de Flutter analyze ni compilación APK.

## Auditoría de sesiones
- Corregido return dentro de finally en _refreshGame.
- Conservado control por generación para evitar mezclar partidos.
- No se ha ejecutado Flutter analyze ni compilación.

## Busqueda segura de equipos
- Se invalidan consultas de busqueda anteriores al cambiar el texto.
- Un error de una busqueda obsoleta no tapa resultados nuevos.
- No se ha ejecutado Flutter analyze ni compilacion APK.

## Integración de escritura (preparada, no habilitada)
- Flutter contiene `_recordPlay()` y controles por rol, versión y sesión.
- Los botones están desactivados mediante `_scoringBackendReady = false` porque el RPC aún no existe en LAB.
- Archivo `V5_3_RPC_PROPUESTA_NO_EJECUTAR.sql`: propuesta para revisión y autorización explícita; **NO EJECUTADA**.
- El RPC de ejemplo cubre solo contadores básicos; no implementar como anotación completa sin reglas de corredores, boleto, ponche y pruebas.
- No cambiar el indicador a `true` hasta aprobar/aplicar/verificar backend y probar con dos mánagers.

## LAB: función básica desplegada (16 nov 2026)
- Migración confirmada: swl_v53_atomic_basic_play_foundation.
- RPC: swl_v53_record_play(uuid,bigint,text).
- Solo authenticated; anon no tiene EXECUTE. Verificado en LAB.
- Acciones básicas: BALL, STRIKE, OUT, RUN, HIT, ERROR.
- WALK y STRIKEOUT completos, corredores, lineups y anotación por bateador aún NO implementados.
- Flutter mantiene _scoringBackendReady=false por seguridad.
- Archivo V5_3_RPC_PROPUESTA_NO_EJECUTAR.sql es una propuesta anterior, NO usar para desplegar.
- No se ha probado una jugada real ni compilado APK.

## Protección de confirmaciones de jugadas (V5.3)
- Cada petición de anotación tiene un identificador de generación.
- Al cambiar de partido o salir del lobby, las respuestas tardías no alteran mensajes ni estados del nuevo encuentro.
- El mensaje de solo lectura solo se presenta cuando el backend de anotación está deshabilitado.
- La escritura sigue desactivada mientras se completa el motor deportivo; no se declara lista la fase.

## Prueba de escritura LAB (parcial, no final)
- Se habilitan controles básicos para mánagers conectados mediante RPC swl_v53_record_play.
- BALL/STRIKE bloqueados en el límite para no simular boletos/ponches; OUT cambia mitad/entrada.
- RUN/HIT/ERROR son contadores manuales, NO mueven corredores ni actualizan alineaciones.
- Solo utilizar en partidos de prueba LAB; no usar en partidos oficiales.
- Pendientes: reglas deportivas, pruebas de sesión, compilación Flutter.

## Protección de contadores LAB
- RUN y HIT requieren confirmación explícita antes de la RPC.
- ERROR se deshabilita temporalmente porque la función básica atribuye el error al equipo al bate, no al defensivo.
- Se indica el rol del mánager. Sin pruebas en dispositivos ni compilación Flutter.

## Corrección de interpretación de ERROR
- Verificado el SQL instalado: cuando batea el visitante (is_top=true), el error se asigna al local; cuando batea el local, al visitante. Ya era correcto.
- Se habilita ERROR en el panel de pruebas LAB, con confirmación previa.
- RUN/HIT/ERROR son contadores manuales de prueba; no simulan jugadas completas.
- No se ha compilado Flutter ni probado en dos dispositivos.

## Confirmación del tercer out
- Antes de registrar el tercer OUT, se solicita confirmación porque cambia la mitad de la entrada y limpia las bases.
- Se verifica que partido y versión sigan siendo los mismos tras el diálogo.
- No se ha compilado Flutter; no equivale a anotación completa.

## Conciliación de anotaciones inciertas
- Si RPC falla o agota tiempo, consultar evento exacto por game_id/version anterior + 1, actor y acción.
- No recomendar reintento automático, para evitar duplicar carreras o hits.
- Bloqueo adicional de confirmaciones simultáneas tras diálogo.
- La comprobación es de código fuente y ZIP, no compilación ni prueba real.

## Protección ante resultado incierto
Si falla una petición de anotación, los controles quedan bloqueados hasta reconciliar el evento o hasta que el mánager revise marcador e historial y confirme explícitamente. No supone garantía de idempotencia del servidor; para ello se requiere un identificador único por petición persistido en LAB. Sin compilación Flutter.

## Motor de reglas aislado (pendiente de integrar)
Se añadió `lib/swl_play_rules.dart` con transiciones puras de boleto forzado y ponche, y ocho pruebas en `test/swl_play_rules_test.dart`. **No está conectado a la pantalla ni al RPC**, para evitar discrepancias cliente/servidor. No incluye tercer strike no retenido, reglas de fin de partido ni corredores identificados. Pruebas escritas pero no ejecutadas: Flutter SDK no disponible.

## Previsualización de hits con destinos explícitos
Se agregó SwlPlayState.hit para sencillo, doble, triple, jonrón y avance de corredores con validación de destinos y seis pruebas unitarias nuevas. Es un motor puro local, todavía NO conectado al RPC de LAB; no incluye outs en bases, sacrificios ni errores.
\n## Avances de corredores sin turno concluido\nSe añadió `advanceRunners` al motor puro: robo, lanzamiento descontrolado y passed ball pueden mover corredores sin reiniciar bolas y strikes. Valida ocupación y destinos. Cinco pruebas adicionales escritas (19 en total); no ejecutadas. No está integrado con RPC ni se atribuyen estadísticas individuales.\n
## Elevados de sacrificio (motor local)
Añadido `sacrificeFly` con validación de destinos, out, carreras y cambio de mitad. No modela apelaciones, tercer out por corredor ni jugadas de tiempo; esas variantes requieren resolución explícita en servidor. Cinco pruebas unitarias nuevas (24 escritas en total, no ejecutadas). No integrado en Supabase ni habilitado en el marcador.

## Out de corredor (cogido robando / pickoff)
Se añadió `runnerOut(base:)` al motor puro, conservando bolas y strikes salvo tercer out. Seis pruebas unitarias nuevas escritas, no ejecutadas. No hay integración con Supabase LAB ni compilación Flutter.

## Doble play básico
Añadido `batterRunnerDoublePlay`: retira al bateador y un corredor seleccionado, sin carreras ni avances. Valida 0/1 outs previos y base ocupada; maneja tercer out. Cinco pruebas escritas (35 acumuladas), no ejecutadas. No representa dobles matanzas complejas, ni está conectado a Supabase LAB.

## Consistencia de destinos y conteos (validación local)
- En hits, un corredor preexistente anota con destino `0`, nunca `4`; `4` se reserva para jonrón del bateador. Se rechaza el dato ambiguo antes de calcular carreras.
- Los avances sin terminar turno validan rangos de bolas, strikes y outs.
- Se agregaron tres pruebas unitarias (38 escritas en total, no ejecutadas).
- Pendiente: motor transaccional en LAB y verificación de compilación Flutter.

## Validación de jonrón
Se rechazan destinos de corredores que no sean home (0) cuando batterBase=4. Dos pruebas unitarias añadidas. No se ha compilado ni ejecutado Dart/Flutter.

## V5.3 — Carreras por entrada (motor local)
Añadido `lib/swl_inning_totals.dart`: registra diferencias de carreras en el inning en que ocurrió la jugada, incluso si el tercer out cambió de mitad. Valida que las carreras correspondan al equipo que bateaba y rechaza saltos de entrada. Cinco pruebas nuevas escritas en `test/swl_inning_totals_test.dart` (45 en total, sin ejecutar). Falta implementar esta misma garantía en RPC de LAB y sincronizar `home_innings`/`away_innings`. No equivale a box score integrado.

## Conciliación de carreras por entrada
El módulo local ahora rechaza totales por entrada que no concuerden con el marcador anterior y entradas futuras. Tres pruebas adicionales escritas. No sustituye la conciliación transaccional del servidor; pruebas Flutter sin ejecutar.
\n## Auditoría visual del desglose por entrada\nEl lobby muestra carreras por entrada únicamente si ambos arreglos del servidor son válidos y sus sumas coinciden con el marcador. De lo contrario muestra una advertencia y no presenta datos inconsistentes como oficiales. No modifica la base de datos. Pendiente de compilar Flutter.\n
## LAB: integración de RUN con innings (17 noviembre 2026)
Se actualizó en LAB `swl_v53_record_play` para que la acción RUN llame a `swl_v53_inning_delta` y guarde `home_innings` y `away_innings` en el mismo UPDATE del partido, junto con la carrera, el evento y la versión. No se alteraron partidos existentes. La acción RUN sigue siendo un contador manual de prueba, no una jugada completa. No se ha verificado la invocación con sesión de mánager ni compilado Flutter. Producción sin cambios.

## Verificación SQL de innings en LAB
Se ejecutaron cinco casos SQL, incluidos tres rechazos esperados, sin alterar partidos. Consultar `V5_3_PRUEBAS_SQL_INNINGS.md`. No se ha ejecutado una anotación real autenticada.

## Protección de diálogos simultáneos
Se añadió `_confirmingPlay` para impedir abrir varias confirmaciones y enviar acciones superpuestas. Los errores de lectura posteriores a una escritura RPC confirmada ya no se clasifican como escritura incierta. Pendiente compilación Flutter y pruebas en dos dispositivos.

## Invariantes del motor local
Se añadió `_validateGameState` a siete métodos de jugada para rechazar conteos, entradas o carreras imposibles antes de simular. Cuatro pruebas unitarias nuevas escritas, no ejecutadas. No se modificó Supabase.
\n## Vista previa del boleto en Flutter\nLa confirmación de la cuarta bola ahora enumera avances forzados según las bases recibidas de LAB y avisa de la carrera con bases llenas. La decisión definitiva permanece en el RPC. No se ha compilado Flutter.\n
## Corrección avances forzados
En hits, corredores no forzados pueden conservar su base; los forzados deben avanzar. Se añadieron cuatro pruebas no ejecutadas. No se modificó Supabase.

## Control de concurrencia de alineaciones (LAB)
- Nueva RPC swl_v53_save_lineup_checked con revisión esperada (0 si no existe).
- Bloqueo transaccional del partido y comparación de revisión; error STALE_LINEUP_REVISION si cambió.
- Se revocó EXECUTE a authenticated en la RPC antigua para evitar saltarse la revisión.
- Flutter envía p_expected_revision desde la última lectura de la alineación.
- Requiere volver a consultar después de un conflicto o error de red.
- No se han ejecutado pruebas de dos sesiones autenticadas ni compilación Flutter.

## Turno al bate controlado por LAB
Nueva tabla swl_game_batting_turns con RLS y lectura para mánagers.
La RPC swl_v53_apply_hit_for_player comprueba el siguiente bateador, añade
batting_order al evento y avanza el cursor en la misma transacción del hit.
Flutter consulta el cursor y muestra al bateador asignado (sin selector manual).
El cursor avanza SOLO con hits: boletos, ponches, outs y sustituciones aún
requieren integración. No utilizar todavía como anotación oficial completa.
No se compiló Flutter ni se probó con sesiones reales.

## Turnos de apariciones al plato (LAB)
swl_v53_record_plate_action registra BALL, STRIKE y OUT con batter_id y batting_order.
Solo avanza al próximo bateador al completar boleto, ponche o out.
Se apoya en la misma transacción del contador y evento; el servidor verifica la alineación.
Flutter lee el turno desde LAB antes de enviar cada acción.
Limitaciones: la RPC antigua de contadores sigue expuesta para RUN/ERROR de prueba y permite eludir
el turno mediante acceso directo; pendiente reemplazarla antes de uso oficial.
Sin compilación Flutter ni prueba autenticada real.
