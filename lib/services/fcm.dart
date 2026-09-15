import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';

/// ⭐ root navigator key
final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

const kChannelUser = 'cunnect_ping_v3';
const kChannelVendor = 'cunnect_alert_v3';

final FlutterLocalNotificationsPlugin _local =
    FlutterLocalNotificationsPlugin();

/// ⭐ Zomato-style heads-up + sound + CU icon — screen on/off dono pe
Future<void> _showLocal(Map<String, dynamic> data) async {
  final title = '${data['title'] ?? 'CUnnect'}';
  final body = '${data['body'] ?? ''}';
  final vendor = data['kind'] == 'vendor';
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      vendor ? kChannelVendor : kChannelUser,
      vendor ? 'CUnnect Partner Alerts' : 'CUnnect Updates',
      channelDescription:
          vendor ? 'New order alerts — accept/reject' : 'Order & campus updates',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'cu_notif',
      sound: RawResourceAndroidNotificationSound(
          vendor ? 'cunnect_alert' : 'cunnect_ping'),
      enableVibration: true,
      enableLights: true,
      styleInformation: BigTextStyleInformation(body),
    ),
  );
  await _local.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000 % 1000000,
    title,
    body,
    details,
  );
}

/// ⭐ app killed/screen-off — background isolate me local notification
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  // ⭐ notification payload ho to SYSTEM khud tray/heads-up dikhata hai
  // (screen-off pe bhi guaranteed) — local sirf pure-data messages ke liye.
  if (message.notification == null) {
    await _showLocal(message.data);
  }
}

/// ⭐ Firebase init + channels + permission + token register
Future<void> initFcm() async {
  if (kIsWeb) return;
  // ⭐ foreground me koi popup/banner NAHI — user ne hatwa diya.
  // System tray notification (background/screen-off) chalti rahegi.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onMessage.listen((m) {
      debugPrint('[FCM] foreground msg: ${m.notification?.title} ${m.data}');
    });
  } catch (e) {
    debugPrint('[FCM] listener registration failed: $e');
  }
  startInstantPolling();
  try {
    await _local.initialize(
        const InitializationSettings(
            android: AndroidInitializationSettings('cu_notif')));
    final android = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      kChannelUser,
      'CUnnect Updates',
      description: 'Order & campus updates',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('cunnect_ping'),
      enableVibration: true,
      enableLights: true,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      kChannelVendor,
      'CUnnect Partner Alerts',
      description: 'New order alerts — accept/reject',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('cunnect_alert'),
      enableVibration: true,
      enableLights: true,
    ));
    await android?.requestNotificationsPermission();

    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
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
// App foreground me khud har 12 sec backend check karti hai;
// naya order / status change → turant local heads-up notification.
bool _inForeground = true;

class _LifeObs extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _inForeground = (s == AppLifecycleState.resumed);
  }
}

Timer? _pollTimer;
int _pollCount = 0;
double? _lastAttendance;
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
    // ⭐ vendor: naye pending orders turant
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
            });
          }
          _seenVendorOrders.add(id);
        }
      } catch (_) {}
    }
    // ⭐ student: order status change turant
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
            });
          }
          _seenStudentStatus[id] = st;
        }
      } catch (_) {}
    }
    // ⭐ UMS attendance watch (~2 min) — change hote hi alert
    _pollCount++;
    if (ApiConfig.studentToken != null && _pollCount % 10 == 0) {
      try {
        final r = await api.get('/api/ums/dashboard/',
            token: ApiConfig.studentToken);
        final raw = r['data']?['overall_attendance'];
        final ov = raw is num ? raw.toDouble() : null;
        if (ov != null) {
          if (_lastAttendance != null &&
              (ov - _lastAttendance!).abs() > 0.001) {
            final msg = 'Overall attendance is now ${ov.toStringAsFixed(1)}%.';
            if (_inForeground) {
              showCunnectPopup('Attendance updated', msg);
            } else {
              await _showLocal(
                  {'title': 'Attendance updated', 'body': msg, 'kind': 'user'});
            }
          }
          _lastAttendance = ov;
        }
      } catch (_) {}
    }
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
                        ? const Color(0xFF2E9D55)
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
