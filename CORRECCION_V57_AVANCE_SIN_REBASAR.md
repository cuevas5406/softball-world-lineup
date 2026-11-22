# V5.7 — Avances sin rebasar corredores

El motor local permitía que el corredor de primera anotara mientras el corredor de segunda permanecía en segunda. Ahora compara los destinos desde tercera hacia primera, tratando home como cuarta base.

Se agregaron dos pruebas Dart y una prueba estática Python. El RPC RUNNER_MOVE sigue operando sobre movimientos individuales, por lo que no se afirma que soporte múltiples avances simultáneos. No se ejecutó SQL ni se modificó Supabase. No se pudieron ejecutar pruebas Dart por ausencia de SDK.
