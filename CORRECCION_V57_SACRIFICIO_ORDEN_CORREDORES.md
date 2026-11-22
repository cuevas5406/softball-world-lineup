# V5.7 — Orden de corredores en fly de sacrificio

El motor Flutter comprobaba bases duplicadas, pero no impedía que un corredor retrasado adelantara a otro que seguía en base. El RPC SQL ya rechazaba esas jugadas. Se agregó a `SwlPlayState.sacrificeFly` la comprobación descendente de tercera a primera, usando home como destino 4 para comparar el orden.

Se añadieron dos pruebas Dart de regresión (no ejecutadas en este entorno) y una prueba estática Python. No se ejecutó SQL ni se modificó Supabase.
