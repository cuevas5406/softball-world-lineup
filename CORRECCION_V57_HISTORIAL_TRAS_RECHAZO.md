# Reconciliación del historial después de un rechazo de RPC

En `lib/swl_live_lobby.dart`, la rama de errores de servidor no reintentables (incluidos conflictos de versión) ahora actualiza marcador, historial y estadísticas, en lugar de actualizar solo el marcador. Esto reduce la posibilidad de mostrar una jugada reciente en la pizarra sin verla en el historial después de un rechazo concurrente.

No modifica SQL, no reintenta jugadas y no da por resuelta la sincronización de dos teléfonos sin pruebas reales.
