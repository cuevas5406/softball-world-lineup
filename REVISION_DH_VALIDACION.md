# Revisión del bateador designado — V5.6

- La validación del guardado impide que el pitcher permanezca en la lista ofensiva cuando `pitcherBats` es falso.
- El DH debe ser un bateador del orden, no puede ocupar una posición defensiva y no puede ser el pitcher.
- El editor limita la selección ofensiva a 13 bateadores, en vez de 14.
- Se agregaron tres casos de prueba, sin ejecutar `flutter test` (SDK no disponible).
- No se ejecutó SQL ni se modificó Supabase LAB.
