import 'dart:async';
import 'app_events.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

/// Global navigator key for navigation from notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  // Lazy getter – only accessed AFTER Firebase.initializeApp()
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final ApiService _api = ApiService();
  bool _isInitialized = false;
  bool _isFirebaseInitialized = false;
  String? _fcmToken;

  // Track whether we already handled an initial (terminated) message
  bool _initialMessageHandled = false;

  /// Initialize Firebase only (called from main())
  Future<void> initializeFirebaseOnly() async {
    if (_isFirebaseInitialized) return;

    try {
      await Firebase.initializeApp();
      _isFirebaseInitialized = true;
    } catch (e) {
      // Don't block app startup
      _isFirebaseInitialized = true;
    }
  }

  DateTime? _lastRegisteredAt;
  bool _registering = false;

  /// Full push-notification init – call AFTER login so auth is valid.
  /// Safe to call many times: listeners are set up once, but the device is
  /// (re-)registered with the server on EVERY call, so a failed first attempt
  /// (no network, forced password change, server hiccup) is never lost.
  Future<void> initialize() async {
    try {
      if (!_isFirebaseInitialized) {
        await Firebase.initializeApp();
        _isFirebaseInitialized = true;
      }
    } catch (_) {}

    if (!_isInitialized && !kIsWeb) {
      try { await _requestPermissions(); } catch (_) {}
      try { await _initializeLocalNotifications(); } catch (_) {}
      try { await _setupMessageHandlers(); } catch (_) {}
      _isInitialized = true;
    }

    await registerDevice(force: true);
  }

  /// Tells the server "this phone has the app, and it was just opened".
  /// This is what the admin panel uses for Installed / Last opened.
  /// [force] ignores the 10-minute throttle (used after login/password change).
  Future<void> registerDevice({bool force = false}) async {
    if (kIsWeb || _registering) return;
    final now = DateTime.now();
    if (!force &&
        _lastRegisteredAt != null &&
        now.difference(_lastRegisteredAt!) < const Duration(minutes: 10)) {
      return;
    }
    _registering = true;
    try {
      String? token;
      for (var i = 0; i < 3 && (token == null || token.isEmpty); i++) {
        try {
          token = await _fcm.getToken();
        } catch (_) {}
        if (token == null || token.isEmpty) {
          await Future<void>.delayed(Duration(seconds: 2 * (i + 1)));
        }
      }
      if (token == null || token.isEmpty) return;
      _fcmToken = token;
      final ok = await _storeFCMToken(token);
      if (ok) _lastRegisteredAt = DateTime.now();
    } finally {
      _registering = false;
    }
  }

  Future<void> _requestPermissions() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      carPlay: true,
      criticalAlert: true,
      provisional: false,
      sound: true,
    );

    if (Platform.isIOS) {
      // Keep badge/sound via system, but disable system alert so we don't
      // get a duplicate with the local notification we show ourselves.
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // Create the Android notification channel so FCM system notifications
    // and local notifications both appear in the device notification drawer.
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'livinkey_channel',
        'Livinkey Notifications',
        description: 'Notifications from Livinkey',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Returns true only when the SERVER confirmed the registration.
  Future<bool> _storeFCMToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString('fcm_token', token);
      String? version;
      try {
        final info = await PackageInfo.fromPlatform();
        version = '${info.version}+${info.buildNumber}';
      } catch (_) {}
      final response = await _api.updateFCMToken(token, appVersion: version);
      if (response['success'] == true) {
        await prefs.remove('pending_fcm_token');
        return true;
      }
    } catch (_) {}
    // Not confirmed (offline, server error, not logged in yet): keep it so
    // it is retried on the next launch / resume / login.
    await prefs.setString('pending_fcm_token', token);
    return false;
  }

  Future<void> retryPendingToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getString('pending_fcm_token');
      if (pending != null && pending.isNotEmpty) {
        await registerDevice(force: true);
      }
    } catch (_) {}
  }

  Future<void> _setupMessageHandlers() async {
    // 1. Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      AppEvents.requestRefresh();
      _handleForegroundMessage(message);
    });

    // 2. Background messages (must be top-level)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. App opened from terminated state
    if (!_initialMessageHandled) {
      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _initialMessageHandled = true;
        // Delay a little so the navigator is ready
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleNotificationData(initialMessage.data);
        });
      }
    }

    // 4. App opened from background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationData(message.data);
    });

    // 5. Token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _fcmToken = newToken;
      _storeFCMToken(newToken);
    });
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final kind = message.data['type']?.toString();
    if (kind == 'probe' || kind == 'ping') return; // silent server check
    _showLocalNotification(message);

    // Refresh the in-app notification list so the badge updates immediately
    // Detect role from SharedPreferences so guest notifications also update.
    try {
      SharedPreferences.getInstance().then((prefs) {
        final role = prefs.getString('lk_role') ?? 'tenant';
        final isTenant = role != 'guest';
        NotificationService().refresh(isTenant: isTenant);
      });
    } catch (_) {}
  }

  /// Stable id so the same FCM message updates instead of stacking duplicates.
  int _notificationIdFor(RemoteMessage message) {
    final raw = message.messageId ??
        message.data['id']?.toString() ??
        message.data['notification_id']?.toString() ??
        '${message.notification?.title ?? ''}|${message.notification?.body ?? ''}|${message.sentTime?.millisecondsSinceEpoch ?? ''}';
    return raw.hashCode & 0x7fffffff; // positive 31-bit
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final String title = message.notification?.title ??
        message.data['title']?.toString() ??
        'Livinkey';
    final String body = message.notification?.body ??
        message.data['body']?.toString() ??
        'You have a new notification';

    // Encode the whole data map as payload so we can navigate correctly
    final String payload = _encodePayload(message.data);

    const androidDetails = AndroidNotificationDetails(
      'livinkey_channel',
      'Livinkey Notifications',
      channelDescription: 'Notifications from Livinkey',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_stat_notification',
      color: Color(0xFF92C24A),
      colorized: false,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFF92C24A),
      ledOnMs: 1000,
      ledOffMs: 500,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      _notificationIdFor(message),
      title,
      body,
      details,
      payload: payload,
    );

    await _updateAppBadge();
  }

  String _encodePayload(Map<String, dynamic> data) {
    // Simple key=value&key2=value2 encoding
    return data.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}')
        .join('&');
  }

  Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return {};
    final map = <String, dynamic>{};
    for (final part in payload.split('&')) {
      final idx = part.indexOf('=');
      if (idx > 0) {
        final key = part.substring(0, idx);
        final value = Uri.decodeComponent(part.substring(idx + 1));
        map[key] = value;
      }
    }
    return map;
  }

  void _handleNotificationTap(NotificationResponse response) {
    final data = _decodePayload(response.payload);
    _handleNotificationData(data);
  }

  /// Navigate to the correct screen based on notification type
  void _handleNotificationData(Map<String, dynamic> data) {
    final String type = (data['type'] ?? data['action'] ?? '').toString().toLowerCase();

    // Wait until navigator is ready
    Future<void> tryNavigate() async {
      final nav = navigatorKey.currentState;
      if (nav == null) {
        // Retry a few times
        Future.delayed(const Duration(milliseconds: 300), tryNavigate);
        return;
      }

      // Guests have no tenant screens: opening the app already lands them on
      // their home, where new notifications are listed.
      try {
        final prefs = await SharedPreferences.getInstance();
        if ((prefs.getString('lk_role') ?? 'tenant') == 'guest') return;
      } catch (_) {}

      switch (type) {
        case 'bill_created':
        case 'bill_paid':
        case 'bill_partially_paid':
        case 'bill_fine_applied':
        case 'payment_reminder':
        case 'payment_proof_verified':
        case 'payment_proof_rejected':
        case 'payment':
          nav.pushNamed('/tenant-payments');
          break;

        case 'maintenance_created':
        case 'maintenance_started':
        case 'maintenance_completed':
        case 'maintenance_reminder':
        case 'maintenance':
          nav.pushNamed('/tenant-maintenance');
          break;

        case 'document_reminder':
        case 'document_approved':
        case 'document_rejected':
        case 'efrro_expiry':
        case 'document':
          nav.pushNamed('/tenant-documents');
          break;

        default:
          // Fallback – open tenant home
          nav.pushNamed('/tenant-home');
          break;
      }
    }

    tryNavigate();
  }

  Future<void> _updateAppBadge() async {
    try {
      if (Platform.isIOS) return;

      bool isSupported = false;
      try {
        isSupported = await AppBadgePlus.isSupported();
      } catch (e) {
        return;
      }

      if (!isSupported) return;

      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('lk_role') ?? 'tenant';
      final isTenant = role != 'guest';

      final count = isTenant
          ? await _api.getUnreadTenantCount()
          : await _api.getUnreadGuestCount();
      final unreadCount = count['unreadCount'] ?? count['unread_count'] ?? 0;
      await AppBadgePlus.updateBadge(unreadCount is int ? unreadCount : int.tryParse(unreadCount.toString()) ?? 0);
    } catch (e) {
      // ignore
    }
  }

  Future<String?> getToken() async {
    if (_fcmToken != null) return _fcmToken;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fcm_token');
  }

  Future<void> removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _fcmToken ?? prefs.getString('fcm_token');
    // Tell the server this person logged out on this phone (the app itself
    // stays "installed" in the admin panel).
    await _api.removeFCMToken(token: token);
    await prefs.remove('fcm_token');
    await prefs.remove('pending_fcm_token');
    _fcmToken = null;
    _lastRegisteredAt = null;
  }

  /// Call this when the app returns to the foreground
  Future<void> onAppResumed({bool isTenant = true}) async {
    try {
      // "Last opened" heartbeat + heals any registration that failed earlier.
      unawaited(registerDevice());
      await NotificationService().refresh(isTenant: isTenant);
      await _updateAppBadge();
    } catch (_) {}
  }
}

/// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  // When the FCM payload includes a `notification` block, Android/iOS already
  // display a system notification. Showing another local one causes duplicates.
  // Only create a local notification for data-only messages.
  // Still ensure the channel exists so system notifications appear in the drawer.
  final localNotifications = FlutterLocalNotificationsPlugin();

  // Must init plugin in background isolate before show()
  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  await localNotifications.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );

  // Ensure channel exists (critical for device notification drawer on Android 8+)
  const channel = AndroidNotificationChannel(
    'livinkey_channel',
    'Livinkey Notifications',
    description: 'Notifications from Livinkey',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );
  await localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  if (message.notification != null) {
    return;
  }
  final silentKind = message.data['type']?.toString();
  if (silentKind == 'probe' || silentKind == 'ping') return;

  const androidDetails = AndroidNotificationDetails(
    'livinkey_channel',
    'Livinkey Notifications',
    channelDescription: 'Notifications from Livinkey',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@drawable/ic_stat_notification',
    color: Color(0xFF92C24A),
  );

  const details = NotificationDetails(android: androidDetails);

  final title =
      message.data['title']?.toString() ?? 'Livinkey';
  final body =
      message.data['body']?.toString() ?? 'You have a new notification';

  final rawId = message.messageId ??
      message.data['id']?.toString() ??
      message.data['notification_id']?.toString() ??
      '$title|$body';
  final id = rawId.hashCode & 0x7fffffff;

  await localNotifications.show(
    id,
    title,
    body,
    details,
    payload: message.data.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}')
        .join('&'),
  );
}