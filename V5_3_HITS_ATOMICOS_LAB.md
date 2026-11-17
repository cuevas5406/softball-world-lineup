# V5.3 — Hits transaccionales en Supabase LAB

Función instalada y verificada en LAB: `public.swl_v53_apply_hit(uuid,bigint,integer,integer,integer,integer)`.

Parámetros RPC: `p_game_id`, `p_expected_version`, `p_batter_base` (1=sencillo, 2=doble, 3=triple, 4=jonrón), `p_first_to`, `p_second_to`, `p_third_to` (destino 0=anota, 1/2/3=base; `null` solo si no había corredor en esa base).

La operación valida autenticación, pertenencia al mánager del partido, permiso activo sobre su equipo, versión optimista y partido no cerrado. Bloquea la fila con `FOR UPDATE`. Rechaza corredores omitidos, bases duplicadas, destinos inválidos y avances forzados incumplidos. En una transacción actualiza bases, bolas/strikes, hits, carreras, carreras por entrada, versión e inserta un evento.

Se verificó que `anon` no tiene permiso EXECUTE y `authenticated` sí. Se verificó que una invocación sin sesión devuelve `AUTH_REQUIRED` (SQL sin modificar partidos). No se ejecutó una jugada autenticada real ni se probó con dos dispositivos. Producción no se modificó.

En Flutter se añadió un formulario para seleccionar hit y destinos de todos los corredores. La RPC se invoca solo después de confirmación y se conserva la reconciliación de resultados inciertos por versión y evento. El botón manual de HIT fue sustituido por el flujo completo; RUN y ERROR siguen siendo controles manuales de LAB, no anotación oficial.

**Pendientes:** pruebas autenticadas, compilación Flutter, pruebas en dos dispositivos, estadísticas individuales y alineaciones persistentes. No publicar como versión final.
