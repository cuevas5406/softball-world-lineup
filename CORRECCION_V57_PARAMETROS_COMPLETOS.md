# Validación completa de parámetros SQL V5.7

Se valida cada campo `source`, `destination`, `first_to`, `second_to` y `third_to` antes del cast a integer. Solo se admiten números JSON enteros entre 0 y 3, o null cuando el destino sea opcional. Se rechazan decimales, exponentes, cadenas y números fuera de rango.

**Estado:** cambio estático, sin ejecución de migración ni pruebas Flutter. LAB y producción no modificados.
