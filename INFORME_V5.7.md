# Softball World Lineup V5.7

La base de esta entrega es el ZIP Flutter V5.6 adjunto. El paquete incluye el proyecto Android, las pruebas, el workflow de GitHub Actions y las propuestas SQL de V5.7 para revisión.

## Matriz de cumplimiento

| Requisito | Cambios en V5.7 | Evidencia local | Pendiente de comprobar en vivo |
| --- | --- | --- | --- |
| 1. Alineaciones | Selección desde el roster, defensa en la primera vista y orden al bate en una segunda pantalla. Se puede mantener pulsado el asa y arrastrar. Las flechas siguen disponibles. Los turnos 12 y 13 pueden ser solo de bateo. Se conservan pitcher, DH y posiciones secundarias del perfil. | Pruebas Flutter del gesto real de arrastre en el widget, la validación defensiva, la recuperación de 13 turnos y las reglas de pitcher/DH. | Verificar el guardado de 13 turnos y las posiciones secundarias contra las RPC instaladas en LAB. |
| 2. Borradores | Se conserva el guardado automático por cuenta, partido, equipo y revisión. **Continuar después** conserva la edición. **Cancelar** pide confirmación si hubo cambios y restaura la edición inicial. La alineación confirmada se abre para editar con su revisión. | Pruebas del borrador y del editor verifican la copia de trabajo, el aviso, los cambios de orden y la validación antes de guardar. | Comprobar persistencia tras cerrar y reiniciar la APK y edición concurrente de una alineación confirmada. El servidor mantiene su bloqueo cuando comienza la anotación. |
| 3. Pizarra | **Hit**, **Doble**, **Triple** y **Jonrón**. Acceso a doble play. Error defensivo a cargo del equipo que defiende. Destinos de avance con outs, incluido home, y vista previa de carreras. Para un tercer out se requiere adjudicación explícita de jugada de tiempo válida para contar carreras previas acreditables. | Pruebas Flutter de doble play, out en home, tercer out forzado y jugada de tiempo. Contratos y sintaxis SQL validados localmente. | Validar hit/error, columna E, corredor retirado, evento de historial y marcador simultáneo en dos teléfonos. Depende de la propuesta 13 y del tipo de evento aceptado en LAB. |
| 4. Sustituciones | Menú **Cambios de jugadores** en la pizarra. Abre el flujo existente de sustitución. Cambio de pitcher en defensa, con protección del orden y del DH. La preparación permite intercambiar posiciones defensivas entre dos jugadores activos. | Prueba de acceso al menú de pizarra con transporte simulado, pruebas de reglas de sustitución y comprobaciones estáticas del intercambio. | Probar con dos mánagers las asignaciones, la versión del partido y la recuperación tras una respuesta incierta. El intercambio usa la propuesta 13. |
| 5. Reglas | El tercer out y el tercer strike se envían sin diálogo adicional. El evaluador de cierre usa la media entrada de la jugada. Conserva las firmas individuales, así como el flujo de decisión que ya existía. | Pruebas Flutter para 2–0 tras la alta de la sexta, umbrales 15 en tercera y 10 en cuarta, empate, extras y permisos de firma. La propuesta 15 está analizada sintácticamente. | Probar en un partido nuevo el cierre transaccional tras la alta de la sexta y el paso de FINAL a OFFICIAL con dos cuentas. |
| 6. Sincronización | Se oculta la barra repetitiva de alineaciones mientras continúa la consulta automática. Hay iconos pequeños para actualizar la pizarra y la preparación. | Prueba simulada del refresco manual, ausencia de barra de carga en la pizarra y rechazo de versiones antiguas. | Comparar marcador, alineaciones y eventos entre dos teléfonos durante anotación y reconexión. |
| 7. Mi Equipo | Al tocar el nombre se abre configuración con nombre, logo, localidad, dos colores, representante y contacto. El roster, el registro y el fichaje siguen en Mi Equipo. | Prueba con transporte simulado de lectura, normalización de color y envío del guardado con revisión. | Verificar permisos y persistencia de la propuesta 14 y del flujo de logo existente en LAB. |

## Archivos modificados

| Archivos | Contenido |
| --- | --- |
| `lib/swl_lineup_editor.dart` | Segunda pantalla, arrastre, orden y confirmación para descartar. |
| `lib/swl_play_rules.dart`, `lib/swl_advanced_scoreboard.dart`, `lib/swl_live_lobby.dart` | Previsualización de avances, anotación en vivo, historial, acceso a sustituciones, cambios defensivos y actualización. |
| `lib/main.dart`, `lib/swl_team_settings.dart` | Navegación desde Mi Equipo y formulario de configuración. Se conserva el editor de logo existente. |
| `propuestas_lab/13_v57_batazos_y_defensa.sql`, `14_v57_configuracion_equipo.sql`, `15_v57_cierre_reglamentario.sql` | Propuestas para jugadas y defensa, configuración autorizada y cierre. |
| `test/swl_game_finish_test.dart`, `test/swl_lineup_editor_test.dart`, `test/swl_official_scoreboard_test.dart`, `test/swl_play_rules_test.dart`, `test/test_v57_proposal_contracts.py` | Cobertura de V5.7. |
| `.github/workflows/build_apk.yml`, `pubspec.yaml` | El workflow incluye las comprobaciones V5.7. Versión Flutter de la aplicación 5.7.0, código Android 2. |
| `README.md`, `INFORME_V5.7.md` | Instrucciones de compilación, verificación y matriz. |

## Pruebas y alcance

- Flutter 3.50.0 y Dart 3.14.0. Se resolvieron las dependencias con el lockfile.
- Pasaron 128 pruebas Flutter y 12 pruebas estáticas de contratos.
- El análisis Flutter terminó con 0 errores, 2 advertencias heredadas y 18 avisos informativos.
- Se analizaron con pglast las tres propuestas nuevas, incluidas 28 sentencias y ocho cuerpos PL/pgSQL. Esto valida sintaxis local. Tipos, permisos, datos y transacciones requieren comprobación en LAB.
- Se intentó compilar la APK localmente. El entorno carece del Android SDK. La ejecución del workflow de GitHub Actions y la prueba en dos teléfonos están pendientes.
- El doble play de la pizarra cubre bateador y un corredor. Las jugadas compuestas permiten marcar varios outs, pero la adjudicación de carreras por tiempo se limita a un único out registrado en esa jugada. El anotador acredita las carreras que cruzaron antes de un tercer out permitido. No se registra el defensor individual.
- El cierre reglamentario depende de las RPC de servidor instaladas. El modo legado conserva su comportamiento previo. La propuesta 15 reemplaza los adaptadores de anotación V5.6 para que evalúen el cierre en la misma transacción y requiere revisar sus dependencias antes de cualquier aplicación.
- No se accedió a Supabase, no se ejecutó SQL y no se utilizó Google AI Studio. El partido **SWL-929159**, reportado como oficial 2–0 con dos firmas, no se usó en pruebas ni recibió escrituras. Las pruebas en vivo deberán usar otro partido.
