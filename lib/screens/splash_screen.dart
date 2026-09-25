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
const int kAppVersion = 89;

/// ⭐ v89: pending update lives OUTSIDE SplashScreen so dispose / route
/// change can never drop it. "Later" only closes this session — the next
/// process start resets [shown] and the popup returns (old behaviour).
class PendingUpdate {
  static String? url;
  static int ver = 0;
  /// True only while a dialog is currently on screen this session.
  static bool showing = false;
  /// True after user tapped Later this session (suppress re-show until
  /// next cold start — process kill resets this static).
  static bool dismissedThisSession = false;

  static void set(String u, int v) {
    url = u;
    ver = v;
  }

  static bool get hasUpdate =>
      url != null && url!.isNotEmpty && ver > kAppVersion;

  /// Show the sticky update sheet on the ROOT navigator.
  /// Safe to call many times — only one sheet; never on a dying route.
  static void present({int attempt = 0}) {
    if (!hasUpdate) return;
    if (dismissedThisSession) return;
    if (showing) return;
    final ctx = rootNavKey.currentContext;
    if (ctx == null) {
      if (attempt < 50) {
        Future.delayed(const Duration(milliseconds: 200),
            () => present(attempt: attempt + 1));
      }
      return;
    }
    // ⭐ Never show while SplashScreen is still the top route — that is
    // what made the popup flash and vanish on pushReplacement.
    final nav = rootNavKey.currentState;
    if (nav == null) {
      if (attempt < 50) {
        Future.delayed(const Duration(milliseconds: 200),
            () => present(attempt: attempt + 1));
      }
      return;
    }
    // If the top page is still the splash (it has no settings name), wait
    // until at least one post-splash frame has settled.
    showing = true;
    try {
      showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogCtx) {
          return PopScope(
            canPop: false,
            child: _UpdateDialog(
              version: ver,
              url: url!,
              onLater: () {
                // Session-only dismiss. Next cold start → popup again.
                dismissedThisSession = true;
                showing = false;
                // Do NOT write skip_update_ver — old sticky behaviour.
              },
            ),
          );
        },
      ).then((_) {
        // Dialog closed (Later or install). Keep dismissedThisSession if Later.
        showing = false;
      }).catchError((_) {
        showing = false;
      });
    } catch (_) {
      showing = false;
      if (attempt < 50) {
        Future.delayed(const Duration(milliseconds: 300),
            () => present(attempt: attempt + 1));
      }
    }
  }
}

/// ⭐ Animated CUnnect splash on every app open — then route by session.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _prefetched = false;
  bool _routed = false;
  late final AnimationController _ctrl;
  late final Animation<double> _logoAnim;
  late final Animation<double> _tagAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _logoAnim = CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.05, 0.55, curve: Curves.easeOutCubic));
    _tagAnim = CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut));
    _prefetchMedia();
    // ⭐ v89: kick update probe + lock refresh in parallel with splash.
    // NEVER show the update dialog on this route.
    _checkUpdate();
    _warmLocksBeforeRoute();
    _ctrl.forward().then((_) => _route());
  }

  /// ⭐ v89: while splash plays, refresh lock flags so the dashboard
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

  Future<void> _checkUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    // Only store the URL here — present() is called AFTER we leave splash.
    final found = await _fetchUpdate(const Duration(seconds: 2));
    if (!found) {
      Future.delayed(const Duration(seconds: 3), () async {
        await _fetchUpdate(const Duration(seconds: 5));
        // If we already left splash, try present now.
        if (_routed) PendingUpdate.present();
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
      final url = (data['apk_url'] ?? data['url'] ?? '').toString().trim();
      if (ver > kAppVersion && url.isNotEmpty) {
        LocalStore.remove('skip_update_ver');
        PendingUpdate.set(url, ver);
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
      next = const StudentDashboardScreen();
    } else if (ApiConfig.vendorToken != null) {
      next = const VendorShell();
    } else {
      next = const StudentLoginScreen();
    }
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => next));
    // ⭐ v89: ONLY after splash is gone — sticky popup on the new route.
    // Multiple staggered tries so a slow first frame still gets it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PendingUpdate.present();
      if (!PendingUpdate.hasUpdate) {
        final ctx = rootNavKeyForUpdate;
        if (ctx != null) promptAutostartOnce(ctx);
      }
    });
    Future.delayed(const Duration(milliseconds: 400), PendingUpdate.present);
    Future.delayed(const Duration(milliseconds: 1000), PendingUpdate.present);
    Future.delayed(const Duration(milliseconds: 2000), PendingUpdate.present);
    Future.delayed(const Duration(milliseconds: 4000), PendingUpdate.present);
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

/// ⭐ v85/v89: in-app update sheet — live progress, then auto-install.
/// Stays until Later OR successful install. Back button blocked.
class _UpdateDialog extends StatefulWidget {
  final int version;
  final String url;
  final VoidCallback? onLater;
  const _UpdateDialog(
      {required this.version, required this.url, this.onLater});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double _progress = 0;
  String _status = '';
  String? _error;

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = -1;
      _status = 'Starting download…';
      _error = null;
    });
    final ok = await downloadApk(
      widget.url,
      onProgress: (p, status) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          if (status.isNotEmpty) _status = status;
        });
      },
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _progress = 1;
        _status = 'Opening installer…';
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = 'Direct download failed — opening in browser.';
      _status = '';
    });
    await openExternalUrl(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF101010),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
          widget.version > 0
              ? 'Update to v${widget.version}'
              : 'Update available',
          style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'A new version of CUnnect is ready. '
              'Tap UPDATE — it installs inside the app, no browser.',
              style: TextStyle(color: Color(0xFFB5B5B5), fontSize: 12.5)),
          if (_busy) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress < 0 ? null : _progress.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: const Color(0xFF2A2A2A),
                color: const Color(0xFFF10B1D),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _progress >= 0
                  ? '${(_progress * 100).floor()}%  ·  $_status'
                  : _status,
              style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 11),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Color(0xFFFFABB2), fontSize: 11)),
          ],
        ],
      ),
      actions: [
        if (!_busy)
          TextButton(
            onPressed: () {
              widget.onLater?.call();
              Navigator.of(context).pop();
            },
            child: const Text('Later',
                style: TextStyle(color: Color(0xFF9A9A9A))),
          ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF10B1D)),
          onPressed: _busy ? null : _start,
          child: Text(_busy ? 'DOWNLOADING' : 'UPDATE',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      ],
    );
  }
}
