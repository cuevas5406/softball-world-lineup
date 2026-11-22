# V5.7 — UUID de último out

Se normaliza con btrim el identificador elegido del historial antes de validar su formato y convertirlo a UUID. Antes se aplicaba btrim solo al convertir, por lo que un UUID rodeado de espacios se rechazaba antes de llegar a esa conversión.

Validación: revisión estática y verificación de contenido del ZIP. No se ejecutaron migraciones, pruebas Flutter ni compilación APK.
