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
const int kAppVersion = 87;

/// ⭐ Animated CUnnect splash on every app open — then route by session.
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
  bool _updateDialogShown = false;
  late final AnimationController _ctrl;
  late final Animation<double> _logoAnim;
  late final Animation<double> _tagAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        // ⭐ v85: shorter splash — update check no longer holds the door.
        vsync: this, duration: const Duration(milliseconds: 1400));
    _logoAnim = CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.05, 0.55, curve: Curves.easeOutCubic));
    _tagAnim = CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut));
    // ⭐ v85: splash paints immediately. Update check runs in parallel
    // and the dialog pops once (or after) we land on the next screen.
    _prefetchMedia();
    _ctrl.forward().then((_) => _route());
    _checkUpdate();
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
  /// ⭐ v63: Android-only — iOS cannot install APKs (App Store/TestFlight
  /// handles iOS updates), so the dialog is skipped there.
  Future<void> _checkUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    // ⭐ v85: fast first probe (2s). If Render is cold, one short retry.
    // Always try to raise the dialog — _route may already have run.
    final found = await _fetchUpdate(const Duration(seconds: 2));
    if (found) {
      _showUpdateDialog();
      return;
    }
    Future.delayed(const Duration(seconds: 3), () async {
      if (_updateUrl != null) {
        _showUpdateDialog();
        return;
      }
      final ok = await _fetchUpdate(const Duration(seconds: 5));
      if (ok) _showUpdateDialog();
    });
  }

  Future<bool> _fetchUpdate(Duration timeout) async {
    try {
      final api = ApiClient();
      final data = api.dataOf(
          await api.get('/api/app/version/').timeout(timeout));
      final ver = (data['version'] ?? 0) is int
          ? (data['version'] as int)
          : int.tryParse('${data['version']}') ?? 0;
      final url = (data['url'] ?? '').toString();
      if (ver > kAppVersion && url.isNotEmpty) {
        // ⭐ v73: "Later" no longer silences the update — the dialog
        // comes back every single time the app is opened until the
        // user actually updates.
        LocalStore.remove('skip_update_ver');
        _updateUrl = url;
        _updateVer = ver;
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

  void _route() {
    if (!mounted) return;
    final store = context.read<AppStore>();
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _showUpdateDialog());
    }
    if (_updateUrl == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = rootNavKeyForUpdate;
        if (ctx != null) promptAutostartOnce(ctx);
      });
    }
  }

  /// ⭐ Update dialog — same dialog from the splash and the late retry.
  /// ⭐ v85: UPDATE starts a tracked in-app download with a live % bar,
  /// then opens the installer the moment the file lands (no waiting on
  /// the notification tray, no browser hop unless native download fails).
  void _showUpdateDialog() {
    final ctx = rootNavKeyForUpdate;
    if (ctx == null || _updateUrl == null || _updateDialogShown) return;
    _updateDialogShown = true;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(
        version: _updateVer,
        url: _updateUrl!,
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

/// ⭐ v85: in-app update sheet — live progress, then auto-install.
class _UpdateDialog extends StatefulWidget {
  final int version;
  final String url;
  const _UpdateDialog({required this.version, required this.url});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double _progress = 0; // 0..1, <0 = indeterminate / unknown
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
      // Native side already fires the installer; keep the sheet a beat.
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop();
      return;
    }
    // Fallback: open the URL externally (still better than nothing).
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
            onPressed: () => Navigator.of(context).pop(),
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
