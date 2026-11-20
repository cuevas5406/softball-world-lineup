# Corrección de pruebas del DH y del intercambio defensivo

Se detectaron dos expectativas erróneas en las pruebas existentes:

1. La prueba de pitcher sin turno ofensivo mantenía al pitcher en la lista seleccionada y elegía como DH a un jugador que también defendía. Se corrigió: el pitcher queda fuera del orden y el DH es b9, que no ocupa defensa.
2. La prueba de intercambio esperaba que b1 conservara 1B después de asignársela a b3. Se corrigió la expectativa: b3 ocupa 1B y b1 queda sin posición.

No se alteró el código de producción ni Supabase LAB. No se ejecutó `flutter test` porque Flutter SDK no está instalado. Las pruebas requieren ejecución en GitHub Actions o entorno Flutter.
