# Cierre automático instalado en LAB

Proyecto wgeziptdoabyicufnrfk. Archivo exacto autorizado y ejecutado en una sola transacción.
SHA-256: `6643050b70788059dd02a991333d573d76b193d7ce59f3601e076e345029998a`.

Pasaron 22 escenarios SQL con partidos temporales: 17 de cierre y 5 de
decisiones. Se comprobaron los márgenes inclusivos de 15 y 10, la oportunidad
de bateo del local, el cierre reglamentario, el empate y las extras, el
último out, el crédito del pitcher, el rechazo de reintentos y el bloqueo
de jugadas posteriores al cierre. También pasaron la solicitud desde quinta,
la invalidación por nueva jugada, el rechazo al tercero, las dos firmas, las
estadísticas oficiales y la participación en un partido posterior tras
oficializar. La publicación Realtime se verificó por catálogo.

El ROLLBACK TO SAVEPOINT retiró los datos temporales antes del COMMIT.
Lectura posterior: cero partidos y cero peloteros temporales. SWL-378859
sigue IN_PROGRESS en versión 58. Partido, historial, alineaciones, pitcheo
y decisiones conservan las mismas huellas. El avance de la versión 46
sigue sin clasificación. Producción queda intacta. No se generó APK.
Falta comprobar la sincronización física en ambos dispositivos.

```json
[
  {
    "version": 58,
    "status": "IN_PROGRESS",
    "partido": "5681a86bff47aa3629c854248bf8c1c2",
    "historial": "ce9c972f89e7c312a1492fbbcffbf737",
    "alineaciones": "270aff831553b092b095ec6e9c5578f5",
    "pitcheo": "5af577c4db0768775c4a6792b462fb19",
    "decisiones": null
  },
  {
    "constraint_actual": "CHECK ((action = ANY (ARRAY['REQUEST'::text, 'ACCEPT'::text, 'REJECT'::text, 'SIGN'::text, 'AUTO'::text, 'INVALIDATED'::text])))",
    "quinta": true,
    "partidos_temporales": 0,
    "jugadores_temporales": 0
  }
]
```
