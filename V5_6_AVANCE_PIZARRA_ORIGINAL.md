# V5.6 — Pizarra original: avance de integración de lectura

- La pantalla `SwlAdvancedScoreboard` admite ahora `liveSnapshot` opcional; sin este parámetro conserva el modo local anterior.
- La vista original muestra marcador, entradas, contadores, corredores y nombres de equipos procedentes del partido consultado en el lobby.
- El lobby ofrece «VER MI PIZARRA ORIGINAL · SOLO LECTURA» para abrirla.
- Para impedir anotaciones falsas, todos los controles locales de la pizarra quedan bloqueados en este modo. Las anotaciones reales permanecen en el lobby.
- **Pendiente:** conectar cada control de la pizarra original a los RPC reales y a la suscripción Realtime; actualizar la vista mientras está abierta, traer alineaciones y estadísticas reales y validar con Flutter/GitHub Actions.
- **No es una APK lista para producción ni una pizarra de anotación integrada.**
