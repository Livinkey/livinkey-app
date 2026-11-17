// lib/services/deep_link_service.dart
//
// Opens the right app screen when a person taps a Livinkey link in WhatsApp / SMS / e-mail.
// The https smart link (https://api.livinkey.com/l/<code>) lands on a web page that hands over to
//   livinkey://open?t=<screen>
// A link never signs anybody in: a signed-in person goes straight to the screen, a signed-out
// person logs in as usual and is then taken to the screen.
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';
import 'api_service.dart';
import 'push_notification_service.dart' show navigatorKey;

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService _instance = DeepLinkService._();
  factory DeepLinkService() => _instance;

  StreamSubscription<Uri>? _sub;
  String? _pendingRoute;

  /// Screen name used in links -> named route registered in main.dart.
  static String? routeFor(String? target) {
    switch ((target ?? 'home').toLowerCase()) {
      case 'payments':
      case 'pay':
        return '/tenant-payments';
      case 'maintenance':
        return '/tenant-maintenance';
      case 'documents':
        return '/tenant-documents';
      case 'home':
      case 'notifications':
      case 'agreements':
        return '/tenant-home';
      default:
        return null;
    }
  }

  Future<void> init() async {
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) {
        // cold start: let AuthGuard finish choosing the first screen
        Future.delayed(const Duration(milliseconds: 1500), () => _handle(initial));
      }
      _sub ??= links.uriLinkStream.listen(_handle, onError: (_) {});
    } catch (_) {
      // deep links are a convenience – never break app start-up
    }
  }

  Future<void> _handle(Uri uri) async {
    try {
      if (uri.scheme != 'livinkey') return;
      final route = routeFor(uri.queryParameters['t']);
      if (route == null) return;

      final api = ApiService();
      await api.init();
      if (!await api.isLoggedIn()) {
        _pendingRoute = route; // opened after the next successful login
        return;
      }
      await _open(route);
    } catch (_) {}
  }

  /// Call right after a successful login.
  Future<void> consumePending() async {
    final route = _pendingRoute;
    _pendingRoute = null;
    if (route == null) return;
    await Future.delayed(const Duration(milliseconds: 900));
    await _open(route);
  }

  Future<void> _open(String route) async {
    // Guests have no tenant screens; opening the app already shows their home.
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getString(kStorageRole) ?? 'tenant') == 'guest') return;
    } catch (_) {}

    for (var i = 0; i < 10; i++) {
      final nav = navigatorKey.currentState;
      if (nav != null) {
        if (route != '/tenant-home') nav.pushNamed(route);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }
}
