# V5.3 — Consulta de rosters reales

Se agregó `lib/swl_roster_repository.dart` para consultar fichajes activos (`rosters.removed_at IS NULL`) y recuperar los UUID reales de `players` sin usar nombres como identidad. El lobby ahora permite visualizar roster local y visitante, con códigos universales, número, posición y condición de refuerzo. Es **solo lectura**: todavía no guarda alineaciones ni atribuye estadísticas. No se cambió ninguna tabla ni dato de Supabase LAB/producción.

Pruebas unitarias nuevas: identidad correcta y rechazo de cruce de jugador equivocado. No ejecutadas: Flutter SDK no disponible en el entorno. Se requiere probar lectura con usuario autenticado y las políticas RLS reales antes de declarar la función lista para uso.
