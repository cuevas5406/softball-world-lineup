# Revisión de preinstalación LAB

La función propuesta ahora rechaza bases_state nulo, sin las tres claves first/second/third, con claves adicionales o con valores no booleanos. Evita interpretar estados dañados como bases vacías y registrar carreras/outs incorrectos.

Consulta de LAB: confirmadas columnas de swl_live_games y firmas de funciones auxiliares. No se ha ejecutado la migración ni pruebas de jugadas en la base de datos. No ejecutar en producción.
