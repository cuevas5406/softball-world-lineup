# Notificaciones V5.7 — etapa 2

- Cliente: registra el token FCM del usuario autenticado en Supabase LAB y lo actualiza al rotar.
- Backend LAB: tablas `swl_push_devices` y `swl_push_outbox` con RLS, trigger de retos.
- **Pendiente:** servicio de entrega FCM HTTP v1 y credenciales de servidor configuradas como secretos. La cola no envía mensajes por sí sola.
- No publicar credenciales de cuenta de servicio ni colocarlas en el proyecto Flutter.
- La APK requiere compilarse en GitHub Actions; no se ha compilado en este entorno.
