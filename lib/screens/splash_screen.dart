import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
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

/// ⭐ Internal app version — bump it when building a new APK +
/// also put the same number + APK link in backend deploy/app_version.json.
const int kAppVersion = 92;

/// ⭐ Animated CUnnect splash on every app open — then route by session.
/// ⭐ v91: OLD update behaviour restored (simple + reliable) —
/// the app waits for the version check BEFORE the splash animation,
/// so the popup is ready the moment the dashboard appears. "Later"
/// only closes the dialog — it comes back on EVERY app open.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  String? _updateUrl;
  bool _prefetched = false;
  bool _routed = false;
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
    // ⭐ v89 (kept): refresh lock flags in parallel while the splash plays.
    _warmLocksBeforeRoute();
    // ⭐ v91: FIRST the version check, THEN the splash animation runs —
    // exactly the old flow. Slow is fine, reliable is better.
    _checkUpdate().then((_) {
      _prefetchMedia();
      _ctrl.forward().then((_) => _route());
    });
  }

  /// ⭐ v89 (kept): while splash plays, refresh lock flags so the dashboard
  /// paints with the REAL admin lock state (not a stale unlocked cache).
  Future<void> _warmLocksBeforeRoute() async {
    try {
      final store = context.read<AppStore>();
      if (store.studentLoggedIn) {
        await store.loadStoreSections()
            .timeout(const Duration(seconds: 4), onTimeout: () {});
      }
    } catch (_) {}
  }

  /// ⭐ Warm the banner/hero images into the disk cache during the splash.
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

  /// ⭐ Check the latest version on the server — show the update dialog if
  /// a newer APK exists. The first try can time out on a Render cold start,
  /// so it checks again in the background after the splash (late dialog).
  /// ⭐ Android-only — iOS cannot install APKs.
  Future<void> _checkUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final found = await _fetchUpdate(const Duration(seconds: 6));
    if (!found) {
      // ⭐ retry in the background — the dialog still appears once the
      // server wakes up (root navigator, works after splash is gone).
      Future.delayed(const Duration(seconds: 8), () async {
        if (_updateUrl != null) return;
        final ok = await _fetchUpdate(const Duration(seconds: 25));
        if (ok) _showUpdateDialog();
      });
    }
  }

  Future<bool> _fetchUpdate(Duration timeout) async {
    try {
      final api = ApiClient();
      final data = api.dataOf(
          await api.get('/api/app/version/').timeout(timeout));
      final ver = (data['version'] ?? 0) is int
          ? (data['version'] as int)
          : int.tryParse('${data['version']}') ?? 0;
      // ⭐ v91 FIX: read "url" first — the backend sends apk_url as an
      // EMPTY string when unused, which used to shadow the real URL
      // and silently killed the popup. Empty strings are skipped now.
      var url = (data['url'] ?? '').toString().trim();
      if (url.isEmpty) url = (data['apk_url'] ?? '').toString().trim();
      if (ver > kAppVersion && url.isNotEmpty) {
        // ⭐ "Later" never silences the update — the dialog comes back
        // every single time the app is opened until the user updates.
        LocalStore.remove('skip_update_ver');
        _updateUrl = url;
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _route() async {
    if (!mounted || _routed) return;
    _routed = true;
    final store = context.read<AppStore>();
    // One last short try to have fresh locks before paint.
    if (store.studentLoggedIn && store.builtinSections.isEmpty) {
      try {
        await store.loadStoreSections()
            .timeout(const Duration(seconds: 2), onTimeout: () {});
      } catch (_) {}
    }
    if (!mounted) return;
    final Widget next;
    if (store.studentLoggedIn) {
      next = const StudentDashboardScreen(); // ⭐ already logged in -> dashboard
    } else if (ApiConfig.vendorToken != null) {
      next = const VendorShell(); // ⭐ vendor logged-in -> vendor dashboard
    } else {
      next = const StudentLoginScreen();
    }
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => next));
    if (_updateUrl != null) {
      // ⭐ v91 (old behaviour): popup right after the dashboard appears.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showUpdateDialog());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = rootNavKeyForUpdate;
        if (ctx != null) promptAutostartOnce(ctx);
      });
    }
  }

  /// ⭐ Update dialog — the OLD simple one. ⭐ v92: no title line (the user
  /// does not want the "Update to vNN" line) — just the message below it.
  /// "Later" just closes it; reopening the app shows it again. UPDATE
  /// downloads the APK in-app and falls back to the browser.
  void _showUpdateDialog() {
    final ctx = rootNavKeyForUpdate;
    if (ctx == null || _updateUrl == null) return;
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF101010),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        content: const Text(
            'A new version of CUnnect is available. '
            'Update now for the best experience.',
            style: TextStyle(color: Color(0xFFB5B5B5), fontSize: 12.5)),
        actions: [
          TextButton(
            onPressed: () {
              // ⭐ "Later" only closes the dialog — it will be
              // shown again the next time the app is opened.
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
