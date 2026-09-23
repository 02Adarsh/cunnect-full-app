import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'app_portal.dart';
import 'local_store.dart';
import 'ride_events.dart';
import 'ring_service.dart';

/// ⭐ root navigator key
final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

// ⭐ v5: the shrinker was stripping sound files from the APK (fixed via keep.xml) —
// but the v4 channels were created on phones WITHOUT sound, hence a new id.
// ⭐ v75: Android locks a channel's sound at creation time, so switching to
// the Universfield tone needs fresh ids (v6) again.
const kChannelUser = 'cunnect_ping_v6';
const kChannelVendor = 'cunnect_alert_v6';

/// ⭐ v75: notification tone used by BOTH channels.
/// Drop a file with this name in android/app/src/main/res/raw/ to change it.
const kNotifSound = 'universfield_new_notification_066_494545';

final FlutterLocalNotificationsPlugin _local =
    FlutterLocalNotificationsPlugin();

/// ⭐ v53: DEEP-LINK NAV — tapping any notification opens the matching
/// section of the app (orders / vendor / ums / feed / notifications),
/// whether the app was in the foreground, background or fully closed.
/// The route arrives in FCM `data['route']`; local notifications carry
/// it in their payload.
String? pendingNotifRoute;

typedef NotifRouteHandler = void Function(String route);

/// The dashboard registers the real navigator here once it is mounted.
NotifRouteHandler? _routeHandler;

void setNotifRouteHandler(NotifRouteHandler? handler) {
  _routeHandler = handler;
  // A tap that happened before the UI was ready (cold start) fires now.
  if (handler != null && pendingNotifRoute != null) {
    final r = pendingNotifRoute!;
    pendingNotifRoute = null;
    handler(r);
  }
}

void dispatchNotifRoute(String? route) {
  final r = (route ?? '').trim();
  if (r.isEmpty) return;
  final h = _routeHandler;
  if (h != null) {
    h(r);
  } else {
    pendingNotifRoute = r; // consumed when the dashboard mounts
  }
}

/// ⭐ v73: remember a BROADCAST so the home page can show it as a card
/// the moment the notification is tapped (or the app is opened from it).
void rememberBroadcast(Map<String, dynamic> data) {
  final route = '${data['route'] ?? ''}';
  if (route != 'broadcast') return;
  final title = '${data['title'] ?? 'CUnnect'}';
  final body = '${data['body'] ?? ''}';
  if (title.trim().isEmpty && body.trim().isEmpty) return;
  LocalStore.set('bc_title', title);
  LocalStore.set('bc_body', body);
  LocalStore.set('bc_pending', '1');
}

/// ⭐ Zomato-style heads-up + sound + CU icon — with the screen on or off
Future<void> _showLocal(Map<String, dynamic> data) async {
  rememberBroadcast(data);
  final title = '${data['title'] ?? 'CUnnect'}';
  final body = '${data['body'] ?? ''}';
  final portal = ('${data['portal'] ?? ''}').trim().toLowerCase();
  final vendor = data['kind'] == 'vendor' ||
      portal == 'vendor' ||
      portal == 'rider';
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      vendor ? kChannelVendor : kChannelUser,
      vendor ? 'CUnnect Partner Alerts' : 'CUnnect Updates',
      channelDescription:
          vendor ? 'New order alerts — accept/reject' : 'Order & campus updates',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'cu_notif',
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(kNotifSound),
      enableVibration: true,
      enableLights: true,
      category: AndroidNotificationCategory.message,
      audioAttributesUsage: AudioAttributesUsage.notification,
      styleInformation: BigTextStyleInformation(body),
    ),
    // ⭐ v63: iOS presentation — banner + sound, same as Android.
    iOS: const DarwinNotificationDetails(
        presentAlert: true, presentSound: true, presentBadge: true),
  );
  await _local.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000 % 1000000,
    title,
    body,
    details,
    payload: '${data['route'] ?? (vendor ? 'vendor' : 'orders')}',
  );
}

/// ⭐ app killed/screen-off — background isolate me local notification
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  // ⭐ with a notification payload the SYSTEM shows the tray/heads-up itself
  // (guaranteed even with the screen off) — local only for pure-data messages.
  if (message.notification == null) {
    await _showLocal(message.data);
  }
}

/// ⭐ Firebase init + channels + permission + token register
Future<void> initFcm() async {
  if (kIsWeb) return;
  // ⭐ NO popup/banner in the foreground — removed at the user's request.
  // The system tray notification (background/screen-off) keeps working.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onMessage.listen((m) async {
      debugPrint('[FCM] foreground msg: ${m.notification?.title} ${m.data}');
      // ⭐ v74: with the app OPEN the push used to be swallowed silently
      // (no tray entry, no popup) — that is why ride notifications never
      // showed up. Data-only messages still need a local heads-up, and
      // ride events also raise their POPUP right away.
      final data = Map<String, dynamic>.from(m.data);
      final notif = m.notification;
      if (notif != null) {
        data['title'] = notif.title ?? '';
        data['body'] = notif.body ?? '';
      }
      final route = '${data['route'] ?? ''}';
      // ⭐ v74: in the FOREGROUND Android does NOT show a notification
      // payload by itself — ride alerts would simply vanish. So they
      // always get a local heads-up as well as their in-app popup.
      if (notif == null || route == 'ride') {
        await _showLocal(data);
      }
      // ⭐ v75: every partner portal rings non-stop for 20 seconds on new
      // work — food order, printout job or ride request. Accept/reject
      // stops it immediately.
      await RingService.ringForPush(data);
      if (route == 'ride') {
        await RideEvents.handle(
          data,
          title: '${data['title'] ?? ''}',
          body: '${data['body'] ?? ''}',
          context: rootNavKey.currentContext,
        );
      }
    });
  } catch (e) {
    debugPrint('[FCM] listener registration failed: $e');
  }
  startInstantPolling();
  try {
    await _local.initialize(
      // ⭐ v63: iOS settings added — local notifications work on both.
      const InitializationSettings(
          android: AndroidInitializationSettings('cu_notif'),
          iOS: DarwinInitializationSettings()),
      // ⭐ v53: tap on a local notification -> jump to that section
      onDidReceiveNotificationResponse: (resp) {
        dispatchNotifRoute(resp.payload);
      },
    );
    // ⭐ Cold start from a local notification tap
    try {
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        pendingNotifRoute =
            launch?.notificationResponse?.payload ?? pendingNotifRoute;
      }
    } catch (_) {}
    final android = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    // ⭐ purane channels delete — unme sound settings corrupt/mute ho sakti
    // (Android channel settings cannot be changed after creation).
    for (final old in [
      'cunnect_ping', 'cunnect_alert',
      'cunnect_ping_v2', 'cunnect_alert_v2',
      'cunnect_ping_v3', 'cunnect_alert_v3',
      'cunnect_ping_v4', 'cunnect_alert_v4',
      'cunnect_ping_v5', 'cunnect_alert_v5',
    ]) {
      try {
        await android?.deleteNotificationChannel(old);
      } catch (_) {}
    }
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      kChannelUser,
      'CUnnect Updates',
      description: 'Order & campus updates',
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(kNotifSound),
      enableVibration: true,
      enableLights: true,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      kChannelVendor,
      'CUnnect Partner Alerts',
      description: 'New order alerts — accept/reject',
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(kNotifSound),
      enableVibration: true,
      enableLights: true,
    ));
    await android?.requestNotificationsPermission();

    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    // ⭐ v53: FCM notification tapped while the app was in the background
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      rememberBroadcast(m.data);
      final data = Map<String, dynamic>.from(m.data);
      if (m.notification != null) {
        data['title'] = m.notification!.title ?? '';
        data['body'] = m.notification!.body ?? '';
      }
      // ⭐ v74: ride taps also raise the matching popup once the screen
      // is open (accept / pay / OTP / completed ...).
      if ('${data['route'] ?? ''}' == 'ride') {
        RideEvents.handle(
          data,
          title: '${data['title'] ?? ''}',
          body: '${data['body'] ?? ''}',
          context: rootNavKey.currentContext,
          fromTap: true,
        );
      }
      dispatchNotifRoute('${m.data['route'] ?? ''}');
    });
    // ⭐ v53: FCM notification tapped while the app was fully CLOSED
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        rememberBroadcast(initial.data);
        final data = Map<String, dynamic>.from(initial.data);
        if (initial.notification != null) {
          data['title'] = initial.notification!.title ?? '';
          data['body'] = initial.notification!.body ?? '';
        }
        if ('${data['route'] ?? ''}' == 'ride') {
          RideEvents.handle(
            data,
            title: '${data['title'] ?? ''}',
            body: '${data['body'] ?? ''}',
            fromTap: true,
          );
        }
        pendingNotifRoute =
            '${initial.data['route'] ?? ''}'.isEmpty
                ? pendingNotifRoute
                : '${initial.data['route']}';
      }
    } catch (_) {}
    await FirebaseMessaging.instance.requestPermission();

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await registerFcmToken(token);
    if (ApiConfig.vendorToken != null) {
      await registerFcmToken(token, 'vendor');
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      registerFcmToken(t);
      registerFcmToken(t, 'vendor');
    });
  } catch (e) {
    debugPrint('[FCM] init failed: $e');
  }
}

/// ⭐ device token backend ko do (student / vendor role ke saath)
Future<void> registerFcmToken([String? token, String role = 'student']) async {
  if (kIsWeb) return;
  final authToken =
      role == 'vendor' ? ApiConfig.vendorToken : ApiConfig.studentToken;
  if (authToken == null) return;
  try {
    token ??= await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await ApiClient().post(
        role == 'vendor' ? '/api/vendor/device/token/' : '/api/device/token/',
        body: {'token': token},
        token: authToken);
  } catch (_) {}
}

// ⭐ INSTANT ALERT POLLING — battery saver / FCM delay se azad.
// In the foreground the app itself checks the backend every 12 sec;
// new order / status change → instant local heads-up notification.
bool _inForeground = true;

class _LifeObs extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _inForeground = (s == AppLifecycleState.resumed);
  }
}

Timer? _pollTimer;

final Set<String> _seenVendorOrders = {};
final Map<String, String> _seenStudentStatus = {};
bool _pollBusy = false;

void startInstantPolling() {
  if (kIsWeb || _pollTimer != null) return;
  WidgetsBinding.instance.addObserver(_LifeObs());
  _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
    _pollTick();
  });
}

Future<void> _pollTick() async {
  if (_pollBusy) return;
  _pollBusy = true;
  try {
    final api = ApiClient();
    // ⭐ vendor: new pending orders instantly
    if (ApiConfig.vendorToken != null) {
      try {
        final r = await api.get('/api/vendor/dashboard/',
            token: ApiConfig.vendorToken);
        final orders = (r['data']?['incoming_orders'] as List?) ?? [];
        for (final o in orders) {
          final id = '${o['id']}';
          if (_seenVendorOrders.isNotEmpty &&
              !_seenVendorOrders.contains(id)) {
            await _showLocal({
              'title': 'New order received',
              'body':
                  '${o['order_number'] ?? ''} • ${o['customer_name'] ?? ''}',
              'kind': 'vendor',
              'route': 'vendor',
            });
          }
          _seenVendorOrders.add(id);
        }
      } catch (_) {}
    }
    // ⭐ student: order status changes instantly
    if (ApiConfig.studentToken != null) {
      try {
        final r = await api.get('/api/food/orders/status/',
            token: ApiConfig.studentToken);
        final orders = (r['data']?['orders'] as List?) ?? [];
        for (final o in orders) {
          final id = '${o['id']}';
          final st = '${o['status']}';
          final prev = _seenStudentStatus[id];
          if (prev != null && prev != st) {
            await _showLocal({
              'title': 'Order $st',
              'body':
                  '${o['order_number'] ?? ''} • ${o['vendor_name'] ?? ''}',
              'kind': 'user',
              'route': 'orders',
            });
          }
          _seenStudentStatus[id] = st;
        }
      } catch (_) {}
    }
    // ⭐ v62: UMS is NO LONGER polled from here. Scraping now happens
    // ONLY when the student actually opens the UMS screen (the backend
    // serves its cache instantly and refreshes in the background), and
    // attendance-change alerts arrive via server-side FCM push from the
    // keepalive — zero portal load from idle app users.
  } finally {
    _pollBusy = false;
  }
}

/// ⭐ YouTube-style TOP heads-up popup — har screen pe (student + vendor)
void showCunnectPopup(String title, String body, {bool vendor = false}) {
  final overlay = rootNavKey.currentState?.overlay;
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CunnectPopup(
      title: title,
      body: body,
      vendor: vendor,
      onClose: () {
        try {
          entry.remove();
        } catch (_) {}
      },
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 4), () {
    try {
      entry.remove();
    } catch (_) {}
  });
}

class _CunnectPopup extends StatefulWidget {
  final String title;
  final String body;
  final bool vendor;
  final VoidCallback onClose;

  const _CunnectPopup(
      {required this.title,
      required this.body,
      required this.vendor,
      required this.onClose});

  @override
  State<_CunnectPopup> createState() => _CunnectPopupState();
}

class _CunnectPopupState extends State<_CunnectPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _slide = Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Positioned(
      top: top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF17171A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: widget.vendor
                        ? const Color(0xFFF10B1D)
                        : const Color(0x66F10B1D),
                    width: 1.2),
                boxShadow: const [
                  BoxShadow(color: Color(0xAA000000), blurRadius: 18,
                      offset: Offset(0, 6)),
                ],
              ),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x29F10B1D),
                    border: Border.all(
                        color: const Color(0x59F10B1D), width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: const Text('CU',
                      style: TextStyle(
                          color: Color(0xFFF10B1D),
                          fontSize: 13,
                          fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(widget.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFFB9B9BE), fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.close, size: 15,
                    color: Color(0xFF8A8A90)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
