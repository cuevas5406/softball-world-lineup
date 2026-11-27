# SWL-378859 · Carreras limpias y sucias

LAB consultado en solo lectura. En la versión 28 el marcador es Los 300 4,
Los Jodones 1. El error defensivo de la versión 27 tiene bateador, primera
base y cero outs agregados. No tiene fila en swl_v56_pitching_events.
La definición instalada de swl_v57_defensive_error tampoco escribe esa
tabla ni llama al acumulador. Las jugadas 26 y 28 acreditan al #92 y
el cambio al #92 está registrado en la versión 25.

La vista anterior declaraba indeterminada toda la atribución si un
anotador no tenía pitcher. Flutter ahora reconcilia un error defensivo
estructurado solo cuando las referencias anterior y posterior de la
defensa coinciden. Considera las jugadas acreditadas, los relevos y el
pitcher activo en la alineación de la misma lectura versionada. Esta
reconstrucción es local y no escribe en LAB.

El error de la 27 deja un corredor no elegible para CL. El bateador
de la 28 sí suma CL: no había un tercer out teórico. Resultado para
Los Jodones: #91 0/0, #93 1/1, #92 3/2. Colectivo 4/3.
Un crédito parcial positivo se muestra como mínimo confirmado (≥).
Un valor indeterminado sin un mínimo positivo se muestra con raya.

El aviso de actualización se activaba con cualquier excepción de un ciclo
de lectura, incluso con una lectura válida anterior. Ahora se conserva
esa lectura y se informa si el problema se repite. La causa concreta del
aviso intermitente en el dispositivo no pudo confirmarse en LAB.

Android usa la orientación permitida por el usuario. El Box Score
ajusta el reparto de ancho y conserva la pestaña y el encuentro al
cambiar el tamaño. La verificación física de la rotación queda pendiente.
