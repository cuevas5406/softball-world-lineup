# V5.7 — casos de regresión para jonrones

Se agregaron tres pruebas Dart para:
1. Jonrón solitario: 1 carrera y bases vacías.
2. Jonrón con corredores en primera y tercera: 3 carreras y bases vacías.
3. Jonrón con corredor retirado: rechazo de la jugada.

Se agregó un test Python que verifica la presencia de los escenarios y de las reglas SQL correspondientes. Los ocho tests Python de contrato pasaron. **Los tests Dart NO fueron ejecutados** por falta del SDK en este entorno.

Revisión de `swl_v56_close_after_play` y `swl_v56_accumulate_pitching` contra funciones instaladas en LAB: el primero vuelve a consultar el estado actualizado del juego y el segundo valida la versión nueva. Esos helpers no necesitan cambio por el uso de `g` anterior. Las RPC V5.7 siguen sin instalarse; producción intacta.
