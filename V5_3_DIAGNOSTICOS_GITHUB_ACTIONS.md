# V5.3 — Diagnosticos de compilacion

El workflow `Compilar APK Android - Softball World Lineup` conserva la compilacion APK con GitHub Actions.

- Al ejecutar el workflow se registran el analisis Dart, el analisis Flutter, las pruebas y la compilacion en `diagnosticos/`.
- Se publica el artefacto `SWL-V53-Diagnosticos` incluso cuando falla un paso, para que el usuario pueda compartir el error exacto.
- La APK, cuando la compilacion termina correctamente, sigue en `Softball-World-Lineup-Instalador`.
- `set -o pipefail` evita que `tee` oculte un error de analisis, pruebas o compilacion.
- Un rechazo explicito del servidor al sustituir ya no se trata como perdida de conexion; una respuesta ausente sigue requiriendo revision manual.

## Como obtener los registros

GitHub > Actions > Compilar APK Android - Softball World Lineup > Run workflow. Al terminar, abrir el run y descargar `SWL-V53-Diagnosticos` en Artifacts. Si el run fue exitoso, descargar tambien `Softball-World-Lineup-Instalador`.

No se ha ejecutado GitHub Actions desde este entorno. No se ha compilado ni probado la APK. No se ha modificado Supabase.
