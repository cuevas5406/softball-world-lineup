# Corrección: cancelar el editor no altera el borrador

El diálogo trabaja con una copia independiente de orden ofensivo, defensa, pitcherBats y designatedId. Solo el botón GUARDAR ALINEACIÓN transfiere esos valores al borrador original; CANCELAR y cerrar el diálogo descartan la copia. Esto evita efectos secundarios durante la edición. No modifica el contrato de la RPC ni Supabase LAB.

**Verificación:** inspección estática y comprobación de integridad ZIP. `flutter test` y compilación APK no ejecutados; requieren SDK Flutter.
