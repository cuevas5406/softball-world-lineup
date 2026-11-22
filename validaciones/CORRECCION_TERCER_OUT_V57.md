# Corrección del tercer out — V5.7 (sin desplegar)

Archivo modificado: `propuestas_lab/13_v57_batazos_y_defensa.sql`.

**Antes:** para outs no forzados solo sumaba corredores de bases posteriores a la base de origen del corredor eliminado; esto podía descartar una carrera legítima.

**Ahora:** conserva las carreras calculadas cuando el tercer out no es forzado y el anotador confirmó expresamente `count_runs_on_third_out=true`; anula carreras para out forzado o sin confirmación. No deduce la cronología por el orden de bases. **Limitación:** la confirmación del anotador sigue siendo necesaria; deben verificarse jugadas de apelación, out del bateador antes de primera y la interfaz de confirmación antes de usar en vivo.

Esta corrección NO se ha ejecutado en Supabase. El archivo completo contiene otras funciones que reemplazan contratos existentes; NO instalarlo directamente. Faltan dependencias y pruebas.
