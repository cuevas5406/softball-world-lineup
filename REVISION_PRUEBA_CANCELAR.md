# Regresión: cancelar no debe modificar la alineación

La prueba del editor todavía esperaba que los cambios de orden y pitcher afectaran al borrador original antes de guardar. Esa expectativa era incompatible con la corrección que introdujo una copia temporal en el diálogo.

Se actualizó la prueba para verificar que el borrador original permanezca intacto mientras se edita y después de pulsar CANCELAR. Se conserva la comprobación de que una defensa incompleta no puede guardarse.

No se modificó código de producción ni Supabase LAB. Pruebas Flutter y compilación APK pendientes.
