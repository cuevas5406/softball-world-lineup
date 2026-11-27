# SWL-378859 — carreras por pitcher y defensa

Lectura de Supabase LAB, versión 26. Marcador 2–1 para Los 300 en la segunda alta.
Flutter mostraba C y CL como desconocidas en presencia de más de un pitcher
porque el Box Score solo tenía totales y créditos de lanzamientos por versión.

- Versión 14. SWL-0024 (#94, Los Jodones) bateó un jonrón solitario ante
  SWL-0028 (#93, Los 300). Se registra 1 C y 1 CL a ese pitcher.
- Versiones 23, 25 y 26. SWL-0032 (#97, Los 300) llegó a primera con un hit
  ante el #93 de Los Jodones. El #92 relevó en la versión 25 y permitió el
  jonrón de dos carreras. El corredor heredado sigue a cargo del #93 y el
  bateador corresponde al #92. El #91 termina con 0 C y 0 CL. Los otros dos
  terminan con 1 C y 1 CL cada uno, y el total es 2 C y 2 CL.
- La defensa guardada de Los Jodones contiene P, 1B, 2B, 3B, SS, LF, CF, RF
  y SF, sin asignación C. Los 300 sí tienen C. Se muestra «Sin receptor asignado»
  para explicar el dato registrado. Se conserva el escudo genérico de Los 300.

## Reconstrucción

El Box Score agrupa jugadas por mitad de entrada, enlaza el pitcher acreditado por
versión y conserva la responsabilidad del corredor al cambiar su identidad por
sustitución. Usa los anotadores identificados por el servidor y comprueba el
total contra el marcador. No reasigna al relevista las carreras de corredores
heredados.

Un corredor que alcanzó base por error no produce una limpia. La reconstrucción
considera las oportunidades de out perdidas; para el relevista separa las
oportunidades anteriores a su entrada de las de su turno. Esta separación se
utiliza solo para clasificar CL, no para asignar C. Hay historias que no contienen
el motivo del avance o la identidad del anotador. Se deja el dato pendiente en
esos casos, incluso si el total del marcador es conocido. Se conservan como eventos
distintos las correcciones, los movimientos de corredor y los lanzamientos.
Referencia para la reconstrucción: reglas de anotación de sóftbol NCAA, 14.23–14.25,
https://ncaaorg.s3.amazonaws.com/championships/sports/softball/rules/PRWSB_RulesBook.pdf

La verificación fue de solo lectura. El cambio requiere exclusivamente Flutter.
