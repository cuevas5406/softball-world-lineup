# Estabilización V5.7

Base d1d2cf2. La exportación iniciada desde el Box Score del mánager usa las
mismas tablas formateadas en pantalla. La lectura pública para fanáticos
conserva la vía oficial ya existente y una alternativa de marcador según los
datos legibles. Los documentos de muestra se renderizaron con datos sintéticos.

## Pendiente de autorización y verificación

- Las dos propuestas SQL se prepararon para LAB. Instalar y verificar en la
  misma transacción, con los datos de pruebas bajo un savepoint y ROLLBACK.
  Comprobar permisos, función previa y SHA-256 antes de cualquier ejecución.
- La prueba SQL cubre tres modalidades, finalización unilateral en consulta,
  dos votos para continuar, rechazo de juego y voto duplicado durante consulta,
  destinos de out en las cuatro bases y la transición al tercer out.
- El formulario de error admite un out de corredor por jugada. La RPC anterior
  informa que la opción requiere actualización de LAB. Se conserva el historial.
  La migración acredita al pitcher desde la anotación y deja intactas las
  jugadas históricas. No añade reversión de errores ni reconstrucción retroactiva.
- La defensa exporta posiciones registradas y errores colectivos. La fuente
  vigente no atribuye todos los errores individuales, putouts o asistencias.
- La vista pública sigue dependiendo de los permisos y campos de su RPC. Sus
  exportaciones no comparten todavía el agregado completo del mánager.

## Pruebas físicas para la próxima APK

1. Teléfono y tablet en ambas orientaciones, cambiar de pestaña y plegar la
   pizarra en horizontal. Verificar dorsales, columnas y encabezados.
2. Compartir PNG de ambos alcances y marcador solo, y PDF de ambos alcances.
   Abrirlos en WhatsApp, revisar logos reales, numeración, símbolos pendientes,
   nombres largos y tablas de partidos con extras y varias sustituciones.
3. Confirmar alineación con receptor faltante o doble posición y corregir el
   borrador. Verificar pitcher, DH y bateadores extra.
4. Con SQL autorizado y probado, crear encuentros nuevos para AUTO, CONSULT
   y DISABLED. Comprobar bloqueo sincronizado, rechazo de voto repetido,
   continuación por dos votos y cierre si un mánager decide finalizar.
5. Con SQL autorizado y probado, anotar errores con outs en cada base, incluido
   home, con y sin tercer out. Contrastar historial y Box Score en ambos equipos.
6. Revisar fanático sin permiso de mánager, resultados oficiales, cancelados,
   favoritos, y regresión física de retos, anotación, DP y deshacer.

## Siguientes fases aprobadas

- Estadísticas acumuladas oficiales por pelotero, equipo, período y competencia,
  un UUID/SWL, historial de equipos y promedios sobre totales sin duplicados.
- Rankings y rivalidades por período y geografía, mínimos de participación,
  líderes de bateo, pitcheo y defensa e historial de enfrentamientos.
- Competencias en Agenda con torneos y copas, organizadores, invitaciones,
  calendarios, formatos, desempates, eliminatorias y reconocimientos.
- Comunidad con seguimiento, publicaciones, cromitos, comentarios y reacciones.
- Backoffice independiente con permisos y auditoría, campañas, contratos,
  publicidad diferenciada y métricas con gestión remota.
