import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<AuthState>? _authChanges;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(swlFirebaseBackgroundHandler);
      _foreground = FirebaseMessaging.onMessage.listen(_messages.add);
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(_messages.add);
      _initialized = true;
      _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        registerDevice(token);
      });
      _authChanges = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        registerCurrentDevice();
      });
      await registerCurrentDevice();
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

  /// Registers only the signed-in user's own device in LAB. No FCM token is logged.
  Future<void> registerDevice(String token) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || token.isEmpty) return;
    try {
      await client.from('swl_push_devices').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'platform': defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fcm_token');
    } catch (error) {
      debugPrint('No se pudo registrar el dispositivo para notificaciones: $error');
    }
  }

  Future<void> registerCurrentDevice() async {
    if (!_initialized || Supabase.instance.client.auth.currentUser == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await registerDevice(token);
    } catch (error) {
      debugPrint('Token FCM no disponible: $error');
    }
  }

  Future<String?> deviceToken() async {
    if (!_initialized) return null;
    return FirebaseMessaging.instance.getToken();
  }
}
