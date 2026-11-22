# V5.7 — esperar la lectura de marcador en curso

El sondeo de marcador se ejecuta cada cuatro segundos. Antes, si una jugada era confirmada mientras una consulta anterior estaba en vuelo, `_refreshLiveScore()` retornaba sin consultar el estado nuevo. Ahora las llamadas concurrentes esperan la consulta activa y solicitan una lectura posterior, agrupando las solicitudes pendientes.

No se ejecutaron pruebas Dart, APK ni SQL. No se modificó Supabase.
