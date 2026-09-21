import 'package:flutter/material.dart';

import '../screens/customer/my_orders_screen.dart';
import '../screens/ride/ride_home_screen.dart';
import '../screens/ride/ride_tracking_screen.dart';
import '../screens/ride/rider_console_screen.dart';
import '../screens/customer/notifications_screen.dart';
import '../screens/notices/notice_board_screen.dart';
import '../screens/ums/ums_dashboard_screen.dart';
import '../screens/ums/ums_login_screen.dart';
import '../screens/vendor/vendor_shell.dart';
import 'api_client.dart';
import 'fcm.dart';
import 'local_store.dart';
import 'ride_events.dart';

/// ⭐ v53: GLOBAL notification deep-link router.
///
/// Any notification the user taps (FCM tray, local heads-up, cold start)
/// carries a `route` string. This router turns it into real navigation
/// using the root navigator — no matter which screen is currently open,
/// whether the app was foreground, background or fully closed.
///
/// Routes: 'orders' | 'ums' | 'feed' | 'ride' | 'notifications' | 'vendor'
class NotifRouter {
  NotifRouter._();

  static bool _installed = false;

  /// Called once from main() after runApp — installs the handler and
  /// replays any tap that launched the app (cold start).
  static void install() {
    if (_installed) return;
    _installed = true;
    setNotifRouteHandler(_open);
  }

  static void _open(String route) {
    // The navigator may not be mounted yet on a cold start — retry
    // briefly until the first frame/screen is up, then navigate.
    _tryOpen(route, attempts: 0);
  }

  static void _tryOpen(String route, {required int attempts}) {
    final nav = rootNavKey.currentState;
    if (nav == null) {
      if (attempts < 40) {
        Future.delayed(const Duration(milliseconds: 250),
            () => _tryOpen(route, attempts: attempts + 1));
      }
      return;
    }
    // Give the splash router a moment to settle on cold starts.
    // ⭐ v55: keep retrying while the saved session is still loading —
    // previously a cold-start tap was silently dropped if the token
    // had not been restored yet, so the notification "did nothing".
    if (!_sessionReady()) {
      if (attempts < 40) {
        Future.delayed(const Duration(milliseconds: 500),
            () => _tryOpen(route, attempts: attempts + 1));
      }
      return;
    }
    switch (route) {
      case 'orders':
        if (ApiConfig.studentToken == null) return;
        // ⭐ v55: food order status notifications land on My Orders —
        // the same section opened from the profile icon on the home page.
        nav.push(MaterialPageRoute(builder: (_) => const MyOrdersScreen()));
        break;
      case 'ums':
        if (ApiConfig.studentToken == null) return;
        final hasUms = (LocalStore.get('ums_uid') ?? '').isNotEmpty;
        nav.push(MaterialPageRoute(
            builder: (_) => hasUms
                ? const UmsDashboardScreen()
                : const UmsLoginScreen()));
        break;
      case 'feed':
        if (ApiConfig.studentToken == null) return;
        nav.push(
            MaterialPageRoute(builder: (_) => const CunnectFeedScreen()));
        break;
      case 'notifications':
        if (ApiConfig.studentToken == null) return;
        nav.push(MaterialPageRoute(
            builder: (_) => const NotificationsScreen()));
        break;
      case 'broadcast':
        // ⭐ v73: broadcasts stay ON THE HOME PAGE — the dashboard shows
        // the message as a centred card (see _BroadcastCard).
        if (ApiConfig.studentToken == null) return;
        LocalStore.set('bc_pending', '1');
        nav.popUntil((r) => r.isFirst);
        break;
      case 'ride':
        // ⭐ v74: ride partners land in their console, students on the
        // live ride screen for THAT ride — the code rides along with the
        // push, so it works even with several rides in flight.
        final ev = RideEvents.pending;
        final code = (ev != null && ev.code.isNotEmpty)
            ? ev.code
            : '${LocalStore.get('active_ride_code') ?? ''}';
        if (ApiConfig.vendorToken != null && ApiConfig.studentToken == null) {
          nav.push(
              MaterialPageRoute(builder: (_) => const RiderConsoleScreen()));
          break;
        }
        if (ApiConfig.studentToken == null) return;
        nav.push(MaterialPageRoute(
            builder: (_) => code.isNotEmpty
                ? RideTrackingScreen(rideCode: code)
                : const RideHomeScreen()));
        break;
      case 'vendor':
        if (ApiConfig.vendorToken == null) return;
        // Vendors land on their portal; if it is already the current
        // screen this simply brings a fresh copy with Orders loaded.
        nav.push(MaterialPageRoute(builder: (_) => const VendorShell()));
        break;
      default:
        break;
    }
  }

  static bool _sessionReady() =>
      ApiConfig.studentToken != null || ApiConfig.vendorToken != null;
}
