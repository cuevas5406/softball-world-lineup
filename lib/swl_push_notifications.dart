import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// A push received while the app is backgrounded is handled by Android/FCM.
/// Never call Supabase or write private data from this background isolate.
@pragma('vm:entry-point')
Future<void> swlFirebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Firebase client initialization. Does not upload device tokens or send pushes.
/// A secure server-side device registry and sender must be deployed separately.
class SwlPushNotifications {
  SwlPushNotifications._();
  static final instance = SwlPushNotifications._();
  final StreamController<RemoteMessage> _messages =
      StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get messages => _messages.stream;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(swlFirebaseBackgroundHandler);
      _foreground = FirebaseMessaging.onMessage.listen(_messages.add);
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(_messages.add);
      _initialized = true;
    } catch (error) {
      debugPrint('FCM no disponible: $error');
    }
  }

  Future<void> requestPermission() async {
    if (!_initialized) return;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
    } catch (error) {
      debugPrint('Permiso de notificaciones no disponible: $error');
    }
  }

  Future<RemoteMessage?> initialMessage() async {
    if (!_initialized) return null;
    return FirebaseMessaging.instance.getInitialMessage();
  }

  Future<String?> deviceToken() async {
    if (!_initialized) return null;
    return FirebaseMessaging.instance.getToken();
  }
}
