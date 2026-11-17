# Estadísticas individuales preliminares — LAB
RPC swl_v53_batting_stats(game_id): agrega eventos con batter_id.
Calcula VB, hits, sencillos, dobles, triples, HR, BB, K y apariciones completadas.
Se ejecuta en servidor sobre todos los eventos del partido; no solo los últimos 20.
Verifica autenticación y pertenencia a mánagers del partido.
Se revocó EXECUTE a authenticated de swl_v53_record_play (ruta manual).
Flutter retiró RUN/ERROR de los botones y muestra estadísticas consultables.
Limitaciones: no se calculan impulsadas, anotadas, carreras limpias ni estadísticas
de lanzador; eventos antiguos sin batter_id quedan fuera. No es box score oficial.
No se ejecutaron pruebas Flutter ni pruebas con mánagers autenticados.
