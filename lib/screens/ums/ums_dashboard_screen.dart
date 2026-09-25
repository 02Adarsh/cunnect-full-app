import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../services/open_url.dart';
import '../pdf_viewer_screen.dart';
import '../../services/ums_file_pick.dart';
import '../../widgets/common.dart';
import 'ums_login_screen.dart';

/// Collegia/UMS dashboard — original dashboard.html ka poora mirror:
/// black + #EC1C24 theme, 8-tab footer strip (red active + underline),
/// attendance + course modal + PREDICT, live schedule badges, courses +
/// lecture-plan PDFs, results (semester dropdown + SGPA/CGPA + summary),
/// notices + files, fees (FY groups + LATEST + due hero), hostel,
/// profile (photo hero + ID card upload/viewer).
/// ⭐ percentage formatted like the portal: 62.62 -> '62.62', 60 -> '60'
String _pctStr(num v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class UmsDashboardScreen extends StatefulWidget {
  const UmsDashboardScreen({super.key});

  @override
  State<UmsDashboardScreen> createState() => _UmsDashboardScreenState();
}

class _UmsDashboardScreenState extends State<UmsDashboardScreen> {
  static const _red = Color(0xFFEC1C24);
  static const _reddim = Color(0x1AEC1C24);
  static const _hair = Color(0x17FFFFFF);
  static const _surface = Color(0xFF0F0F11);
  static const _muted = Color(0xFF87878D);
  static const _soft = Color(0xFFB7B7BC);
  static const _grn = Color(0xFF16A34A);
  static const _emerald = Color(0xFF10B981);

  static const _tabs = [
    ('\u25CD', 'ATTENDANCE'),
    ('\u25F7', 'SCHEDULE'),
    ('\u25A6', 'COURSES'),
    ('\u25A4', 'RESULTS'),
    ('\u2726', 'NOTICES'),
    ('\u20B9', 'FEES'),
    ('\u2302', 'HOSTEL'),
    ('\u25C9', 'PROFILE'),
  ];
  static const _tabW = 68.0;

  int _tab = 0;
  final PageController _pc = PageController();
  final Set<int> _openCourses = {};
  final Set<int> _openNotices = {};
  final Set<int> _openMarks = {};
  String? _selDay;
  DateTime _now = DateTime.now();
  Timer? _tick;
  Timer? _syncTimer;
  bool _alive = true;
  bool _semLoading = false;
  bool _idcBusy = false;
  AppStore? _store;
  bool _verifyOpen = false;
  double? _lastOverall;

  @override
  void initState() {
    super.initState();
    _store = context.read<AppStore>()..addListener(_onStore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ⭐ v62: opening the screen IS the trigger — cached data paints
      // instantly, the backend refreshes in the background, and the
      // early syncs below pull the fresh numbers in without any manual
      // refresh. No scraping ever happens while this screen is closed.
      _store?.loadUmsDashboard();
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) _sync();
      });
      Future.delayed(const Duration(seconds: 25), () {
        if (mounted) _sync();
      });
    });
    // ⭐ refresh the live badges every 30 sec (like the original updateLiveSchedule)
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // ⭐ realtime sync while the screen is OPEN — the ping endpoint reads
    // the server cache only (no portal hit), so this stays feather-light.
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => _sync());
  }

  @override
  void dispose() {
    _pc.dispose();
    _tick?.cancel();
    _syncTimer?.cancel();
    _store?.removeListener(_onStore);
    super.dispose();
  }

  /// ⭐ left/right swipe + tab tap sync
  void _goTab(int i) {
    if (_tab == i) return;
    setState(() => _tab = i);
    _pc.animateToPage(i,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  /// ⭐ ANY-NETWORK: portal captcha maange to "Verification Required" dialog.
  void _onStore() {
    final st = _store;
    if (st == null || !mounted) return;
    if (st.umsNeedsCaptcha && !_verifyOpen && st.umsCaptchaReady) {
      _verifyOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showVerifyDialog(st);
      });
    }
  }

  void _showVerifyDialog(AppStore st) {
    final ctrl = TextEditingController();
    bool busy = false;
    String? err;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final b64 = st.umsCaptchaB64 ?? '';
          if (!st.umsNeedsCaptcha) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            });
          }
          Future<void> verify() async {
            if (busy) return;
            setS(() {
              busy = true;
              err = null;
            });
            final res = await st.umsVerifyCaptcha(ctrl.text.trim());
            if (!mounted) return;
            if (res.containsKey('error')) {
              setS(() {
                busy = false;
                err = '${res['error']}';
              });
              await st.umsFetchCaptcha(); // wrong code -> new captcha
              ctrl.clear();
              if (mounted) setS(() {});
            } else {
              Navigator.of(ctx).pop();
            }
          }

          return Dialog(
            backgroundColor: const Color(0xFF101010),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Expanded(
                      child: Text('Verification Required',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700))),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                          color: Color(0xFF232327), shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          size: 16, color: Color(0xFF9d9d9d)),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Enter the text shown below to continue',
                      style: TextStyle(
                          color: Color(0xFF9d9d9d), fontSize: 12)),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 92,
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: b64.isEmpty
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Image.memory(base64Decode(b64),
                          fit: BoxFit.contain, height: 80),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  textAlign: TextAlign.center,
                  autocorrect: false,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      letterSpacing: 4,
                      fontFamily: 'monospace'),
                  onSubmitted: (_) => verify(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1D1D21),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 13),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: Color(0xFF2E2E33))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: Color(0xFF4A4A50))),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh,
                          size: 18, color: Color(0xFF9d9d9d)),
                      onPressed: () async {
                        await st.umsFetchCaptcha();
                        if (mounted) setS(() {});
                      },
                    ),
                  ),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(err!,
                        style: const TextStyle(
                            color: Color(0xFFf10b1d), fontSize: 11)),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: busy ? null : verify,
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : const Text('Verify  \u2713',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    ).then((_) {
      _verifyOpen = false;
      ctrl.dispose();
      // ⭐ closed without verifying -> 10 min cooldown (no popup every 2 min)
      if (st.umsNeedsCaptcha) st.markUmsCaptchaDismissed();
    });
  }

  Future<void> _sync() async {
    final store = context.read<AppStore>();
    if (store.umsUid == null) return;
    final ping = await store.umsPing();
    if (!mounted) return;
    if (ping == null) {
      if (_alive) setState(() => _alive = false);
    } else {
      store.applyUmsSync(ping);
      if (!_alive) setState(() => _alive = true);
    }
  }

  // ---------- helpers ----------
  String _s(dynamic v) => v?.toString() ?? '';
  double _n(dynamic v) {
    if (v is num) return v.toDouble();
    final t = _s(v).replaceAll(',', '').replaceAll('\u20B9', '').trim();
    return double.tryParse(t) ?? 0;
  }

  List<Map<String, dynamic>> _list(dynamic v) => v is List
      ? [
          for (final item in v)
            if (item is Map)
              item.map((k, x) => MapEntry(k.toString(), x)),
        ]
      : [];
  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? v.map((k, x) => MapEntry(k.toString(), x)) : {};

  Widget _mono(String text, double size,
          {Color color = Colors.white,
          FontWeight w = FontWeight.w700,
          bool ellipsize = false}) =>
      Text(text,
          maxLines: ellipsize ? 1 : null,
          overflow: ellipsize ? TextOverflow.ellipsis : null,
          style: TextStyle(
              fontFamily: 'monospace',
              fontSize: size,
              color: color,
              fontWeight: w,
              letterSpacing: .6));

  Widget _eyebrow(String text) => _mono(text.toUpperCase(), 9,
      color: _muted, w: FontWeight.w700);

  String _abs(String url) {
    if (url.isEmpty || url.startsWith('http')) return url;
    var full = ApiConfig.baseUrl + (url.startsWith('/') ? url : '/$url');
    // ⭐ v65 security: UMS media/PDF endpoints now require auth — these
    // URLs load via Image.network/browser (no headers), so the token
    // rides along as a query parameter instead.
    if (url.contains('/api/ums/')) {
      final tok = ApiConfig.studentToken ?? '';
      if (tok.isNotEmpty) {
        full += (full.contains('?') ? '&' : '?') + 'token=$tok';
      }
    }
    return full;
  }

  Future<void> _open(String url) async {
    final full = _abs(url);
    // ⭐ v59: UMS documents (lecture plans, datesheets, portal PDFs)
    // open INSIDE the app now — no browser redirect.
    final lower = Uri.parse(full).path.toLowerCase();
    if (full.contains('/api/ums/pdf/') || lower.endsWith('.pdf')) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
              url: full, title: 'Lecture Plan')));
      return;
    }
    final message = await openExternalUrl(full);
    if (mounted && message != null) showCunnectToast(context, message);
  }

  Widget _bar(double pct, {bool low = false}) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: (pct / 100).clamp(0.0, 1.0),
          minHeight: 5,
          backgroundColor: const Color(0x17FFFFFF),
          color: low ? _red : Colors.white,
        ),
      );

  /// Original .ledger card — left 2px red bar (mute = white/15 bar).
  /// Original .ledger — 2px red/white line card ke LEFT EDGE pe flush.
  Widget _ledger(List<Widget> children, {bool mute = false}) => Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hair),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 2,
                color: mute ? const Color(0x26FFFFFF) : _red,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _noData(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hair),
        ),
        child: Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 11.5)),
      );

  Widget _scroll(List<Widget> children) => RefreshIndicator(
        onRefresh: () => context.read<AppStore>().loadUmsDashboard(live: true),
        color: _red,
        backgroundColor: const Color(0xFF141416),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
          children: children,
        ),
      );

  Widget _title(String text, [String? subtitle]) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6)),
          const SizedBox(height: 10),
          Container(width: 26, height: 2, color: _red),
          if (subtitle != null) ...[
            const SizedBox(height: 10),
            Text(subtitle,
                style: const TextStyle(color: _muted, fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
        ],
      );

  // ---------- shell ----------
  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final data = store.umsDashboard;
    // ⭐ attendance update hui to notification + toast
    final ov = _n(data['overall_attendance']);
    if (ov > 0) {
      if (_lastOverall != null && (ov - _lastOverall!).abs() > 0.001) {
        final msg = 'Overall attendance is now ${_pctStr(ov)}%.';
        _lastOverall = ov;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          store.addLocalNotification('Attendance updated', msg);
          showCunnectToast(context, 'Attendance updated: $msg');
        });
      } else {
        _lastOverall = ov;
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (!_alive) _expiredBanner(store),
            _header(store, data),
            Expanded(
              child: data.isEmpty
                  ? _emptyState()
                  : PageView.builder(
                      controller: _pc,
                      itemCount: _tabs.length,
                      onPageChanged: (i) => setState(() => _tab = i),
                      itemBuilder: (c, i) => _panel(i, store, data),
                    ),
            ),
            _tabStrip(),
          ],
        ),
      ),
    );
  }

  Widget _expiredBanner(AppStore store) => const SizedBox.shrink();

  Widget _header(AppStore store, Map<String, dynamic> data) {
    final name = store.umsUserName;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.9),
        border: const Border(bottom: BorderSide(color: Color(0x17FFFFFF))),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0FEC1C24), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          const CunnectBrand(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: _hair),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _mono('UMS', 9, color: _muted),
          ),
          const SizedBox(width: 6),
          const Spacer(),
          // ⌂ back to the dashboard
          GestureDetector(
            onTap: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              child: Text('\u2302',
                  style: TextStyle(fontSize: 18, color: _soft)),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _goTab(7),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF151518),
                border: Border.all(color: _hair),
              ),
              child: _mono(name.isEmpty ? 'S' : name[0].toUpperCase(), 11,
                  color: _soft, w: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => const SizedBox.shrink();

  /// ⭐ FOOTER: 8-tab strip — red icon+label + top red underline glow
  /// (original #tab-strip mirror, horizontal scroll).
  Widget _tabStrip() => Container(
        color: Colors.black.withOpacity(.92),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Color(0x00EC1C24),
                        Color(0x73EC1C24),
                        Color(0x00EC1C24),
                      ]),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _tabW * _tabs.length,
                    child: Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          top: 0,
                          left: _tab * _tabW + 8,
                          width: _tabW - 16,
                          height: 2,
                          child: Container(color: _red),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < _tabs.length; i++)
                              SizedBox(
                                width: _tabW,
                                child: InkWell(
                                  onTap: () => _goTab(i),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(_tabs[i].$1,
                                          style: TextStyle(
                                              fontSize: 21,
                                              height: 1,
                                              color:
                                                  _tab == i ? _red : _muted,
                                              shadows: _tab == i
                                                  ? const [
                                                      Shadow(
                                                          color: Color(
                                                              0x66EC1C24),
                                                          blurRadius: 14)
                                                    ]
                                                  : null)),
                                      const SizedBox(height: 5),
                                      Text(_tabs[i].$2,
                                          style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 8,
                                              letterSpacing: 1,
                                              color: _tab == i
                                                  ? _red
                                                  : _muted,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _safePanel(String name, Widget Function() builder) {
    try {
      return builder();
    } catch (e) {
      return _scroll([
        _noData(
            '$name section could not be rendered.\n(${e.toString().length > 90 ? e.toString().substring(0, 90) : e})'),
      ]);
    }
  }

  Widget _panel(int tab, AppStore store, Map<String, dynamic> data) {
    // Only the selected panel is built + every panel is guarded —
    // one broken section cannot blank the whole screen.
    switch (tab) {
      case 0:
        return _safePanel('Attendance', () => _attendance(store, data));
      case 1:
        return _safePanel('Schedule', () => _timetable(data));
      case 2:
        return _safePanel('Courses', () => _courses(data));
      case 3:
        return _safePanel('Results', () => _results(store, data));
      case 4:
        return _safePanel('Notices', () => _notices(data));
      case 5:
        return _safePanel('Fees', () => _fees(data));
      case 6:
        return _safePanel('Hostel', () => _hostel(data));
      default:
        return _safePanel('Profile', () => _profile(store, data));
    }
  }

  // ---------- ATTENDANCE ----------
  Widget _attendance(AppStore store, Map<String, dynamic> data) {
    final overall = _n(data['overall_attendance']);
    final attended = _n(data['total_attended']);
    final held = _n(data['total_held']);
    final courses = _list(data['attendance']);
    final safe = overall >= 75;

    return _scroll([
      _title('Attendance'),
      _ledger([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _eyebrow('Aggregate'),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_pctStr(overall),
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 42,
                              fontWeight: FontWeight.w800,
                              height: 1)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 3),
                        child:
                            Text('%', style: TextStyle(fontSize: 18, color: _soft)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _mono(
                      '${attended.round()} / ${held.round()} CLASSES ATTENDED',
                      10,
                      color: _muted),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _eyebrow('Status'),
                const SizedBox(height: 5),
                Text(safe ? 'SAFE' : 'LOW',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: safe ? _emerald : _red)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _openPredict(data),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: _hair),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _mono('PREDICT \u2197', 9, color: _soft),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _bar(overall, low: !safe),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _mono('0%', 9, color: _muted),
            _mono('SAFE LINE \u00B7 75%', 9, color: _muted),
            _mono('100%', 9, color: _muted),
          ],
        ),
      ]),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _eyebrow('By course'),
          GestureDetector(
            onTap: () => store.loadUmsDashboard(live: true),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: _hair),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _mono('\u21BB SYNC', 9, color: _muted, w: FontWeight.w800),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (courses.isEmpty) _noData('No attendance records added yet.'),
      for (final c in courses) _courseAttCard(c, data),
    ]);
  }

  Widget _courseAttCard(Map<String, dynamic> c, Map<String, dynamic> data) {
    final pct = _n(c['percentage']);
    final low = pct < 75;
    final att = _n(c['attended']).round();
    final tot = _n(c['total']).round();
    final hasCounts = att > 0 || tot > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _openCourse(c, data),
        child: _ledger([
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow('Course'),
                    const SizedBox(height: 4),
                    Text(_s(c['title']).isEmpty ? 'Course' : _s(c['title']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _mono(_s(c['code']), 10, color: _muted),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: low ? _red : null,
                      border: Border.all(
                          color: low ? _red : const Color(0x40FFFFFF)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(low ? 'Low' : 'Safe',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: low ? Colors.white : _soft)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_pctStr(pct),
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              color: low ? _red : Colors.white)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Text('%',
                            style: TextStyle(fontSize: 12, color: _muted)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _bar(pct, low: low),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration:
                const BoxDecoration(border: Border(top: BorderSide(color: _hair))),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _mono('ATTENDED', 8, color: _muted),
                    const SizedBox(height: 4),
                    _mono(hasCounts ? '$att' : '\u2014', 15,
                        color: low ? _red : Colors.white,
                        w: FontWeight.w800),
                  ],
                ),
                const SizedBox(width: 28),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _mono('DELIVERED', 8, color: _muted),
                    const SizedBox(height: 4),
                    _mono(hasCounts ? '$tot' : '\u2014', 15,
                        color: _soft, w: FontWeight.w800),
                  ],
                ),
                if (_n(c['duty_leave']) > 0) ...[
                  const SizedBox(width: 28),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _mono('DUTY LEAVE', 8, color: _muted),
                      const SizedBox(height: 4),
                      _mono('${_n(c['duty_leave']).round()}', 15,
                          color: _soft, w: FontWeight.w800),
                    ],
                  ),
                ],
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _mono('DETAILS', 8, color: _muted),
                    const SizedBox(height: 4),
                    Text('\u2304',
                        style:
                            TextStyle(fontSize: 14, color: _muted, height: 1)),
                  ],
                ),
              ],
            ),
          ),
        ], mute: !low),
      ),
    );
  }

  /// ⭐ Course modal (original openCourse mirror) — ring + pill +
  /// Prediction / Timeline / Course Plan tabs.
  void _openCourse(Map<String, dynamic> c, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CourseSheet(
        course: c,
        timetable: _map(data['timetable']),
        onOpen: _open,
      ),
    );
  }

  // ---------- PREDICT ----------
  void _openPredict(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PredictSheet(
        attended: _n(data['total_attended']),
        held: _n(data['total_held']),
        overall: _n(data['overall_attendance']),
        records: _list(data['attendance']),
        timetable: _map(data['timetable']),
      ),
    );
  }

  // ---------- SCHEDULE ----------
  static const _dow = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

  String _todayKey() => _dow[DateTime.now().weekday % 7];

  /// The portal only gives the meridiem at the end ("11:20 - 12:10 PM") —
  /// exact Dart port of the original dashboard.html parseTimeRange.
  Map<String, int?> _parseTimeRange(String text) {
    int toMinutes(int h, int m, String? mer) {
      if (mer == 'PM' && h < 12) h += 12;
      else if (mer == 'AM' && h == 12) h = 0;
      else if (mer == null && h >= 1 && h <= 6) h += 12;
      return h * 60 + m;
    }

    String? mer(String t) {
      final c = t.replaceAll('.', '');
      if (c.contains('PM')) return 'PM';
      if (c.contains('AM')) return 'AM';
      return null;
    }

    final parts =
        text.toUpperCase().trim().split(RegExp(r'[-\u2013\u2014]|\bTO\b'));
    final re = RegExp(r'(\d{1,2})[:.](\d{2})');
    final sm = re.firstMatch(parts[0]);
    if (sm == null) return {'start': null, 'end': null};
    final sh = int.tryParse(sm.group(1)!) ?? 99;
    final smin = int.tryParse(sm.group(2)!) ?? 99;
    if (sh > 23 || smin > 59) return {'start': null, 'end': null};
    final startMer = mer(parts[0]);
    int? startMinutes;
    int? endMinutes;
    if (parts.length > 1) {
      final em = re.firstMatch(parts[1]);
      if (em != null) {
        final eh = int.tryParse(em.group(1)!) ?? 99;
        final emin = int.tryParse(em.group(2)!) ?? 99;
        if (eh <= 23 && emin <= 59) {
          final endMer = mer(parts[1]);
          endMinutes = toMinutes(eh, emin, endMer);
          if (startMer != null) {
            startMinutes = toMinutes(sh, smin, startMer);
          } else {
            for (final c in <String?>[endMer, null, 'AM', 'PM']) {
              final v = toMinutes(sh, smin, c);
              if (v <= endMinutes!) {
                startMinutes = v;
                break;
              }
            }
            startMinutes ??= endMinutes;
          }
        }
      }
    }
    startMinutes ??= toMinutes(sh, smin, startMer);
    endMinutes ??= startMinutes + 60;
    return {'start': startMinutes, 'end': endMinutes};
  }

  Widget _timetable(Map<String, dynamic> data) {
    final timetable = _map(data['timetable']);
    final days = timetable.keys.toList();
    if (days.isEmpty) {
      return _scroll([
        _title('Schedule', 'Current and upcoming lectures update automatically.'),
        _noData('Timetable not found.'),
      ]);
    }
    final today = _todayKey();
    final sel = (_selDay != null && timetable.containsKey(_selDay))
        ? _selDay!
        : (timetable.containsKey(today) ? today : days.first);
    final slots = _list(_map(timetable[sel])['slots']);
    final nowMinutes = _now.hour * 60 + _now.minute;

    // ⭐ ONGOING / UP NEXT / DONE — original updateLiveSchedule logic
    final doneIdx = <int>{};
    var liveIdx = -1;
    var nextIdx = -1;
    if (sel == today) {
      final cand = <List<int>>[];
      for (var i = 0; i < slots.length; i++) {
        final t = _parseTimeRange(_s(slots[i]['time']));
        final s = t['start'];
        final e = t['end'];
        if (s == null || e == null) continue;
        if (nowMinutes >= e) {
          doneIdx.add(i);
          continue;
        }
        cand.add([i, s]);
      }
      cand.sort((a, b) => a[1].compareTo(b[1]));
      if (cand.isNotEmpty) {
        if (nowMinutes >= cand.first[1]) {
          liveIdx = cand.first[0];
        } else {
          nextIdx = cand.first[0];
        }
      }
    }

    // slots time se sorted (original sortScheduleSlotsByTime)
    final order = [for (var i = 0; i < slots.length; i++) i];
    order.sort((a, b) => (_parseTimeRange(_s(slots[a]['time']))['start'] ?? 1 << 30)
        .compareTo(_parseTimeRange(_s(slots[b]['time']))['start'] ?? 1 << 30));

    return _scroll([
      _title('Schedule', 'Current and upcoming lectures update automatically.'),
      SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: days.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final d = days[i];
            final on = d == sel;
            return GestureDetector(
              onTap: () => setState(() => _selDay = d),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: on ? Colors.white : null,
                  border: Border.all(color: on ? Colors.white : _hair),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(d,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 1.2,
                        color: on ? Colors.black : _muted,
                        fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 28),
      Text(_s(_map(timetable[sel])['full_day']).isEmpty
          ? sel
          : _s(_map(timetable[sel])['full_day']),
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: .2)),
      Container(
          width: 24, height: 2, color: _red,
          margin: const EdgeInsets.only(top: 8)),
      const SizedBox(height: 8),
      _mono('${slots.length} SESSIONS', 9, color: _muted),
      const SizedBox(height: 16),
      if (slots.isEmpty) _noData('No lectures scheduled for this day.'),
      for (final i in order)
        _slotCard(slots[i],
            status: i == liveIdx
                ? 2
                : i == nextIdx
                    ? 1
                    : doneIdx.contains(i)
                        ? 0
                        : -1),
    ]);
  }

  /// status: 2 = ONGOING, 1 = UP NEXT, 0 = DONE, -1 = normal
  Widget _slotCard(Map<String, dynamic> slot, {int status = -1}) {
    final practical = _s(slot['type']).toUpperCase().contains('PRAC');
    final done = status == 0;
    final live = status == 2;
    final next = status == 1;
    return Opacity(
      opacity: done ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: live ? const Color(0x8CEC1C24) : _hair),
            boxShadow: live
                ? const [
                    BoxShadow(
                        color: Color(0x40EC1C24),
                        blurRadius: 30,
                        offset: Offset(0, 10)),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: live ? 4 : 2,
                  color: live
                      ? _red
                      : done
                          ? const Color(0x2EFFFFFF)
                          : const Color(0x26FFFFFF),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: practical ? _reddim : null,
                            border: Border.all(
                                color: practical
                                    ? const Color(0x4DEC1C24)
                                    : const Color(0x40FFFFFF)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                              _s(slot['type']).isEmpty
                                  ? 'LECTURE'
                                  : _s(slot['type']).toUpperCase(),
                              style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: practical ? _red : _soft)),
                        ),
                        const Spacer(),
                        if (status >= 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: next ? const Color(0xFF3A3A3A) : _red,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                    color: (next
                                            ? const Color(0xFF3A3A3A)
                                            : _red)
                                        .withOpacity(.5),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Text(
                                status == 2
                                    ? 'ONGOING'
                                    : status == 1
                                        ? 'UP NEXT'
                                        : 'DONE',
                                style: const TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: Colors.white)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(_s(slot['title']),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _red)),
                    const SizedBox(height: 4),
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: _s(slot['teacher']),
                          style:
                              const TextStyle(color: _muted, fontSize: 12)),
                      TextSpan(
                          text: ' · ${_s(slot['code'])}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              color: _muted,
                              fontSize: 11)),
                    ])),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.only(top: 10),
                      decoration: const BoxDecoration(
                          border:
                              Border(top: BorderSide(color: _hair))),
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 6,
                        children: [
                          _mono('\u25f7 ${_s(slot['time'])}', 10.5,
                              color: _soft),
                          _mono('\u2316 ${_s(slot['room'])}', 10.5,
                              color: _soft),
                        ],
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- COURSES ----------
  Widget _courses(Map<String, dynamic> data) {
    final plan = _map(data['course_plan']);
    final pagePdfs = _list(plan['page_pdfs']);
    final courses = _list(plan['courses']);
    return _scroll([
      _title('My Courses',
          'All your subjects · lecture plan opens as official PDF. Tap a course.'),
      if (pagePdfs.isNotEmpty) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _eyebrow('Lecture Plan PDFs'),
            _mono('OFFICIAL', 9, color: _muted),
          ],
        ),
        const SizedBox(height: 10),
        for (final p in pagePdfs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => _open(_s(p['view_url'])),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _hair),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_s(p['label']),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _mono('PDF ↗', 9, color: Colors.white, w: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
      ],
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _eyebrow('This Semester'),
          _mono('${courses.length} COURSES', 9, color: _muted),
        ],
      ),
      const SizedBox(height: 10),
      if (courses.isEmpty)
        _noData('No Course Plan Found — no plan uploaded to the portal yet.'),
      for (var i = 0; i < courses.length; i++) _courseCard(i, courses[i]),
    ]);
  }

  Widget _courseCard(int index, Map<String, dynamic> c) {
    final open = _openCourses.contains(index);
    final planUrl = _s(c['plan_view_url']);
    final plans = _list(c['plan']);
    final meta = [for (final m in c['meta'] ?? const []) _s(m)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() =>
                  open ? _openCourses.remove(index) : _openCourses.add(index)),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_s(c['title']).isEmpty ? 'Course' : _s(c['title']),
                              style: const TextStyle(
                                  fontSize: 15.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          _mono(_s(c['code']), 9.5, color: _muted),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final m in meta)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: _hair),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: _mono(m, 8, color: _soft),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(open ? '⌃' : '⌄',
                        style: const TextStyle(fontSize: 14, color: _muted)),
                  ],
                ),
              ),
            ),
            if (open)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _hair)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (planUrl.isNotEmpty) ...[
                      InkWell(
                        onTap: () => _open(planUrl),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            color: _red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _mono('▤ LECTURE PLAN · OPEN PDF', 10,
                                  color: Colors.white, w: FontWeight.w800),
                              _mono('↗', 13, color: Colors.white, w: FontWeight.w800),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _mono('OFFICIAL PORTAL PDF · NEW TAB', 8, color: _muted),
                    ],
                    if (plans.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _eyebrow('Lecture Plan'),
                      const SizedBox(height: 10),
                      for (final sec in plans)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0x4D000000),
                              border: Border.all(color: _hair),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                for (final row in _list2(sec['rows']))
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      border: Border(
                                          bottom: BorderSide(
                                              color: _hair.withOpacity(.6))),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (var ci = 0;
                                            ci < row.length;
                                            ci++)
                                          Expanded(
                                            flex: ci == 0 ? 2 : 3,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.only(right: 8),
                                              child: Text(_s(row[ci]),
                                                  style: TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 10.5,
                                                      color: ci == 0
                                                          ? _muted
                                                          : Colors.white)),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (planUrl.isEmpty && plans.isEmpty)
                      const Text(
                          'No lecture plan on the portal yet for this course (faculty upload may be pending).',
                          style: TextStyle(
                              color: _muted, fontSize: 11.5, height: 1.5)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<List<dynamic>> _list2(dynamic v) =>
      v is List ? [for (final r in v) if (r is List) r] : [];

  // ---------- RESULTS ----------
  String _semLabel(String sem) {
    final m = RegExp(r'Semester\s*(\d+)', caseSensitive: false).firstMatch(sem);
    if (m != null) return 'Sem ${m.group(1)}';
    return sem.isEmpty ? 'SEM' : sem.toUpperCase();
  }

  Future<void> _switchSemester(AppStore store, String id) async {
    if (_semLoading) return;
    setState(() => _semLoading = true);
    final okk = await store.umsSwitchSemester(id);
    if (!mounted) return;
    setState(() => _semLoading = false);
    if (!okk) {
      showCunnectToast(context, 'Semester could not be loaded — try again later');
    }
  }

  Widget _results(AppStore store, Map<String, dynamic> data) {
    final sessions = _list(data['available_sessions']);
    final results = _list(data['exam_results']);
    final marks = _list(data['marks']);
    final flat = _list(data['subject_grades']);
    final sgpa = _s(data['active_sgpa']).isEmpty ? '0.00' : _s(data['active_sgpa']);
    final cgpa = _s(data['student_cgpa']).isEmpty ? '0.00' : _s(data['student_cgpa']);
    final totalCredits = _n(data['total_credits']).round();
    final pending = data['result_pending'] == true;
    final selected = sessions.firstWhere(
        (s) => s['selected'] == true || _s(s['id']) == _s(data['active_session']),
        orElse: () => (sessions.isNotEmpty ? sessions.first : const {}));

    return _scroll([
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _title(
                'Results', 'Official semester grade sheets and SGPAs.'),
          ),
          if (sessions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: PopupMenuButton<String>(
                offset: const Offset(0, 44),
                color: const Color(0xFF18181B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: _hair)),
                onSelected: (id) => _switchSemester(store, id),
                itemBuilder: (_) => [
                  for (final s in sessions)
                    PopupMenuItem<String>(
                      value: _s(s['id']),
                      height: 40,
                      child: _mono(
                          '${_s(s['name']).toUpperCase()}${s['pending'] == true ? ' \u00B7 PENDING' : ''}',
                          10,
                          color: s['pending'] == true ? _red : Colors.white),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    border: Border.all(color: _hair),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_semLoading)
                        const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: _red))
                      else
                        _mono(_semLabel(_s(selected['name'])), 10,
                            w: FontWeight.w900),
                      const SizedBox(width: 6),
                      _mono('\u2304', 10, color: _muted),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      // ── Grade sheet hero ──
      _ledger([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⭐ v53: UID text removed at the user's request
                  const Text('End Semester Examination',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.25)),
                  const SizedBox(height: 4),
                  const Text('Academic Grade Sheet Summary',
                      style: TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _eyebrow('Sgpa'),
                const SizedBox(height: 4),
                Text(sgpa,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1)),
                const SizedBox(height: 12),
                _eyebrow('Cgpa'),
                const SizedBox(height: 4),
                Text(cgpa,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: _red)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.only(top: 14),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _hair))),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _eyebrow('Result'),
                  const SizedBox(height: 4),
                  _mono('PASS', 14, w: FontWeight.w600),
                ],
              ),
              const SizedBox(width: 40),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _eyebrow('Status'),
                  const SizedBox(height: 4),
                  _mono('GOOD', 14, color: _emerald, w: FontWeight.w600),
                ],
              ),
            ],
          ),
        ),
      ]),
      // ── SGPA history ──
      if (results.isNotEmpty) ...[
        const SizedBox(height: 22),
        _eyebrow('SGPA History'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final res in results)
              SizedBox(
                width: 104,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _surface,
                    border: Border.all(color: _hair),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(_semLabel(_s(res['semester'])),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              letterSpacing: 1,
                              color: _muted,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(_s(res['sgpa']).isEmpty ? '\u2014' : _s(res['sgpa']),
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      _mono('SGPA', 8, color: _muted),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
      // ── Sessional marks ──
      const SizedBox(height: 22),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _eyebrow('Sessional Marks'),
      ),
      if (marks.isNotEmpty)
        for (var i = 0; i < marks.length; i++)
          _sessionalCard(i, marks[i])
      else if (flat.isNotEmpty)
        _gradesTable(flat)
      else
        _ledger([
          const Center(
            child: Text('No Sessional Marks Declared',
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Center(
            child: _mono('UMS \u00B7 ARCHIVED OR UNDECLARED RECORDS', 9,
                color: _muted),
          ),
        ], mute: true),
      // ── Subject breakdown ──
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _eyebrow('Subject breakdown'),
      ),
      if (flat.isEmpty && pending)
        _ledger([
          const Center(
            child: Text('Result Not Declared Yet',
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
                'This semester\'s result is not on the portal yet \u2014 it will appear here as soon as it is declared.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _muted, fontSize: 10.5, height: 1.5)),
          ),
        ], mute: true)
      else if (flat.isEmpty)
        _noData('No results added yet.'),
      for (final sub in flat) _gradeCard(sub),
      // ── Semester summary ──
      if (flat.isNotEmpty) ...[
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _eyebrow('Semester summary'),
        ),
        _summaryTable(flat, totalCredits, sgpa),
      ],
    ]);
  }

  Widget _sessionalCard(int index, Map<String, dynamic> item) {
    final open = _openMarks.contains(index);
    final rows = _list(item['marks']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _ledger([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _mono(_s(item['code']), 9, color: _muted),
                  const SizedBox(height: 4),
                  Text(
                      _s(item['title']).isEmpty
                          ? _s(item['code'])
                          : _s(item['title']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => open
                  ? _openMarks.remove(index)
                  : _openMarks.add(index)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: _hair),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _mono(open ? 'VIEW MARKS \u2303' : 'VIEW MARKS \u2304', 9,
                    color: _muted, w: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (open) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _hair))),
            child: rows.isEmpty
                ? _mono('No marks declared for this subject yet.', 11,
                    color: _muted)
                : Column(
                    children: [
                      for (final m in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_s(m['element']),
                                  style: const TextStyle(
                                      color: _soft,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              Text.rich(TextSpan(children: [
                                TextSpan(
                                    text: _s(m['obtained']),
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13)),
                                TextSpan(
                                    text: '/${_s(m['total'])}',
                                    style: TextStyle(
                                        fontFamily: 'monospace',
                                        color: _muted,
                                        fontSize: 11)),
                              ])),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ], mute: true),
    );
  }

  String _gradeVal(Map<String, dynamic> sub, String key) {
    final v = sub[key];
    if (v == null || _s(v).isEmpty) return '\u2014';
    return _s(v);
  }

  Widget _gradesTable(List<Map<String, dynamic>> flat) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _surface,
          border: Border.all(color: _hair),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _hair))),
              child: Row(
                children: [
                  Expanded(child: _eyebrow('Subject')),
                  SizedBox(
                      width: 76,
                      child: Align(
                          alignment: Alignment.centerRight,
                          child: _eyebrow('Internal'))),
                  SizedBox(
                      width: 76,
                      child: Align(
                          alignment: Alignment.centerRight,
                          child: _eyebrow('External'))),
                ],
              ),
            ),
            for (var i = 0; i < flat.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    border: i < flat.length - 1
                        ? const Border(bottom: BorderSide(color: _hair))
                        : null),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _s(flat[i]['subject']).isEmpty
                                    ? _s(flat[i]['title'])
                                    : _s(flat[i]['subject']),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            _mono(_s(flat[i]['code']), 8, color: _muted),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                        width: 76,
                        child: Align(
                            alignment: Alignment.centerRight,
                            child: _mono(_gradeVal(flat[i], 'internal'), 13,
                                w: FontWeight.w800))),
                    SizedBox(
                        width: 76,
                        child: Align(
                            alignment: Alignment.centerRight,
                            child: _mono(_gradeVal(flat[i], 'external'), 13,
                                color: _soft))),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _mono(
                  'SOURCE \u00B7 RESULT.ASPX RECORDS (SESSIONAL PAGE ARCHIVED)',
                  8,
                  color: _muted),
            ),
          ],
        ),
      );

  Widget _gradeCard(Map<String, dynamic> sub) {
    final score = _n(sub['score']);
    final hasMarks = _s(sub['internal']).isNotEmpty || _s(sub['external']).isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _ledger([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _mono(_s(sub['code']), 9, color: _muted),
                  const SizedBox(height: 4),
                  Text(
                      _s(sub['subject']).isEmpty
                          ? _s(sub['title'])
                          : _s(sub['subject']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  _mono('CREDITS: ${_gradeVal(sub, 'credits')}', 9,
                      color: _muted),
                  if (hasMarks) ...[
                    const SizedBox(height: 3),
                    _mono(
                        'INT: ${_gradeVal(sub, 'internal')} \u00B7 EXT: ${_gradeVal(sub, 'external')}',
                        9,
                        color: _soft),
                  ],
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _mono('SCORE', 8, color: _muted),
                    const SizedBox(height: 4),
                    Text(_gradeVal(sub, 'score'),
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(width: 22),
                Column(
                  children: [
                    _mono('GRADE', 8, color: _muted),
                    const SizedBox(height: 4),
                    Text(_gradeVal(sub, 'grade'),
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _red)),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _bar(score),
      ], mute: true),
    );
  }

  Widget _summaryTable(List<Map<String, dynamic>> flat, int credits,
          String sgpa) =>
      LayoutBuilder(
        builder: (context, constraints) {
          // ⭐ overflow-x table like the original: horizontal scroll on narrow
          // screens, fixed-width columns — numbers never wrap/mix.
          const codeW = 96.0;
          const intW = 54.0;
          const extW = 54.0;
          const crW = 40.0;
          const grW = 56.0;
          final inner =
              constraints.maxWidth < 620 ? 620.0 : constraints.maxWidth;
          Widget num(String text, double w,
                  {Color color = const Color(0xFFB7B7BC),
                  FontWeight fw = FontWeight.w700}) =>
              SizedBox(
                width: w,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: color,
                          fontWeight: fw)),
                ),
              );
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _surface,
              border: Border.all(color: _hair),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: inner,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: _hair))),
                      child: Row(
                        children: [
                          Expanded(child: _eyebrow('Subject')),
                          SizedBox(
                              width: codeW,
                              child: Center(child: _eyebrow('Code'))),
                          SizedBox(
                              width: intW,
                              child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _eyebrow('Int'))),
                          SizedBox(
                              width: extW,
                              child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _eyebrow('Ext'))),
                          SizedBox(
                              width: crW,
                              child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _eyebrow('Cr'))),
                          SizedBox(
                              width: grW,
                              child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _eyebrow('Grade'))),
                        ],
                      ),
                    ),
                    for (var i = 0; i < flat.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: const BoxDecoration(
                            border:
                                Border(bottom: BorderSide(color: _hair))),
                        child: Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Text(
                                    _s(flat[i]['subject']).isEmpty
                                        ? _s(flat[i]['title'])
                                        : _s(flat[i]['subject']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ),
                            SizedBox(
                                width: codeW,
                                child: Text(_s(flat[i]['code']),
                                    maxLines: 1,
                                    style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        color: _muted))),
                            num(_gradeVal(flat[i], 'internal'), intW,
                                color: _soft),
                            num(_gradeVal(flat[i], 'external'), extW,
                                color: _soft),
                            num(_gradeVal(flat[i], 'credits'), crW,
                                color: _soft),
                            num(_gradeVal(flat[i], 'grade'), grW,
                                color: Colors.white, fw: FontWeight.w800),
                          ],
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: const BoxDecoration(
                          border: Border(
                              top: BorderSide(color: Color(0x33FFFFFF)))),
                      child: Row(
                        children: [
                          Expanded(
                            child: _mono('TOTAL', 11,
                                color: _muted, w: FontWeight.w800),
                          ),
                          SizedBox(width: codeW + intW + extW),
                          SizedBox(
                              width: crW,
                              child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _mono('$credits', 12,
                                      w: FontWeight.w800))),
                          SizedBox(
                              width: grW,
                              child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _mono(sgpa, 12,
                                      color: _red, w: FontWeight.w800))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  // ---------- NOTICES ----------
  Widget _notices(Map<String, dynamic> data) {
    final notices = _list(data['notices']);
    return _scroll([
      _title('Notices', 'Academic announcements and reminders.'),
      if (notices.isEmpty) _noData('No notices available.'),
      for (var i = 0; i < notices.length; i++) _noticeCard(i, notices[i]),
    ]);
  }

  Widget _noticeCard(int index, Map<String, dynamic> n) {
    final full = _openNotices.contains(index);
    final desc = _s(n['desc']);
    final files = _list(n['files']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card([
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _reddim,
                borderRadius: BorderRadius.circular(20),
              ),
              child: _mono(
                  (_s(n['department']).isEmpty
                          ? 'University'
                          : _s(n['department']))
                      .toUpperCase(),
                  8,
                  color: _red,
                  w: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            _mono(_s(n['date']), 9, color: _muted),
          ],
        ),
        const SizedBox(height: 10),
        Text(_s(n['title']),
            style:
                const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35)),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(full ? desc : (desc.length > 150 ? '${desc.substring(0, 150)}…' : desc),
              style:
                  const TextStyle(color: _muted, fontSize: 12, height: 1.5)),
          GestureDetector(
            onTap: () => setState(() => full
                ? _openNotices.remove(index)
                : _openNotices.add(index)),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _mono(full ? 'CLOSE ⌃' : 'FULL NOTICE ⌄', 9,
                  color: _soft, w: FontWeight.w800),
            ),
          ),
        ],
        if (files.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration:
                const BoxDecoration(border: Border(top: BorderSide(color: _hair))),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in files)
                  GestureDetector(
                    onTap: () => _open(_s(f['url'])),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _reddim,
                        border: Border.all(color: const Color(0x66EC1C24)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _mono('↓ ${_s(f['name'])}', 9,
                          color: _red, w: FontWeight.w800),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ]),
    );
  }


  /// ⭐ Indian numeric system: 1234567 -> 12,34,567
  String _inr(num n) {
    final neg = n < 0;
    var v = n.abs().toStringAsFixed(0);
    if (v.length > 3) {
      final last3 = v.substring(v.length - 3);
      var rest = v.substring(0, v.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      v = '${parts.join(',')},$last3';
    }
    return '${neg ? '-' : ''}$v';
  }

  // ---------- FEES ----------
  Widget _fees(Map<String, dynamic> data) {
    final summary = _map(data['fee_summary']);
    final records = _list(data['fee_records']);
    final hasMoney =
        summary['has_money'] == true || _n(summary['total']) > 0;
    final cleared = summary['cleared'] == true;
    final allPaid = summary['all_paid'] == true;
    final due = _n(summary['due']);
    final receiptCount = _n(summary['receipt_count']).isFinite
        ? _n(summary['receipt_count']).round()
        : records.length;
    final latest = _s(summary['latest']);

    // ⭐ FY grouping (original {% regroup fee_records by semester %})
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final f in records) {
      final fy = _s(f['semester']).isEmpty ? 'ALL' : _s(f['semester']);
      groups.putIfAbsent(fy, () => []).add(f);
    }
    var latestShown = false;

    return _scroll([
      _title('Fees', 'Fee summary, dues and payment history.'),
      // ── Hero ──
      if (hasMoney)
        _ledger([
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow('Remaining Fee'),
                    const SizedBox(height: 8),
                    Text('\u20B9${_inr(due)}',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: cleared ? Colors.white : _red)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _eyebrow('Status'),
                  const SizedBox(height: 5),
                  Text(cleared ? 'CLEAR' : 'DUE',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: cleared ? _emerald : _red)),
                ],
              ),
            ],
          ),
        ])
      else if (allPaid)
        _ledger([
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow('Due Fee'),
                    const SizedBox(height: 8),
                    const Text('\u20B90',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            height: 1)),
                    const SizedBox(height: 8),
                    _mono(
                        '$receiptCount RECEIPTS${latest.isNotEmpty ? ' \u00B7 LATEST PAYMENT $latest' : ''}',
                        10,
                        color: _muted),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _eyebrow('Status'),
                  const SizedBox(height: 5),
                  Text('FULLY PAID',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _emerald)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _bar(100),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _mono('0%', 9, color: _muted),
              _mono('PAID \u00B7 100%', 9,
                  color: Colors.white, w: FontWeight.w800),
              _mono('100%', 9, color: _muted),
            ],
          ),
        ])
      else
        _ledger([
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow('Fee Receipts'),
                    const SizedBox(height: 8),
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '$receiptCount',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 42,
                              fontWeight: FontWeight.w800,
                              height: 1)),
                      TextSpan(
                          text: ' total',
                          style: TextStyle(fontSize: 16, color: _soft)),
                    ])),
                    const SizedBox(height: 8),
                    _mono(
                        latest.isNotEmpty
                            ? 'LATEST PAYMENT \u00B7 $latest'
                            : 'PORTAL RECEIPT LIST',
                        10,
                        color: _muted),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _eyebrow('Mode'),
                  const SizedBox(height: 5),
                  _mono('OFFICIAL', 14, w: FontWeight.w800),
                  const SizedBox(height: 3),
                  _mono('RECEIPT PDFs', 9, color: _red),
                ],
              ),
            ],
          ),
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in groups.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _reddim,
                      border: Border.all(color: const Color(0x4DEC1C24)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _mono('FY ${g.key} \u00B7 ${g.value.length}', 9,
                        color: _red, w: FontWeight.w800),
                  ),
              ],
            ),
          ],
        ]),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _eyebrow('Payment history'),
          _mono('TAP \u2193 PDF', 9, color: _muted),
        ],
      ),
      const SizedBox(height: 12),
      if (records.isEmpty) _noData('No fee records available yet.'),
      for (var gi = 0; gi < groups.length; gi++) ...[
        if (gi > 0) const SizedBox(height: 20),
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _reddim,
                border: Border.all(color: const Color(0x4DEC1C24)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _mono('FY ${groups.keys.elementAt(gi)}', 9,
                  color: _red, w: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Container(
                    height: 1, color: const Color(0x1AFFFFFF))),
            const SizedBox(width: 10),
            _mono('${groups.values.elementAt(gi).length} RECEIPTS', 9,
                color: _muted),
          ],
        ),
        const SizedBox(height: 12),
        for (final f in groups.values.elementAt(gi)) ...[
          Builder(builder: (_) {
            final isFirst = gi == 0 && !latestShown;
            if (isFirst) latestShown = true;
            return _receiptCard(f, showLatest: isFirst);
          }),
        ],
      ],

    ]);
  }

  Widget _receiptCard(Map<String, dynamic> f, {bool showLatest = false}) {
    final url = _s(f['receipt_url']);
    final status = _s(f['status']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _ledger([
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _reddim,
                border: Border.all(color: const Color(0x4DEC1C24)),
              ),
              child: _mono('\u25A4', 13, color: _red, w: FontWeight.w800),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                            _s(f['receipt']).isEmpty
                                ? _s(f['title'])
                                : _s(f['receipt']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      if (showLatest) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _mono('LATEST', 8,
                              color: Colors.white, w: FontWeight.w800),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '\u25F7 ${_s(f['date'])}',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            color: _muted,
                            fontSize: 10)),
                    if (status.isNotEmpty)
                      TextSpan(
                          text: ' \u00B7 $status',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: status.toUpperCase() == 'PAID'
                                  ? _grn
                                  : _red)),
                  ])),
                ],
              ),
            ),
            if (_n(f['amount']) > 0) ...[
              Text('\u20B9${_inr(_n(f['amount']))}',
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
            ],
            if (url.isNotEmpty)
              GestureDetector(
                onTap: () => _open(url),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _mono('\u2193 PDF', 10,
                      color: Colors.white, w: FontWeight.w800),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: _hair),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _mono('NO LINK', 9, color: _muted),
              ),
          ],
        ),
      ]),
    );
  }

  // ---------- HOSTEL ----------
  /// ⭐ v53: left-aligned key/value ledger (hostel section) — every
  /// label + value pair sits flush left in a symmetric ordered column.
  Widget _kvRowsLeft(List<Map<String, dynamic>> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              width: double.infinity,
              padding:
                  EdgeInsets.only(bottom: i < rows.length - 1 ? 12 : 0),
              margin:
                  EdgeInsets.only(bottom: i < rows.length - 1 ? 12 : 0),
              decoration: BoxDecoration(
                  border: i < rows.length - 1
                      ? const Border(bottom: BorderSide(color: _hair))
                      : null),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _mono(_s(rows[i]['label']).toUpperCase(), 8.5,
                      color: _muted, w: FontWeight.w800),
                  const SizedBox(height: 5),
                  Text(
                      _s(rows[i]['value']).isEmpty
                          ? '\u2014'
                          : _s(rows[i]['value']),
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4)),
                ],
              ),
            ),
        ],
      );

  Widget _kvRows(List<Map<String, dynamic>> rows) => Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: EdgeInsets.only(
                  bottom: i < rows.length - 1 ? 10 : 0),
              margin: EdgeInsets.only(bottom: i < rows.length - 1 ? 10 : 0),
              decoration: BoxDecoration(
                  border: i < rows.length - 1
                      ? const Border(bottom: BorderSide(color: _hair))
                      : null),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(_s(rows[i]['label']),
                        style:
                            const TextStyle(color: _muted, fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                        _s(rows[i]['value']).isEmpty
                            ? '\u2014'
                            : _s(rows[i]['value']),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      );

  /// Section rows — both kv (dicts) and portal-table (list of lists) shapes.
  List<dynamic> _secRows(dynamic node) {
    final m = _map(node);
    final kv = m['kv'];
    if (kv is List && kv.isNotEmpty) return kv;
    final rows = m['rows'];
    if (rows is List && rows.isNotEmpty) return rows;
    return [];
  }

  Widget _tableSection(Map<String, dynamic> sec,
      {EdgeInsetsGeometry margin = EdgeInsets.zero}) {
    final flat = _secRows(sec);
    if (flat.isEmpty) return const SizedBox.shrink();
    List? header;
    var rows = flat;
    if (flat.length > 1 && flat[0] is List && flat[1] is List) {
      header = flat[0] as List;
      rows = flat.sublist(1);
    }
    return Container(
      margin: margin,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _hair),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                  border: i < rows.length - 1
                      ? const Border(bottom: BorderSide(color: _hair))
                      : null),
              child: _tableRowCells(rows[i], header),
            ),
        ],
      ),
    );
  }

  Widget _tableRowCells(dynamic row, [List? header]) {
    if (row is Map) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(_s(row['label']),
                style: const TextStyle(color: _muted, fontSize: 12)),
          ),
          Flexible(
            child: Text(_s(row['value']).isEmpty ? '\u2014' : _s(row['value']),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      );
    }
    final cells = row is List ? row : [row];
    // ⭐ 3+ column rows: stacked card style — readable like before, no clipping
    if (cells.length > 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_s(cells[0]),
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          for (var i = 1; i < cells.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                        header != null && i < header.length
                            ? _s(header[i])
                            : '',
                        style:
                            const TextStyle(color: _muted, fontSize: 10.5)),
                  ),
                  Expanded(
                    child: Text(_s(cells[i]),
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            height: 1.45)),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var ci = 0; ci < cells.length; ci++)
          Expanded(
            flex: ci == 0 ? 3 : 4,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(_s(cells[ci]),
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: ci == 0 ? _muted : Colors.white)),
            ),
          ),
      ],
    );
  }

  Widget _hostel(Map<String, dynamic> data) {
    final hostel = _map(data['hostel_details']);
    final found = hostel.isNotEmpty && hostel['found'] != false;
    final kv = _list(hostel['kv']);
    final sections = _list(hostel['sections']);
    final nothing = kv.isEmpty && sections.every((s) => _secRows(s).isEmpty);

    return _scroll([
      _title('Hostel', 'Room, allotment and hostel details from the portal.'),
      if (!found)
        _ledger([
          const Center(
            child: Text('No Hostel Data Found',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
                'No hostel page link found in the portal\'s Student Home menu.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _muted, fontSize: 11, height: 1.5)),
          ),
        ], mute: true)
      else if (nothing)
        _noData(
            'Hostel page was found, but no readable details could be extracted.')
      else ...[
        if (kv.isNotEmpty)
          _ledger([
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _eyebrow('My Hostel'),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _reddim,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _mono('PORTAL', 8, color: _red, w: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ⭐ v53: left-aligned ledger — label above value, both
            // flush to the left edge in one clean ordered column.
            _kvRowsLeft(kv),
          ]),
        for (final sec in sections)
          if (_secRows(sec).isNotEmpty) ...[
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _eyebrow(
                    _s(sec['heading']).isEmpty ? 'Details' : _s(sec['heading'])),
                _mono('${_secRows(sec).length} ROWS', 9, color: _muted),
              ],
            ),
            const SizedBox(height: 10),
            _tableSection(sec),
          ],
      ],
    ]);
  }

  // ---------- PROFILE ----------
  Widget _profile(AppStore store, Map<String, dynamic> data) {
    final profile = _map(data['student_profile']);
    final found = profile.isNotEmpty && profile['found'] != false;
    final kv = _list(profile['kv']);
    final sections = _list(profile['sections']);
    final name =
        _s(profile['name']).isEmpty ? store.umsUserName : _s(profile['name']);
    final uid = _s(data['uid']);
    final hasPhoto = profile['has_photo'] == true;
    final idcV = store.umsIdCardV ?? _n(data['id_card_v']).round();
    final hasIdc = idcV > 0;

    return _scroll([
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _title('Profile',
                'Your official student record from the portal.'),
          ),
          GestureDetector(
            onTap: () => store.loadUmsDashboard(live: true),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: _hair),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _mono('\u21BB SYNC', 9, color: _muted, w: FontWeight.w800),
            ),
          ),
        ],
      ),
      if (!found)
        _ledger([
          const Center(
            child: Text('No Profile Data Found',
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
                'The portal\'s Student Profile page came back empty or failed to parse.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 11, height: 1.5)),
          ),
        ], mute: true)
      else ...[
        // ── Identity hero ──
        _ledger([
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF151518),
                  border: Border.all(color: _hair),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Text(
                          name.isEmpty ? 'S' : name[0].toUpperCase(),
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: _red)),
                    ),
                    if (hasPhoto)
                      Image.network(_abs('/api/ums/photo/?uid=$uid'),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink()),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow('Student'),
                    const SizedBox(height: 4),
                    Text(name.isEmpty ? '\u2014' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _reddim,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _mono('OFFICIAL', 8, color: _red, w: FontWeight.w800),
              ),
            ],
          ),
        ]),
        if (kv.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _eyebrow('Details'),
              _mono('${kv.length} FIELDS', 9, color: _muted),
            ],
          ),
          const SizedBox(height: 10),
          _ledger([_kvRows(kv)]),
        ],
        for (final sec in sections)
          if (_secRows(sec).isNotEmpty) ...[
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _eyebrow(_s(sec['heading']).isEmpty
                    ? 'Details'
                    : _s(sec['heading'])),
                _mono('${_secRows(sec).length} ROWS', 9, color: _muted),
              ],
            ),
            const SizedBox(height: 10),
            _tableSection(sec),
          ],
      ],
      const SizedBox(height: 24),
      _idCardSection(store, data, idcV: hasIdc ? idcV : null),
    ]);
  }

  /// ⭐ College ID card — upload / view / change / download / remove
  /// (original v7.9 id-card block mirror).
  Widget _idCardSection(AppStore store, Map<String, dynamic> data,
      {int? idcV}) {
    final uid = _s(data['uid']);
    final url = '/api/ums/id-card/?uid=$uid&v=$idcV';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _eyebrow('College ID Card'),
            _mono(idcV != null ? 'SAVED' : 'NOT UPLOADED', 9,
                color: idcV != null ? _soft : _muted),
          ],
        ),
        const SizedBox(height: 10),
        _ledger([
          if (_idcBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _red)),
            )
          else if (idcV != null) ...[
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _IdCardViewer(url: _abs(url)))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 320),
                  width: double.infinity,
                  color: Colors.black,
                  child: Image.network(_abs(url),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          height: 120,
                          alignment: Alignment.center,
                          child: _mono('IMAGE FAILED TO LOAD', 10,
                              color: _muted))),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _pickIdCard,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _reddim,
                        border:
                            Border.all(color: const Color(0x66EC1C24)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                          child: _mono('\u27F2 CHANGE', 10,
                              color: _red, w: FontWeight.w800)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _open(url),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: _hair),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                          child: _mono('\u21E9 DOWNLOAD', 10,
                              color: _soft, w: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                setState(() => _idcBusy = true);
                final okk = await store.umsIdCardRemove();
                if (!mounted) return;
                setState(() => _idcBusy = false);
                showCunnectToast(
                    context, okk ? 'ID CARD REMOVED' : 'REMOVE FAILED');
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: _hair),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                    child: _mono('REMOVE', 10,
                        color: _muted, w: FontWeight.w800)),
              ),
            ),
          ] else
            GestureDetector(
              onTap: _pickIdCard,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: _reddim,
                  border: Border.all(color: const Color(0x66EC1C24)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _surface,
                        border:
                            Border.all(color: const Color(0x66EC1C24)),
                      ),
                      child: _mono('\u21EA', 18, color: _red),
                    ),
                    const SizedBox(height: 12),
                    const Text('Upload your ID Card',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _mono('GALLERY / CAMERA \u00B7 AUTO-COMPRESS', 9,
                        color: _muted),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: 'NOTE: ',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    letterSpacing: 1.4,
                    color: Colors.white.withOpacity(.9),
                    fontWeight: FontWeight.w700)),
            TextSpan(
                text:
                    'remove the ID case and upload a colourful scanned document version of your ID card',
                style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: Colors.white.withOpacity(.75))),
          ])),
        ]),
      ],
    );
  }

  Future<void> _pickIdCard() async {
    if (!idPickSupported) {
      showCunnectToast(context,
          'ID card upload is available in the Chrome web browser');
      return;
    }
    final dataUrl = await pickImageDataUrl();
    if (!mounted || dataUrl == null) return;
    setState(() => _idcBusy = true);
    final okk = await context.read<AppStore>().umsIdCardUpload(dataUrl);
    if (!mounted) return;
    setState(() => _idcBusy = false);
    showCunnectToast(
        context, okk ? 'ID CARD SAVED \u2713' : 'UPLOAD FAILED \u2014 TRY AGAIN');
  }
}

// ══════════ ID CARD FULLSCREEN VIEWER ══════════
class _IdCardViewer extends StatelessWidget {
  final String url;

  const _IdCardViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(.94),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x17FFFFFF)),
                      ),
                      child: const Text('\u2190',
                          style: TextStyle(color: Color(0xFFB7B7BC))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('ID CARD',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.2,
                          color: const Color(0xFFB7B7BC))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      final message = await openExternalUrl(url);
                      if (context.mounted && message != null) {
                        showCunnectToast(context, message);
                      }
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x17FFFFFF)),
                      ),
                      child: const Text('\u21E9',
                          style: TextStyle(color: Color(0xFFB7B7BC))),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text(
                            'IMAGE FAILED TO LOAD',
                            style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: Color(0xFF87878D)))),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ══════════ COURSE MODAL (openCourse mirror) ══════════
class _CourseSheet extends StatefulWidget {
  final Map<String, dynamic> course;
  final Map<String, dynamic> timetable;
  final Future<void> Function(String url) onOpen;

  const _CourseSheet({
    required this.course,
    required this.timetable,
    required this.onOpen,
  });

  @override
  State<_CourseSheet> createState() => _CourseSheetState();
}

class _CourseSheetState extends State<_CourseSheet> {
  String _ctab = 'time'; // original: default Timeline
  double _k = 0;

  static const _red = Color(0xFFEC1C24);
  static const _hair = Color(0x17FFFFFF);
  static const _muted = Color(0xFF87878D);
  static const _soft = Color(0xFFB7B7BC);

  String _s(dynamic v) => v?.toString() ?? '';
  double _n(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(_s(v)) ?? 0;

  Widget _mono(String text, double size,
          {Color color = Colors.white, FontWeight w = FontWeight.w700}) =>
      Text(text,
          style: TextStyle(
              fontFamily: 'monospace',
              fontSize: size,
              color: color,
              fontWeight: w,
              letterSpacing: .6));

  static const _dow = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

  /// ⭐ Upcoming classes for this subject from TODAY onward (from the timetable) —
  /// original predOcc: day-wise occurrences today-first order me.
  List<String> _occurrences() {
    // ⭐ v53: prediction week starts NOW — today contributes only the
    // lectures of this subject still LEFT today (start time after now),
    // then upcoming days follow for one full week.
    final code = _s(widget.course['code']).toUpperCase();
    if (code.isEmpty) return const [];
    final counts = <String, int>{}; // full-day counts (upcoming days)
    final todayLeft = <int>[]; // start-minutes of today's slots
    final now = DateTime.now();
    final todayShort = _dow[now.weekday % 7];
    final nowMin = now.hour * 60 + now.minute;
    for (final e in widget.timetable.entries) {
      final day = _s(e.key).trim().toUpperCase();
      if (day.length < 3) continue;
      final short = day.substring(0, 3);
      final slots = (e.value is Map ? e.value['slots'] : null);
      if (slots is! List) continue;
      for (final slot in slots) {
        if (slot is Map &&
            _s(slot['code']).toUpperCase() == code) {
          counts[short] = (counts[short] ?? 0) + 1;
          if (short == todayShort) {
            final st = _slotStartMin(_s(slot['time']));
            if (st == null || st > nowMin) todayLeft.add(st ?? 24 * 60);
          }
        }
      }
    }
    final today = now.weekday % 7;
    final occ = <String>[];
    for (var i = 0; i < 7; i++) {
      final name = _dow[(today + i) % 7];
      final n = i == 0 ? todayLeft.length : (counts[name] ?? 0);
      for (var j = 0; j < n; j++) {
        occ.add(i == 0 ? 'TODAY' : name);
      }
    }
    return occ;
  }

  /// ⭐ v76: every upcoming lecture of THIS subject (day + start time),
  /// today's remaining slots first, then the rest of the week.
  List<Map<String, dynamic>> _lectures() {
    final code = _s(widget.course['code']).toUpperCase();
    if (code.isEmpty) return const [];
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final todayIdx = now.weekday % 7;
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < 7; i++) {
      final short = _dow[(todayIdx + i) % 7];
      final found = <Map<String, dynamic>>[];
      for (final e in widget.timetable.entries) {
        final day = _s(e.key).trim().toUpperCase();
        if (day.length < 3 || day.substring(0, 3) != short) continue;
        final slots = (e.value is Map ? e.value['slots'] : null);
        if (slots is! List) continue;
        for (final slot in slots) {
          if (slot is! Map) continue;
          if (_s(slot['code']).toUpperCase() != code) continue;
          final st = _slotStartMin(_s(slot['time']));
          if (i == 0 && st != null && st <= nowMin) continue;
          found.add({
            'day': i == 0 ? 'TODAY' : short,
            'time': _s(slot['time']),
            'min': st ?? 24 * 60,
          });
        }
      }
      found.sort((a, b) => (a['min'] as int).compareTo(b['min'] as int));
      out.addAll(found);
    }
    return out;
  }

  /// ⭐ v76: one headline that follows the PLAN (the slider), not just
  /// today's percentage — once the planned lectures take the subject to
  /// 75% the "attend the next N" warning disappears.
  Widget _planLine(int att, int tot) {
    final k = _k.round();
    final pa = att + k;
    final pt = tot + k;
    final pct = pt > 0 ? pa * 100.0 / pt : 0.0;
    final low = pct < 75;
    final need = (((0.75 * pt - pa) * 4) - 1e-9).ceil();
    final miss = (((pa - 0.75 * pt) / 0.75) + 1e-9).floor();
    final String head, bold, tail;
    if (low) {
      head = 'Attend the next ';
      bold = '${need < 0 ? 0 : need}';
      tail = need == 1 ? ' class to reach 75%.' : ' classes to reach 75%.';
    } else if (miss > 0) {
      head = 'You can miss ';
      bold = '$miss';
      tail = miss == 1
          ? ' more class before dropping below 75%.'
          : ' more classes before dropping below 75%.';
    } else {
      head = 'You are on the safe line — ';
      bold = 'no buffer';
      tail = ' left above 75%.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _mono(low ? 'RECOVERY REQUIRED' : 'SAFETY MARGIN', 9,
            color: low ? _red : _muted, w: FontWeight.w800),
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: head,
              style: const TextStyle(
                  color: _soft, fontSize: 13, height: 1.6)),
          TextSpan(
              text: bold,
              style: TextStyle(
                  fontFamily: 'monospace',
                  color: low ? _red : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
          TextSpan(
              text: tail,
              style: const TextStyle(
                  color: _soft, fontSize: 13, height: 1.6)),
        ])),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    final pct = _n(c['percentage']);
    final att = _n(c['attended']).round();
    final tot = _n(c['total']).round();
    final low = pct < 75;
    final miss = _n(c['miss']).round();
    final need = _n(c['need']).round();
    final dlog = c['dlog'] is Map
        ? (c['dlog'] as Map).map((k, x) => MapEntry(k.toString(), x))
        : const <String, dynamic>{};
    final days = c['dlog_days'] is List
        ? [
            for (final g in c['dlog_days'] as List)
              if (g is Map) g.map((k, x) => MapEntry(k.toString(), x)),
          ]
        : const <Map<String, dynamic>>[];
    final planUrl = _s(c['dplan_url']);
    final credits = _s(c['dplan_credits']);

    return DraggableScrollableSheet(
      initialChildSize: .88,
      minChildSize: .5,
      maxChildSize: .94,
      expand: true,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, .4],
            colors: [Color(0xFF16090B), Color(0xFF0F0F11)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [
                  Color(0x00EC1C24),
                  Color(0x59EC1C24),
                  Color(0x00EC1C24),
                ]),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
                children: [
                  // ── grabber + close ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0x26FFFFFF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _hair),
                          ),
                          child: _mono('\u2715', 11, color: _muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ── hero: title + pill + % ring ──
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0x29EC1C24),
                          Color(0x08EC1C24),
                          Color(0x05FFFFFF),
                        ],
                      ),
                      border: Border.all(color: const Color(0x3DEC1C24)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  _s(c['title']).isEmpty
                                      ? 'Course'
                                      : _s(c['title']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              _mono(
                                  '${_s(c['code'])}${credits.isNotEmpty ? ' \u00B7 $credits' : ''}',
                                  10,
                                  color: _muted),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: low
                                      ? null
                                      : const Color(0x24FFFFFF),
                                  gradient: low
                                      ? const LinearGradient(colors: [
                                          Color(0x47EC1C24),
                                          Color(0x14EC1C24),
                                        ])
                                      : null,
                                  border: Border.all(
                                      color: low
                                          ? const Color(0x61EC1C24)
                                          : const Color(0x40FFFFFF)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: _mono(
                                    low
                                        ? 'ATTEND $need TO RECOVER'
                                        : 'SAFE \u00B7 $miss BUNK LEFT',
                                    9,
                                    color: low
                                        ? const Color(0xFFFF737B)
                                        : const Color(0xFFEDEDEF),
                                    w: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _Ring(
                            pct: pct,
                            size: 76,
                            stroke: 7,
                            color: low ? _red : Colors.white,
                            label: _pctStr(pct),
                            sub: '$att/$tot'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // ── tabs bar ──
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0x0EEC1C24),
                      border: Border.all(color: const Color(0x2BEC1C24)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        for (final t in const [
                          ('pred', 'PREDICTION'),
                          ('time', 'TIMELINE'),
                          ('plan', 'COURSE PLAN'),
                        ])
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _ctab = t.$1),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 9),
                                decoration: BoxDecoration(
                                  gradient: _ctab == t.$1
                                      ? const LinearGradient(colors: [
                                          Color(0xFFEC1C24),
                                          Color(0xFFB01218),
                                        ])
                                      : null,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: _ctab == t.$1
                                      ? const [
                                          BoxShadow(
                                              color: Color(0xA6EC1C24),
                                              blurRadius: 16,
                                              offset: Offset(0, 5)),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: _mono(t.$2, 8.5,
                                      color: _ctab == t.$1
                                          ? Colors.white
                                          : _muted,
                                      w: FontWeight.w800),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ── TAB: PREDICTION ──
                  if (_ctab == 'pred') ...[
                    // ⭐ v76: follows the plan — the warning disappears as
                    // soon as the planned lectures reach 75%.
                    _planLine(att, tot),
                    if (tot > 0 || att > 0)
                      _planner(att, tot, pct),
                    if (tot == 0 && att == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _mono(
                            'No attended/delivered data available for prediction.',
                            10,
                            color: _muted),
                      ),
                  ],
                  // ── TAB: TIMELINE ──
                  if (_ctab == 'time') ...[
                    if (days.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _mono(
                            'No day-wise attendance log available yet.', 10,
                            color: _muted),
                      )
                    else ...[
                      Row(
                        children: [
                          Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFD7D7DC),
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          _mono('Present (${_n(dlog['present']).round()})', 9,
                              color: _muted, w: FontWeight.w800),
                          const SizedBox(width: 16),
                          Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: _red,
                                  shape: BoxShape.circle,
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Color(0xA6EC1C24),
                                        blurRadius: 9)
                                  ])),
                          const SizedBox(width: 6),
                          _mono('Absent (${_n(dlog['absent']).round()})', 9,
                              color: _muted, w: FontWeight.w800),
                        ],
                      ),
                      const SizedBox(height: 18),
                      for (final g in days) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(top: 4, right: 10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _n(g['a']) > 0
                                    ? _red
                                    : const Color(0xFFD7D7DC),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${_s(g['wday']).isEmpty ? '' : '${_s(g['wday'])}, '}${_s(g['date'])}',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 8),
                                  for (final e in (g['entries'] is List
                                      ? [
                                          for (final x in g['entries']
                                              as List)
                                            if (x is Map)
                                              x.map((k, x2) => MapEntry(
                                                  k.toString(), x2)),
                                        ]
                                      : const <Map<String, dynamic>>[]))
                                    _timelineEntry(e),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                    ],
                  ],
                  // ── TAB: COURSE PLAN ──
                  if (_ctab == 'plan')
                    if (planUrl.isNotEmpty) ...[
                      GestureDetector(
                        onTap: () => widget.onOpen(planUrl),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              Color(0xFFEC1C24),
                              Color(0xFFB01218),
                            ]),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0xB3EC1C24),
                                  blurRadius: 22,
                                  offset: Offset(0, 8)),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              _mono('\u25A4 LECTURE PLAN \u00B7 OPEN PDF', 10,
                                  color: Colors.white, w: FontWeight.w800),
                              _mono('\u2197', 14,
                                  color: Colors.white, w: FontWeight.w800),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _mono('OFFICIAL PORTAL PDF \u00B7 OPENS IN APP', 8,
                          color: _muted),
                    ] else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151518),
                          border: Border.all(color: _hair),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                            'No lecture-plan PDF link found for this course (faculty upload may be pending)',
                            style: TextStyle(
                                fontFamily: 'monospace',
                                color: _muted,
                                fontSize: 10,
                                height: 1.6)),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ⭐ v7.1 Class planner — slider se projected % live + day chips.
  Widget _planner(int att, int tot, double curPct) {
    final occ = _occurrences();
    final lec = _lectures();
    final maxK = occ.length;
    final k = _k.round() > maxK ? maxK : _k.round();
    final na = att + k;
    final nt = tot + k;
    final pct = nt > 0 ? na * 100.0 / nt : 0.0;
    final safe = pct >= 75;
    final delta = pct - curPct;

    // day chips: same-day merge ('FRI x2')
    final chips = <Map<String, dynamic>>[];
    var i = 0;
    while (i < occ.length) {
      final day = occ[i];
      final from = i;
      while (i < occ.length && occ[i] == day) {
        i++;
      }
      chips.add({'day': day, 'from': from, 'to': i});
    }

    String leaveText;
    if (safe) {
      final leave = ((na - 0.75 * nt) / 0.75 + 1e-9).floor();
      leaveText = leave > 0
          ? 'With this plan you can still bunk $leave more.'
          : 'With this plan you stay just above 75%.';
    } else {
      final need = (((0.75 * nt - na) * 4) - 1e-9).ceil();
      leaveText =
          'You still need ${need < 0 ? 0 : need} more attended to reach 75%.';
    }

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1FEC1C24), Color(0x05EC1C24)],
        ),
        border: Border.all(color: const Color(0x38EC1C24)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mono('CLASS PLANNER \u00B7 LIVE', 8, color: _muted, w: FontWeight.w800),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(pct.toStringAsFixed(1),
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            height: 1)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 2),
                      child: Text('%',
                          style: TextStyle(fontSize: 13, color: _muted)),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: safe ? null : _red,
                  border: Border.all(
                      color: safe ? const Color(0x38FFFFFF) : _red),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: safe
                      ? null
                      : const [
                          BoxShadow(
                              color: Color(0xB3EC1C24),
                              blurRadius: 12,
                              offset: Offset(0, 3)),
                        ],
                ),
                child: _mono(safe ? 'Safe' : 'Low', 8,
                    color: safe ? _soft : Colors.white, w: FontWeight.w800),
              ),
            ],
          ),
          if (maxK > 0) ...[
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white.withOpacity(.12),
                inactiveTrackColor: Colors.white.withOpacity(.12),
                thumbColor: Colors.white,
                overlayColor: const Color(0x22EC1C24),
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 9,
                    elevation: 0,
                    pressedElevation: 0),
              ),
              child: Slider(
                value: _k.clamp(0.0, maxK.toDouble()),
                min: 0,
                max: maxK.toDouble(),
                divisions: maxK,
                onChanged: (v) => setState(() => _k = v),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _mono('NOW', 8, color: _muted, w: FontWeight.w800),
                _mono('ATTEND ALL', 8, color: _muted, w: FontWeight.w800),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final ch in chips)
                  Builder(builder: (_) {
                    final from = ch['from'] as int;
                    final to = ch['to'] as int;
                    final cnt = to - from;
                    final st = k >= to ? 2 : (k > from ? 1 : 0);
                    return GestureDetector(
                      onTap: () => setState(() => _k = to.toDouble()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: st == 2 ? const Color(0x1AEC1C24) : null,
                          border: Border.all(
                              color: st > 0
                                  ? const Color(0x4DEC1C24)
                                  : _hair),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _mono(
                            '${ch['day']}${cnt > 1 ? ' x$cnt' : ''}', 9,
                            color: st == 2
                                ? Colors.white
                                : st == 1
                                    ? _soft
                                    : _muted,
                            w: FontWeight.w800),
                      ),
                    );
                  }),
              ],
            ),
            // ⭐ v76: this subject's upcoming lectures — scroll sideways,
            // tap one to plan "attend up to here" (the % updates itself).
            if (lec.isNotEmpty) ...[
              const SizedBox(height: 16),
              _mono('UPCOMING LECTURES', 9,
                  color: _muted, w: FontWeight.w800),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: lec.length,
                  itemBuilder: (_, i) {
                    final l = lec[i];
                    final on = _k.round() >= i + 1;
                    final time = '${l['time']}'.trim();
                    return GestureDetector(
                      onTap: () => setState(() => _k = (i + 1).toDouble()),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on ? const Color(0x1AEC1C24) : null,
                          border: Border.all(
                              color: on ? const Color(0x4DEC1C24) : _hair),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _mono(
                            '${l['day']}${time.isEmpty ? '' : ' · $time'}',
                            8.5,
                            color: on ? Colors.white : _muted,
                            w: FontWeight.w800),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Text(
              maxK == 0
                  ? 'no class in this week\u2019s timetable'
                  : delta > 0.05
                      ? '\u25B2 +${delta.toStringAsFixed(1)}% vs now'
                      : '= same as now',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: maxK > 0 && delta > 0.05 ? _soft : _soft)),
          const SizedBox(height: 6),
          Text(leaveText,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 1,
                  height: 1.6,
                  color: _muted)),
        ],
      ),
    );
  }

  Widget _timelineEntry(Map<String, dynamic> e) {
    final tone = _s(e['tone']);
    final borderColor = tone == 'absent'
        ? _red
        : tone == 'present'
            ? const Color(0x4DFFFFFF)
            : const Color(0x24FFFFFF);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        border: Border.all(color: _hair),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 2, color: borderColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (_s(e['time']).isNotEmpty)
                  TextSpan(
                      text: '\u25F7 ${_s(e['time'])}',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          letterSpacing: 1,
                          color: _soft)),
                if (_s(e['by']).isNotEmpty)
                  TextSpan(
                      text:
                          ' \u00B7 ${_s(e['by']).length > 24 ? '${_s(e['by']).substring(0, 24)}\u2026' : _s(e['by'])}',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: _muted)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: tone == 'absent' ? _red : null,
              border: Border.all(
                  color: tone == 'absent'
                      ? _red
                      : const Color(0x38FFFFFF)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: tone == 'absent'
                  ? const [
                      BoxShadow(
                          color: Color(0xB3EC1C24),
                          blurRadius: 12,
                          offset: Offset(0, 3)),
                    ]
                  : null,
            ),
            child: _mono(
                '${tone == 'present' ? '\u2713 ' : tone == 'absent' ? '\u2715 ' : ''}${_s(e['status']).toUpperCase()}',
                8,
                color: tone == 'absent'
                    ? Colors.white
                    : tone == 'present'
                        ? _soft
                        : _soft.withOpacity(.7),
                w: FontWeight.w800),
          ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════ PREDICT SHEET ══════════
/// ⭐ v53: start-minutes of a slot time like "10:15-11:05" / "01:15 PM".
/// Mirrors the dashboard's parser: no meridiem + hour 1..6 => PM.
int? _slotStartMin(String text) {
  final parts =
      text.toUpperCase().trim().split(RegExp(r'[-\u2013\u2014]|\bTO\b'));
  if (parts.isEmpty) return null;
  final re = RegExp(r'(\d{1,2})[:.](\d{2})');
  final m = re.firstMatch(parts[0]);
  if (m == null) return null;
  var h = int.tryParse(m.group(1)!) ?? 99;
  final min = int.tryParse(m.group(2)!) ?? 99;
  if (h > 23 || min > 59) return null;
  final c = parts[0].replaceAll('.', '');
  final mer = c.contains('PM') ? 'PM' : (c.contains('AM') ? 'AM' : null);
  if (mer == 'PM' && h < 12) {
    h += 12;
  } else if (mer == 'AM' && h == 12) {
    h = 0;
  } else if (mer == null && h >= 1 && h <= 6) {
    h += 12;
  }
  return h * 60 + min;
}

class _PredictSheet extends StatefulWidget {
  final double attended;
  final double held;
  final double overall;
  final List<Map<String, dynamic>> records;
  final Map<String, dynamic> timetable;

  const _PredictSheet({
    required this.attended,
    required this.held,
    required this.overall,
    required this.records,
    required this.timetable,
  });

  @override
  State<_PredictSheet> createState() => _PredictSheetState();
}

class _PredictSheetState extends State<_PredictSheet> {
  double _days = 0;
  // ⭐ v76: 0 = next 7 days, 1 = next 30 days
  bool _monthly = false;

  static const _red = Color(0xFFEC1C24);
  static const _hair = Color(0xFF242424);
  static const _muted = Color(0xFF9D9D9D);
  static const _soft = Color(0xFFC9C9C9);
  static const _green = Color(0xFF34D399);

  Widget _mono(String text, double size,
          {Color color = Colors.white, FontWeight w = FontWeight.w700}) =>
      Text(text,
          style: TextStyle(
              fontFamily: 'monospace',
              fontSize: size,
              color: color,
              fontWeight: w,
              letterSpacing: .6));

  List<Map<String, dynamic>> _slotsOf(dynamic dayValue) {
    if (dayValue is Map) {
      final slots = dayValue['slots'];
      if (slots is List) {
        return [
          for (final s in slots)
            if (s is Map) s.map((k, x) => MapEntry(k.toString(), x)),
        ];
      }
    }
    return [];
  }

  static const _dowShort = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

  /// ⭐ v53: prediction week starts TODAY — today's entry counts only the
  /// lectures still LEFT today (start time after now), then the upcoming
  /// days follow in real calendar order for one full week.
  List<Map<String, dynamic>> get _dayList {
    final slotsByDay = <String, List<Map<String, dynamic>>>{};
    for (final e in widget.timetable.entries) {
      final k = e.key.toString().trim();
      if (k.length < 3) continue;
      slotsByDay[k.substring(0, 3).toUpperCase()] = _slotsOf(e.value);
    }
    final now = DateTime.now();
    final todayIdx = now.weekday % 7;
    final nowMin = now.hour * 60 + now.minute;
    final out = <Map<String, dynamic>>[];
    // ⭐ v91: a full month of days is built (the sheet shows 7 or 30).
    // ALL calendar days are kept now — even days with no timetable
    // classes (they simply add 0 lectures) — so the month view can be
    // drawn as a real calendar grid.
    for (var i = 0; i < 30; i++) {
      final short = _dowShort[(todayIdx + i) % 7];
      final slots = slotsByDay[short] ?? const [];
      final codes = <String>[
        for (final slot in slots)
          if (i > 0 ||
              (_slotStartMin((slot['time'] ?? '').toString()) ?? 24 * 60) >
                  nowMin)
            (slot['code'] ?? '').toString(),
      ];
      out.add({
        'day': i == 0 ? 'TODAY' : short,
        'short': short,
        'date': now.add(Duration(days: i)).day,
        'codes': codes,
      });
    }
    return out;
  }

  Map<String, int> _addsFor(int days) {
    final adds = <String, int>{};
    var total = 0;
    final dl = _dayList;
    for (var i = 0; i < days && i < dl.length; i++) {
      final codes = (dl[i]['codes'] as List).cast<String>();
      total += codes.length;
      for (final c in codes) {
        adds[c] = (adds[c] ?? 0) + 1;
      }
    }
    return adds..putIfAbsent('__total__', () => total);
  }

  /// ⭐ v76: 1 WEEK / 1 MONTH switch
  Widget _seg(String label, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? _red : Colors.transparent,
            border: Border.all(color: on ? _red : _hair),
            borderRadius: BorderRadius.circular(10),
          ),
          child: _mono(label, 9,
              color: on ? Colors.white : _muted, w: FontWeight.w800),
        ),
      );

  /// ⭐ v76: one day chip — the monthly view adds the date to it.
  Widget _dayChip(int i, List<Map<String, dynamic>> dl) {
    final on = _days.round() >= i + 1;
    final label =
        _monthly ? '${dl[i]['short']} ${dl[i]['date']}' : '${dl[i]['day']}';
    return GestureDetector(
      onTap: () => setState(
          () => _days = (_days.round() == i + 1) ? 0 : (i + 1).toDouble()),
      child: Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? _reddimBg : null,
          border: Border.all(color: on ? _red : _hair),
          borderRadius: BorderRadius.circular(14),
        ),
        child: _mono('$label · ${(dl[i]['codes'] as List).length}', 9,
            color: on ? _red : _muted, w: FontWeight.w800),
      ),
    );
  }

  /// ⭐ v91: month view as a real calendar grid — 7 columns (S M T W T F S),
  /// starting at today's weekday column. Days turn red one by one as the
  /// prediction slider / taps move forward.
  Widget _monthCalendar(List<Map<String, dynamic>> dl, int maxDays) {
    const heads = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final lead = DateTime.now().weekday % 7;
    final cells = <Widget>[
      for (var k = 0; k < lead; k++) const Expanded(child: SizedBox()),
      for (var i = 0; i < maxDays && i < dl.length; i++) _calCell(i, dl),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const Expanded(child: SizedBox()));
    }
    final rows = <Widget>[];
    for (var r = 0; r < cells.length; r += 7) {
      rows.add(Row(children: cells.sublist(r, r + 7)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final h in heads)
              Expanded(
                child: Center(
                  child:
                      _mono(h, 7.5, color: _muted, w: FontWeight.w800),
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        ...rows,
      ],
    );
  }

  /// One calendar day cell — date + that day's lecture count.
  /// Selected (inside the predicted range) = red.
  Widget _calCell(int i, List<Map<String, dynamic>> dl) {
    final on = _days.round() >= i + 1;
    final n = (dl[i]['codes'] as List).length;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() =>
            _days = (_days.round() == i + 1) ? 0 : (i + 1).toDouble()),
        child: Container(
          margin: const EdgeInsets.all(2.5),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: on ? _reddimBg : const Color(0xFF161616),
            border: Border.all(color: on ? _red : _hair),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _mono('${dl[i]['date']}', 12,
                  color: on ? _red : Colors.white, w: FontWeight.w800),
              const SizedBox(height: 2),
              _mono(n > 0 ? '$n' : '·', 7.5,
                  color: on ? _red : _muted, w: FontWeight.w800),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final missed = (widget.held - widget.attended).round();
    final dl = _dayList;
    final maxDays = (_monthly ? 30 : 7) > dl.length ? dl.length : (_monthly ? 30 : 7);
    if (_days.round() > maxDays) _days = maxDays.toDouble();
    final days = _days.round();
    final adds = _addsFor(days);
    final totalAdd = adds['__total__'] ?? 0;
    final predOverall = widget.held + totalAdd > 0
        ? (widget.attended + totalAdd) / (widget.held + totalAdd) * 100
        : 0.0;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F11),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Attendance Prediction',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Color(0xFF373737)),
                    child: const Text('×',
                        style: TextStyle(
                            color: Colors.white, fontSize: 18, height: 1)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: Row(
              children: [
                _seg('1 WEEK', !_monthly, () => setState(() {
                      _monthly = false;
                      if (_days.round() > 7) _days = 7;
                    })),
                const SizedBox(width: 8),
                _seg('1 MONTH', _monthly, () => setState(() => _monthly = true)),
                const Spacer(),
                _mono(_monthly ? 'NEXT 30 DAYS' : 'NEXT 7 DAYS', 8,
                    color: _muted),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Row(
                  children: [
                    _Ring(
                        pct: predOverall,
                        size: 104,
                        stroke: 6,
                        color: predOverall >= 75 ? Colors.white : _red,
                        label: predOverall.toStringAsFixed(1),
                        sub: 'AVG %'),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _mono(
                              'Total: ${widget.held.round()} classes', 11,
                              color: _soft, w: FontWeight.w800),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _chip('✓ ${widget.attended.round()}',
                                  bg: const Color(0x2634D399), fg: _green),
                              _chip('✗ $missed',
                                  bg: const Color(0x26EC1C24), fg: _red),
                              if (totalAdd > 0)
                                _chip('+$totalAdd planned',
                                    bg: const Color(0x26FFFFFF), fg: _soft),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _mono('OVERALL', 8, color: _muted),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _red,
                    inactiveTrackColor: const Color(0xFF2A2A2A),
                    thumbColor: _red,
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _days.clamp(0, maxDays.toDouble()),
                    min: 0,
                    max: maxDays.toDouble() < 1 ? 1 : maxDays.toDouble(),
                    divisions: maxDays < 1 ? 1 : maxDays,
                    onChanged: (v) => setState(() => _days = v),
                  ),
                ),
                const SizedBox(height: 4),
                // ⭐ v91: month = calendar grid (red fills as you predict),
                // week = the old chips.
                _monthly
                    ? _monthCalendar(dl, maxDays)
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < maxDays; i++) _dayChip(i, dl),
                        ],
                      ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _mono('YOUR SUBJECTS', 9, color: _muted, w: FontWeight.w800),
                    _mono('${widget.records.length} COURSES', 9,
                        color: _muted),
                  ],
                ),
                const SizedBox(height: 12),
                // ⭐ v91: month = subjects scroll HORIZONTALLY, week = old
                // vertical list.
                _monthly
                    ? SizedBox(
                        height: 216,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.records.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (_, i) =>
                              _subjCard(widget.records[i], adds),
                        ),
                      )
                    : Column(
                        children: [
                          for (final c in widget.records) _subjTile(c, adds),
                        ],
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _reddimBg = Color(0x26EC1C24);

  Widget _chip(String text, {required Color bg, required Color fg}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: _mono(text, 9, color: fg, w: FontWeight.w800),
      );

  Widget _subjTile(Map<String, dynamic> c, Map<String, int> adds) {
    final code = (c['code'] ?? '').toString();
    final att = (c['attended'] is num ? (c['attended'] as num).toDouble() : 0);
    final tot = (c['total'] is num ? (c['total'] as num).toDouble() : 0);
    final add = adds[code] ?? 0;
    final pct = tot > 0 ? att / tot * 100 : 0.0;
    final pred = tot + add > 0 ? (att + add) / (tot + add) * 100 : 0.0;
    final shown = add > 0 ? pred : pct;
    // ⭐ v91: the verdict now follows the PREDICTED percentage — once the
    // slider pushes a subject over 75% it flips to "MISS NEXT n" (how many
    // you can safely miss), instead of sticking on "ATTEND NEXT n".
    final low = shown < 75;
    final need = (tot + add) > 0 && low
        ? ((0.75 * (tot + add)) - (att + add)).ceil()
        : (c['need'] is num ? (c['need'] as num) : 0).round();
    final miss = (tot + add) > 0 && !low
        ? ((att + add) - (0.75 * (tot + add))).floor()
        : (c['miss'] is num ? (c['miss'] as num) : 0).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hair),
        ),
        child: Row(
          children: [
            _Ring(
                pct: shown,
                size: 46,
                stroke: 5,
                color: shown >= 75 ? Colors.white : _red,
                label: _pctStr(shown),
                sub: ''),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _mono(code.isEmpty ? 'COURSE' : code, 11, w: FontWeight.w800),
                  const SizedBox(height: 3),
                  Text((c['title'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 10)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _mono('${att.round()}/${tot.round()}', 8.5,
                          color: _muted),
                      if (add > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x2634D399),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _mono('+$add', 8.5,
                              color: _green, w: FontWeight.w800),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _mono(
                    low
                        ? '⚠ ATTEND NEXT $need'
                        : 'MISS NEXT $miss',
                    8.5,
                    color: low ? _red : _soft,
                    w: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ⭐ v91: compact subject card for the month view — the subject row
  /// scrolls HORIZONTALLY now. Same numbers as _subjTile.
  Widget _subjCard(Map<String, dynamic> c, Map<String, int> adds) {
    final code = (c['code'] ?? '').toString();
    final att = (c['attended'] is num ? (c['attended'] as num).toDouble() : 0);
    final tot = (c['total'] is num ? (c['total'] as num).toDouble() : 0);
    final add = adds[code] ?? 0;
    final pct = tot > 0 ? att / tot * 100 : 0.0;
    final pred = tot + add > 0 ? (att + add) / (tot + add) * 100 : 0.0;
    final shown = add > 0 ? pred : pct;
    final low = shown < 75;
    final need = (tot + add) > 0 && low
        ? ((0.75 * (tot + add)) - (att + add)).ceil()
        : (c['need'] is num ? (c['need'] as num) : 0).round();
    final miss = (tot + add) > 0 && !low
        ? ((att + add) - (0.75 * (tot + add))).floor()
        : (c['miss'] is num ? (c['miss'] as num) : 0).round();
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _hair),
      ),
      child: Column(
        children: [
          _Ring(
              pct: shown,
              size: 54,
              stroke: 5,
              color: shown >= 75 ? Colors.white : _red,
              label: _pctStr(shown),
              sub: ''),
          const SizedBox(height: 9),
          _mono(code.isEmpty ? 'COURSE' : code, 11, w: FontWeight.w800),
          const SizedBox(height: 3),
          SizedBox(
            width: 126,
            child: Text(
              (c['title'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 9),
            ),
          ),
          const SizedBox(height: 7),
          _mono(
              add > 0
                  ? '${att.round()}/${tot.round()}  +$add'
                  : '${att.round()}/${tot.round()}',
              8.5,
              color: add > 0 ? _green : _muted,
              w: FontWeight.w800),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: low ? const Color(0x26EC1C24) : const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _mono(low ? '⚠ ATTEND NEXT $need' : 'MISS NEXT $miss', 8,
                color: low ? _red : _soft, w: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ══════════ RING ══════════
class _Ring extends StatelessWidget {
  final double pct;
  final double size;
  final double stroke;
  final Color color;
  final String label;
  final String sub;

  const _Ring({
    required this.pct,
    required this.size,
    required this.stroke,
    required this.color,
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(pct: pct, stroke: stroke, color: color),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: size * 0.19,
                      fontWeight: FontWeight.w800)),
              if (sub.isNotEmpty)
                Text(sub,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: size * 0.07,
                        color: const Color(0xFF9D9D9D),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final double stroke;
  final Color color;

  _RingPainter({required this.pct, required this.stroke, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final bg = Paint()
      ..color = const Color(0x14FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 3.14159 * 2, false, bg);
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final sweep = (pct / 100).clamp(0.0, 1.0) * 3.14159 * 2;
    canvas.drawArc(rect, -3.14159 / 2, sweep, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.pct != pct || old.color != color;
}
