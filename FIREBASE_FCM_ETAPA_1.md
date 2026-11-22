# Softball World Lineup V5.7 — Firebase Cloud Messaging (etapa 1)

## Integrado
- `android/app/google-services.json` coincide con `applicationId`.
- Plugin Google Services en Gradle, `firebase_core` y `firebase_messaging`.
- Permiso Android 13+ `POST_NOTIFICATIONS`.
- Inicialización Firebase y recepción de mensajes FCM en primer plano, en segundo plano y al abrir la aplicación desde una notificación.
- Navegación a Agenda para mensajes con `data.type=challenge` o `data.screen=agenda`.

## Pendiente para notificaciones reales de retos
1. Registrar, rotar y revocar tokens FCM por usuario/dispositivo en Supabase, con RLS estricta y sin exponer tokens de otros usuarios.
2. Implementar emisor FCM HTTP v1 en un servicio de confianza (Edge Function) con credenciales de cuenta de servicio **solo del servidor**, nunca en Flutter ni en GitHub.
3. Vincular eventos de reto (enviar, aceptar, rechazar, cancelar) a una cola segura e idempotente de notificaciones.
4. Validar entrega en dos teléfonos, aplicación abierta, en segundo plano y cerrada, y limpieza al cerrar sesión.

## Compilación
`pubspec.yaml` incorpora dependencias Firebase. El `pubspec.lock` anterior no las incluye; el workflow usa `flutter pub get` sin `--enforce-lockfile` en esta etapa. Después de una compilación exitosa, regenerar y confirmar `pubspec.lock` para reproducibilidad.

## Seguridad
No se ha ejecutado SQL para notificaciones ni se ha configurado ningún emisor. No se ha tocado producción. El archivo `google-services.json` no contiene una clave privada de servicio, pero no se deben subir secretos de servidor al repositorio.

## Estado de pruebas
No hay Flutter SDK disponible en este entorno: compilación y pruebas Dart/Flutter pendientes de GitHub Actions. Esta entrega es la **etapa 1 de integración del cliente**, no una activación completa de notificaciones push.
