# Revisión V5.6 — intercambio de posiciones defensivas

Se corrigió el editor para permitir tocar una posición defensiva ya ocupada y efectuar un intercambio entre ambos jugadores. Antes, los botones para posiciones ocupadas distintas de P estaban deshabilitados y `SwlLineupDraft.assign` rechazaba el cambio.

El intercambio no modifica `selected` (orden al bate) y conserva los controles de validación de pitcher, DH, cantidad de defensores y posiciones únicas.

Se agregó una prueba de regresión para el intercambio 1B/2B.

**Verificación:** revisión estática del código y prueba agregada; no se ejecutó Flutter test ni se compiló APK. No se ejecutó SQL ni se modificó Supabase LAB.
