# Preflight real Supabase LAB (solo lectura)
Proyecto LAB: wgeziptdoabyicufnrfk.
Consultas SQL de lectura ejecutadas: la RPC `swl_v56_special_play` **NO está instalada**; tampoco existe `swl_v57_batted_ball` (0 funciones de ese nombre). Las cuatro columnas especiales esperadas de `swl_live_games` sí existen. Se inspeccionaron las implementaciones de `swl_v53_substitute_batter`, `swl_v56_close_after_play` y `swl_v56_accumulate_pitching`: la sustitución incrementa versión e inserta evento; los otros dos auxiliares recargan el partido y verifican que la versión avance exactamente una unidad. 

La migración 18 continúa **sin instalar**. El siguiente paso técnico no es una APK: es desplegarla en LAB y probar las jugadas con autenticación de mánager. No se han ejecutado pruebas Flutter ni transacciones de jugadas.
