# Consistencia de pruebas del bateador designado

Se ajustó una prueba que esperaba el error del DH cuando el draft aún tenía un pitcher indebidamente incluido en la lista ofensiva y defensa incompleta. Ahora el escenario mantiene al pitcher fuera del orden, completa la defensa y comprueba después el error del DH. La reasignación defensiva de un DH también se prueba explícitamente.

Se ejecutaron las 7 pruebas Python de contratos SQL del proyecto, todas satisfactorias. Las pruebas Dart/Flutter no se han ejecutado porque el SDK no está disponible. No se modificó Supabase LAB.
