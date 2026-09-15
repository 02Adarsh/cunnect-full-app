import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/app_store.dart';
import '../services/autostart.dart';
import '../services/apk_download.dart';
import '../services/local_store.dart';
import '../services/fcm.dart';
import '../services/open_url.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import 'auth/student_login_screen.dart';
import 'dashboard/student_dashboard_screen.dart';
import 'vendor/vendor_shell.dart';

BuildContext? get rootNavKeyForUpdate => rootNavKey.currentContext;

/// ⭐ App ka internal version — naya APK banate waqt badhao +
/// backend deploy/app_version.json me bhi same number + APK link daalo.
const int kAppVersion = 39;

/// ⭐ Har app-open pe animated CUnnect splash — phir session ke hisaab se route.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  String? _updateUrl;
  int _updateVer = 0;
  bool _prefetched = false;
  late final AnimationController _ctrl;
  late final Animation<double> _logoAnim;
  late final Animation<double> _tagAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    _logoAnim = CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.05, 0.55, curve: Curves.easeOutCubic));
    _tagAnim = CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut));
    _checkUpdate().then((_) {
      _prefetchMedia();
      _ctrl.forward().then((_) => _route());
    });
  }

  /// ⭐ Splash ke dauran hi banner/hero images disk-cache me garam karo.
  void _prefetchMedia() {
    if (_prefetched) return;
    _prefetched = true;
    final store = context.read<AppStore>();
    final urls = <String>[
      ...store.dashboardBanners.map((b) => b.imageUrl),
      ...store.heroSlides.map((h) => h.image),
      ...store.offers.map((o) => o.imageUrl),
    ].where((u) => u.startsWith('http')).take(10);
    for (final u in urls) {
      precacheImage(CachedNetworkImageProvider(u), context)
          .catchError((_) {});
    }
  }

  /// ⭐ Server se latest version check — naya APK hai to update dialog.
  Future<void> _checkUpdate() async {
    try {
      final api = ApiClient();
      final data = api
          .dataOf(await api
              .get('/api/app/version/')
              .timeout(const Duration(seconds: 4)));
      final ver = (data['version'] ?? 0) is int
          ? (data['version'] as int)
          : int.tryParse('${data['version']}') ?? 0;
      final url = (data['url'] ?? '').toString();
      if (ver > kAppVersion && url.isNotEmpty) {
        // ⭐ Later dabaya tha to wahi version dobara mat dikhao
        final skipped =
            int.tryParse(LocalStore.get('skip_update_ver') ?? '') ?? 0;
        if (ver > skipped) {
          _updateUrl = url;
          _updateVer = ver;
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _route() {
    if (!mounted) return;
    final store = context.read<AppStore>();
    final Widget next;
    if (store.studentLoggedIn) {
      next = const StudentDashboardScreen(); // ⭐ login tha -> seedha dashboard
    } else if (ApiConfig.vendorToken != null) {
      next = const VendorShell(); // ⭐ vendor logged-in -> vendor dashboard
    } else {
      next = const StudentLoginScreen();
    }
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => next));
    if (_updateUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = rootNavKeyForUpdate;
        if (ctx == null) return;
        showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF161616),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Update available 🎉',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: const Text(
                'A new version of CUnnect is available. '
                'Update now for the best experience.',
                style: TextStyle(color: Color(0xFFB5B5B5), fontSize: 12.5)),
            actions: [
              TextButton(
                onPressed: () {
                  LocalStore.set('skip_update_ver', '$_updateVer');
                  Navigator.of(ctx).pop();
                },
                child: const Text('Later',
                    style: TextStyle(color: Color(0xFF9A9A9A))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF10B1D)),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final ok = await downloadApk(_updateUrl!);
                  if (!ok) await openExternalUrl(_updateUrl!);
                  final c = rootNavKeyForUpdate;
                  if (c != null) {
                    showCunnectToast(
                        c,
                        ok
                            ? 'Download started — install from the notification'
                            : 'Opening download in browser');
                  }
                },
                child: const Text('UPDATE',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ),
        );
      });
    }
    if (_updateUrl == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = rootNavKeyForUpdate;
        if (ctx != null) promptAutostartOnce(ctx);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _logoAnim,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.72, end: 1.0)
                          .animate(_logoAnim),
                      child: const CunnectWordmark(fontSize: 52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeTransition(
                    opacity: _tagAnim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(0, 0.35),
                              end: Offset.zero)
                          .animate(_tagAnim),
                      child: const Text('YOUR CAMPUS. CONNECTED.',
                          style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
