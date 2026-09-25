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

/// ⭐ Internal app version — bump when shipping a new APK +
/// put the same number + APK link in backend deploy/app_version.json.
const int kAppVersion = 90;

/// ⭐ v90: sticky in-app update via ROOT OverlayEntry.
///
/// Why Overlay (not showDialog on a route):
///   showDialog is tied to a route. Splash → pushReplacement destroyed the
///   dialog (flash then vanish). An OverlayEntry on rootNavKey.overlay
///   survives every route change until we remove it.
///
/// Later = this session only (static flag). Next process start → popup again.
/// Never writes skip_update_ver.
class PendingUpdate {
  static String? url;
  static int ver = 0;
  static bool dismissedThisSession = false;
  static OverlayEntry? _entry;

  static void set(String u, int v) {
    url = u;
    ver = v;
  }

  static bool get hasUpdate =>
      url != null && url!.isNotEmpty && ver > kAppVersion;

  static bool get isShowing => _entry != null;

  /// Insert (or keep) the sticky sheet on the root overlay.
  static void present({int attempt = 0}) {
    if (!hasUpdate) return;
    if (dismissedThisSession) return;
    if (_entry != null) return; // already on screen

    final overlay = rootNavKey.currentState?.overlay;
    if (overlay == null) {
      if (attempt < 60) {
        Future.delayed(const Duration(milliseconds: 200),
            () => present(attempt: attempt + 1));
      }
      return;
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      opaque: false,
      maintainState: true,
      builder: (ctx) {
        return Material(
          color: Colors.black54,
          child: Center(
            child: _UpdateDialog(
              version: ver,
              url: url!,
              onLater: () {
                dismissedThisSession = true;
                _remove();
              },
              onInstalled: () {
                // User got the installer — drop the sheet.
                dismissedThisSession = true;
                _remove();
              },
            ),
          ),
        );
      },
    );
    _entry = entry;
    try {
      overlay.insert(entry);
    } catch (_) {
      _entry = null;
      if (attempt < 60) {
        Future.delayed(const Duration(milliseconds: 300),
            () => present(attempt: attempt + 1));
      }
    }
  }

  static void _remove() {
    try {
      _entry?.remove();
    } catch (_) {}
    _entry = null;
  }
}

/// ⭐ Animated CUnnect splash — then route by session.
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
    // ⭐ NEVER show update on splash. Only probe + warm locks.
    _checkUpdate();
    _warmLocksBeforeRoute();
    _ctrl.forward().then((_) => _route());
  }

  /// Always refresh locks while splash plays so dashboard opens locked.
  Future<void> _warmLocksBeforeRoute() async {
    try {
      final store = context.read<AppStore>();
      if (store.studentLoggedIn) {
        // ⭐ v90: ALWAYS await — even if cache has old unlocked state.
        await store.loadStoreSections()
            .timeout(const Duration(seconds: 5), onTimeout: () {});
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
    final found = await _fetchUpdate(const Duration(seconds: 2));
    if (!found) {
      Future.delayed(const Duration(seconds: 3), () async {
        await _fetchUpdate(const Duration(seconds: 6));
        if (_routed) PendingUpdate.present();
      });
    } else if (_routed) {
      PendingUpdate.present();
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
    // ⭐ v90: always one more await so locks are live before hub paints.
    if (store.studentLoggedIn) {
      try {
        await store.loadStoreSections()
            .timeout(const Duration(seconds: 3), onTimeout: () {});
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

    // Sticky overlay AFTER splash is gone — staggered so slow frames still hit.
    void show() => PendingUpdate.present();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      show();
      if (!PendingUpdate.hasUpdate) {
        final ctx = rootNavKeyForUpdate;
        if (ctx != null) promptAutostartOnce(ctx);
      }
    });
    Future.delayed(const Duration(milliseconds: 300), show);
    Future.delayed(const Duration(milliseconds: 800), show);
    Future.delayed(const Duration(milliseconds: 1600), show);
    Future.delayed(const Duration(milliseconds: 3000), show);
    Future.delayed(const Duration(milliseconds: 5000), show);
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

/// Sticky update card (used inside the root OverlayEntry).
class _UpdateDialog extends StatefulWidget {
  final int version;
  final String url;
  final VoidCallback? onLater;
  final VoidCallback? onInstalled;
  const _UpdateDialog({
    required this.version,
    required this.url,
    this.onLater,
    this.onInstalled,
  });

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
      widget.onInstalled?.call();
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
    // Card-style sheet (not AlertDialog) so it is not route-owned.
    return PopScope(
      canPop: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.version > 0
                  ? 'Update to v${widget.version}'
                  : 'Update available',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'A new version of CUnnect is ready. '
              'Tap UPDATE — it installs inside the app, no browser.',
              style: TextStyle(color: Color(0xFFB5B5B5), fontSize: 12.5),
            ),
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
                style:
                    const TextStyle(color: Color(0xFF9A9A9A), fontSize: 11),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFFFABB2), fontSize: 11)),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_busy)
                  TextButton(
                    onPressed: () => widget.onLater?.call(),
                    child: const Text('Later',
                        style: TextStyle(color: Color(0xFF9A9A9A))),
                  ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF10B1D)),
                  onPressed: _busy ? null : _start,
                  child: Text(_busy ? 'DOWNLOADING' : 'UPDATE',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
