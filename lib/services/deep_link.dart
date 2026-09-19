import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/auth/reset_link_expired_screen.dart';
import '../screens/auth/reset_password_screen.dart';
import 'fcm.dart' show rootNavKey;

/// ⭐ v63: cunnect:// deep links — currently: password reset from email.
///
/// cunnect://reset/<uidb64>/<token>  ->  in-app ResetPasswordScreen.
/// Works on cold start (link launched the app) AND while running
/// (link arrives via onNewIntent -> MethodChannel callback).
class DeepLinks {
  DeepLinks._();

  static const _channel = MethodChannel('cunnect/deeplink');
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    // Links that arrive while the app is running.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        _handle('${call.arguments}');
      }
    });
    // Link that launched the app (cold start).
    _channel.invokeMethod<String>('getInitialLink').then((link) {
      if (link != null && link.isNotEmpty) _handle(link);
    }).catchError((_) {});
  }

  static void _handle(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'cunnect') return;
    if (uri.host != 'reset') return;
    final seg = uri.pathSegments;
    // cunnect://reset/<uidb64>/<token> -> in-app reset screen.
    if (seg.length >= 2) {
      // ⭐ v66: expired/used links also open the APP (the server bounces
      // them here instead of leaving the user on a website page).
      if (seg[0] == 'expired') {
        _push(const ResetLinkExpiredScreen(), attempts: 0);
      } else {
        _openReset(seg[0], seg[1], attempts: 0);
      }
      return;
    }
    // cunnect://reset?status=expired (query form) -> expired screen.
    if (uri.queryParameters['status'] == 'expired' ||
        uri.queryParameters['error'] == 'expired') {
      _push(const ResetLinkExpiredScreen(), attempts: 0);
    }
  }

  /// Generic push with the cold-start retry (navigator not ready yet).
  static void _push(Widget screen, {required int attempts}) {
    final nav = rootNavKey.currentState;
    if (nav == null) {
      if (attempts < 40) {
        Future.delayed(const Duration(milliseconds: 250),
            () => _push(screen, attempts: attempts + 1));
      }
      return;
    }
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }

  /// The navigator may not exist yet on a cold start — retry briefly.
  static void _openReset(String uidb64, String token,
      {required int attempts}) {
    final nav = rootNavKey.currentState;
    if (nav == null) {
      if (attempts < 40) {
        Future.delayed(const Duration(milliseconds: 250),
            () => _openReset(uidb64, token, attempts: attempts + 1));
      }
      return;
    }
    nav.push(MaterialPageRoute(
        builder: (_) =>
            ResetPasswordScreen(uidb64: uidb64, token: token)));
  }
}
