# V5.6 — Orden al bate separado de la defensa

- `selected` conserva únicamente los candidatos del orden ofensivo.
- `positions` conserva los defensores, aunque no estén en `selected`.
- Al reabrir una alineación, se recupera el orden ofensivo de `lineup` sin añadir defensores extra.
- Se pueden asignar posiciones defensivas a peloteros que no batean.
- El cambio «El pitcher batea» ajusta el orden ofensivo; el pitcher sin turno no se incorpora al orden.
- Se añadió una prueba de contrato para pitcher defensivo y bateador designado.

**Pendiente:** ejecutar `flutter test`, revisión visual del editor en Android y pruebas de dos teléfonos. No se ha compilado APK ni modificado Supabase LAB.
