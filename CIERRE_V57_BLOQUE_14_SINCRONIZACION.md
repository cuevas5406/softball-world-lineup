# V5.7 — Bloque 14: sincronización de equipos autorizados

## Hallazgo
El Hub mantenía `widget.authorizedTeams` recibido al entrar, mientras Mi Equipo consultaba permisos actualizados tras crear un equipo. El Hub rechazaba equipos nuevos y seguía mostrando permisos revocados en Agenda, Pizarra y lobby hasta reiniciar sesión.

## Corrección
- Estado local `_authorizedTeams` en el Hub, inicializado desde la sesión.
- Callback `onAuthorizedTeamsChanged` desde Mi Equipo tras consulta válida al servidor.
- Conservación de equipo activo si sigue autorizado; eliminación si fue revocado; selección automática si solo queda uno.
- Propagación de la lista actualizada a Agenda, Pizarra, Mi Equipo y lobby.
- Tras editar ajustes del equipo, se recargan permisos desde el servidor.

## Limitaciones
No se ejecutó SQL, no se modificó Supabase y no se compiló APK. Las pruebas Python comprueban contratos estáticos, no ejecución Dart ni comportamiento real de dispositivos.
