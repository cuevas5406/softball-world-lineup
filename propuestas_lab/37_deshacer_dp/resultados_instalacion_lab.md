# Instalación verificada de Deshacer DP en LAB

Proyecto `wgeziptdoabyicufnrfk`. Se ejecutó el archivo aprobado byte por
byte, con SHA-256 `4e6dd80e0d8252bb841e75ba2c9f87533ee0b27a3607b00843a32f4f13258c2f`.
La migración de `14386f9`, el filtro del agregado legado de bateo y la
regresión ampliada se ejecutaron dentro de la misma transacción.
El COMMIT solo confirmó el esquema y las funciones tras revertir los datos
temporales y comprobar la integridad del partido.

## Pruebas efectivamente ejecutadas en LAB

- Matriz de 72 combinaciones de ocupación, outs y origen, con escenarios
  adicionales para conservación de corredores, avances y carreras.
- Deshacer DP de uno, dos y tres corredores, con carreras y cambio de mitad.
  Se verificó la restauración de bases, UUID de corredores, marcador, turno,
  outs, bolas, strikes y media entrada. El mánager de la mitad original
  pudo revertir aun después del cambio de lado.
- Se rechazaron la versión obsoleta, la repetición y el mánager rival.
- Se verificaron el pitcher original en el historial, el evento de auditoría,
  la eliminación del crédito anulado de pitcheo y la exclusión de la PA
  en el agregado legado y de la jugada en los agregados oficiales.
- Se verificó la compatibilidad con el DP previo y Deshacer OUT sencillo.
- Quedaron cero partidos, cero peloteros y cero respaldos de prueba.
- Los RPC públicos conservan EXECUTE para authenticated, sin EXECUTE para
  anon. El helper privado queda fuera de ambos roles.

SWL-378859 sigue IN_PROGRESS, versión 48. Sus huellas coinciden con
las comprobadas antes de la instalación. Producción queda fuera del alcance.
No se generó APK. La sincronización física queda por validar en dos Android.

## Lectura posterior

```json
{
  "version": 48,
  "status": "IN_PROGRESS",
  "game": "60f9a89d7225f6f304cfc5da5fc89dae",
  "events": "fd51662417205522b87d4be113092c10",
  "pitching": "b6703990e31c6f9e39aa322f1aa366d2",
  "lineups": "270aff831553b092b095ec6e9c5578f5",
  "snapshots": 0,
  "temporary_games": 0,
  "temporary_players": 0,
  "functions": [
    [
      "swl_v53_batting_stats",
      "515aae1bd95a54396ba98203a067817a",
      true,
      false
    ],
    [
      "swl_v57_double_play",
      "e2dd9eeadb775524e4899189b6848c1e",
      true,
      false
    ],
    [
      "swl_v57_double_play_advanced",
      "ba853729bcdac68139d22816d35191f9",
      true,
      false
    ],
    [
      "swl_v57_undo_last_out",
      "9b43922d7f0805ad40e107e39bf5d23b",
      true,
      false
    ],
    [
      "v57_undo_dp",
      "ad22b39c084a0efb7b88fa725c7247e6",
      false,
      false
    ]
  ]
}
```
