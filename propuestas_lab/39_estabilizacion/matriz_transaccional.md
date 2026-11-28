# Matriz de validación de SWL V5.7 en LAB

Destino exclusivo para instalación posterior: `wgeziptdoabyicufnrfk`.
Los 34 escenarios contabilizados abajo son casos preparados, no ejecuciones.
Los controles de integridad rodean todos los casos y no se cuentan como
escenarios deportivos.

| Casos | Cantidad | Resultado exigido |
|---|---:|---|
| A01 | 1 | Alineaciones de equipos distintos: un mismo UUID no puede representar a ambos |
| K01–K04 | 4 | 3.ª baja y margen 15: automático, desactivado, consulta y reanudación, consulta y cierre. En consulta se rechazan jugadas, votos repetidos y usuarios ajenos. Dos votos para continuar reanudan y se reevalúa en 4.ª |
| K05–K10 | 6 | 3.ª con margen 15: para cada modo, visitante conserva ventaja tras la baja o el local reduce a 14. En ambos casos el local batea; al reducir la diferencia se continúa |
| K11–K16 | 6 | 4.ª con margen 10: los mismos dos resultados en los tres modos; el local conserva su turno, y con margen 9 el encuentro sigue |
| K17–K22 | 6 | Local arriba por 15 en 3.ª o 10 en 4.ª, tres modos por entrada: se resuelve al terminar la alta, salvo modo desactivado |
| E01–E05 | 5 | Un corredor retirado en primera, segunda, tercera o home con cero outs; repetir en segunda con dos outs previos. Un error, sin hit adicional, crédito al pitcher y cambio de mitad al tercer out |
| E06–E09 | 4 | Dos outs con carrera; dos outs y carrera de tiempo al tercero; tercer out forzado sin carrera; tres outs en una jugada. Repetición rechazada, historial y pitcheo consistentes |
| P01 | 1 | Sencillo y error, relevo con dos heredados, HR de tres, sencillo, error con out y sustitución del corredor retirado. El titular permite 2 C y 1 CL; el relevo, 1 C y 1 CL, con 0.1 IP. Total: 3 C y 2 CL |
| F01 | 1 | Rol autenticado ajeno a ambos equipos: misma fuente oficial, dos alineaciones, historial, sustitución, posiciones, bateo, pitcheo y totales. Escrituras y acceso anónimo rechazados, información privada excluida |

## Cobertura y límites

- La prueba SQL P01 utiliza las RPC y comprueba el historial y los créditos
  oficiales antes de reconstruir las C y CL esperadas de ese caso. El test
  Flutter correspondiente comprueba el cálculo que realmente usa la aplicación
  con una reproducción de la misma secuencia y los mismos resultados.
- F01 aplica el rol PostgreSQL de la API y un UUID sintético sin vínculos de
  mánager. Comprueba permisos efectivos en la sesión transaccional. Una cuenta
  autenticada de extremo a extremo, el inicio de sesión y el Box Score en dos
  dispositivos requieren una prueba de cliente aparte del SQL.
- La comparación del fanático usa la misma proyección bajo ambos perfiles y
  contrasta campos deportivos con las tablas oficiales. El SQL no renderiza
  pantallas, ni convierte jugadas históricas con atribución incierta en ceros.
- Un caso crítico fallido aborta la transacción. La reversión del savepoint
  elimina los datos de prueba antes de comparar las huellas del partido
  protegido y las propiedades y permisos de las funciones.
