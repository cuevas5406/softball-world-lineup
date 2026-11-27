# SWL-378859 — Verificación de solo lectura en LAB

Proyecto LAB `wgeziptdoabyicufnrfk`. Versión 12, primera entrada baja,
marcador 0–0 y un hit de Los 300, visitantes. Los arreglos
`home_innings` y `away_innings` están vacíos en la fila oficial.

| Versión | Registro comprobado |
|---:|---|
| 2 | Los 300 sustituyeron a SWL-0031 por SWL-0029 en el turno 1. |
| 3 | El sencillo se acreditó a SWL-0029 y al pitcher de la defensa SWL-0019. |
| 4 | Los 300 sustituyeron a SWL-0007 por SWL-0032 en el turno 4. |
| 5 | Los Jodones cambiaron de SWL-0019 a SWL-0023. |
| 6–9 | SWL-0005 recibió una bola y tres strikes; el tercero completó el ponche. Los cuatro lanzamientos corresponden a SWL-0023. |
| 10 | SWL-0006 bateó el doble play, con SWL-0029 como corredor retirado. Los dos outs corresponden a SWL-0023. |
| 11 | Los 300 cambiaron de SWL-0021 a SWL-0028. Ninguno tiene lanzamientos registrados en este corte. |
| 12 | Los Jodones sustituyeron a SWL-0001 por SWL-0024 en el turno 1. |

Identidades confirmadas por UUID en los eventos, cambios de pitcher y
registros de peloteros. El DH de Los 300 es SWL-0012 y el de Los Jodones
es SWL-0014. La alineación actual tiene 10 y 9 bateadores respectivamente.

- Bateo. El RPC instalado `swl_v53_batting_stats` devuelve
  `batting_team_id`, pero Flutter filtraba por `team_id`. Además, el
  agregado antiguo omitía el doble play del turno oficial registrado.
  Los 300 tienen 3 PA, 3 VB, 1 H y 1 K en el historial consultado.
- Pitcheo. LAB tiene seis filas acreditadas, pero carecen de los campos
  de conteo por categoría que esperaba Flutter. La unión por versión
  con la jugada identifica un lanzamiento en juego para SWL-0019
  y cinco para SWL-0023 (una bola, tres strikes y un lanzamiento en juego).
  SWL-0023 retiró tres outs (1.0 IP), incluido un ponche.
- Entradas. El cliente anterior aceptaba arreglos vacíos que sumaran
  cero y los mostraba vacíos. La nueva vista muestra el cero del primer
  turno visitante y concilia con el marcador oficial. Si el historial no
  permite cuadrar el desglose, muestra un dato pendiente en esas celdas.
- Carreras individuales. Se usan los identificadores de anotadores y
  los créditos de empujadas registrados. Para carreras permitidas de un
  cuerpo con relevos o carreras limpias sin atribución suficiente se
  conserva el dato pendiente. El marcador del equipo sigue siendo oficial.

La nueva consulta es de solo lectura. No se cambian registros, RPC,
migraciones ni las reglas de anotación. La vista de fanáticos conserva
sus permisos originales y el flujo de compartir ya existente se conserva
para resultados oficiales sin ampliar su alcance.
