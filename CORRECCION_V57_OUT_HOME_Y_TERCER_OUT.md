# V5.7 — Regresiones de out en home y tercer out

Se incorporaron pruebas Dart para out en home sin carrera, tercer out en home con cambio automático de media entrada, carrera no confirmada en jugada de tiempo y carrera confirmada de corredor adelantado. Se eliminó una rama inalcanzable del elevado de sacrificio (dos outs), ya rechazada por su precondición.

El cálculo de carreras de `hit` no fue alterado: se añadió cobertura de regresión para preservar el contrato actual y detectar cambios accidentales. La confirmación del tercer out de tiempo sigue siendo explícita cuando corresponde.

No se ejecutó Dart ni SQL, ni se modificó Supabase. Pruebas Python verifican presencia y consistencia estática de estos casos.
