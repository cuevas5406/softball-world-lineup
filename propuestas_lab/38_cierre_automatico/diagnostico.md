# Cierre automático · revisión LAB

Proyecto LAB wgeziptdoabyicufnrfk. Inspección de solo lectura.

SWL-378859 está en versión 58, tercera baja, dos outs, bases vacías y 16–1
a favor de Los 300. La diferencia es exactamente 15. La RPC instalada
`swl_v56_close_after_play` intenta insertar AUTO al cerrar y INVALIDATED
cuando una nueva jugada invalida una solicitud. La restricción instalada
solo admite REQUEST, ACCEPT, REJECT y SIGN. El INSERT falla y la transacción
completa revierte el out, el crédito del pitcher y el cambio a FINAL.

El motor instalado ya usa márgenes inclusivos: 15 en tercera y 10 desde
cuarta. Da al local la oportunidad de batear si el visitante está en
ventaja, omite la baja cuando el local ya ganó al terminar la alta
correspondiente y admite extras si termina empatado. El parche amplía
la restricción con AUTO e INVALIDATED y alinea la solicitud bilateral
con Flutter, disponible desde quinta para un encuentro sin empate.
Se conservan la clave única partido/versión/acción, los permisos, las
dos firmas y la decisión automática registrada en la versión del último out.
El último out y los créditos estadísticos continúan en la misma transacción.

Las consultas de solo lectura no alteraron partidos. PostgreSQL aún no
ha ejecutado los 15 escenarios de cierre y 5 de decisiones propuestos.
La migración requiere autorización. Validar bajo un savepoint en LAB,
revertir los datos temporales, comparar huellas de SWL-378859 y confirmar
el DDL solo si pasan las pruebas. La sincronización en dos Android debe
validarse después de autorizar y aplicar.

## Carreras limpias parciales

La reproducción del historial con el agregador Dart confirmó que en la
versión 48 el #92 muestra ≥9 CL y el equipo ≥10. En la versión 58 los
mínimos son ≥13 y ≥14, respectivamente. El #92 tiene 15 C. Si una pantalla
sigue mostrando los mínimos anteriores, revisar qué versión cargó.

El error defensivo de la versión 27 deja una carrera sucia confirmada.
En la tercera alta el corredor avanzó de segunda a tercera en la versión
46 mediante RUNNER_MOVE, sin indicar si fue robo, wild pitch, passed ball
u otro motivo. Anotó desde tercera con el sencillo de la versión 47.
El segundo avance manual, versión 48, no impide determinar las carreras
del jonrón posterior. Los DP anulados en versiones 50 y 52 no cuentan.
La lectura confirma las carreras permitidas. La clasificación de esa
carrera de la versión 47 queda pendiente: el historial no dice cómo
se produjo el avance ni reconstruye toda la jugada sin ese avance.
Cambiar un mínimo por una cifra exacta requeriría evidencia adicional.

## Corrección Flutter de avances futuros

La pizarra permite registrar el motivo al mover un corredor: robo, wild pitch,
bola pasada u otro motivo. La RPC de jugadas especiales instalada acepta
`p_data` y conserva ese JSON en el historial. Para este campo no hace falta
migración. Robo y wild pitch documentados no generan incertidumbre por sí
solos. Para bola pasada o causa desconocida se conserva la incertidumbre
cuando afecta al anotador y no puede resolverse con una jugada posterior
como el jonrón. El agregador conserva esa marca al sustituir al corredor.
El Box Score explica el símbolo ≥. El avance existente de la versión 46
queda sin causa registrada.
