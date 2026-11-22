# V5.7 — Corrección de compilación SQL

La función `swl_v56_special_play` usaba `runner_text` en la rama `RUNNER_REPLACE` sin declararla en el bloque `DECLARE`. PostgreSQL rechazaría la creación de la función con un error de variable inexistente.

Se agregó `runner_text text;` al bloque `DECLARE`, sin cambiar la semántica de sustitución.

**Validación realizada:** inspección estática de la declaración y los usos de la variable; integridad del ZIP. **Pendiente:** compilación de la migración en LAB, ejecución de pruebas SQL/Flutter y APK. No se ejecutó SQL.
