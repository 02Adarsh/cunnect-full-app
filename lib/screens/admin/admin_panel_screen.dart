import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../vendor/vendor_shell.dart';
import 'admin_login_screen.dart';

/// ⭐ CUnnect Admin Portal 2.0 — six swipeable pages (like the UMS
/// sections) with a floating bottom carousel nav (like the CUnnect
/// homepage): Home · Store · Vendors · Orders · Students · Control.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _pageController = PageController();
  final _vendorCardController = PageController(viewportFraction: .92);
  int _page = 0;
  Timer? _liveTimer;

  // ---- home / stats ----
  Map<String, dynamic> _stats = {};
  String _statsPeriod = 'daily';
  List<dynamic> _liveUsers = [];
  // ⭐ v50.1 speed: per-period and per-kind caches — switching views is
  // instant (cached data renders immediately, refresh happens silently).
  final Map<String, Map<String, dynamic>> _statsCache = {};
  final Map<String, List<dynamic>> _ordersCache = {};

  // ---- store ----
  List<dynamic> _sections = [];

  // ---- vendors ----
  List<dynamic> _vendors = [];
  // ⭐ v50.1: pre-warmed portal sessions — "Open Vendor Portal" is instant.
  final Map<int, Map<String, dynamic>> _portalCache = {};

  // ---- orders ----
  List<dynamic> _orders = [];
  String _orderKind = 'food';
  // ⭐ v61: every store section becomes an order tab (from the API)
  List<Map<String, dynamic>> _orderKinds = [
    {'key': 'food', 'title': 'Food'},
    {'key': 'print', 'title': 'Print'},
    {'key': 'hostel', 'title': 'Hostel'},
  ];

  // ---- students ----
  List<dynamic> _allStudents = [];
  final _studentSearch = TextEditingController();
  // ⭐ v81: add-an-AUTO-partner form
  final _autoName = TextEditingController();
  final _autoPhone = TextEditingController();
  final _autoPass = TextEditingController();

  /// ⭐ Local instant filtering — no network round-trip while typing.
  List<dynamic> get _students {
    final q = _studentSearch.text.trim().toLowerCase();
    if (q.isEmpty) return _allStudents;
    return [
      for (final s in _allStudents)
        if ('${s['name']} ${s['uid']} ${s['phone']}'.toLowerCase().contains(q))
          s,
    ];
  }

  // ---- control ----
  List<dynamic> _feedPosts = [];
  int _pinnedCount = 0;
  int _maxPinned = 15;
  List<dynamic> _coupons = [];
  List<dynamic> _support = [];
  List<dynamic> _banners = []; // ⭐ v58

  static const _navItems = [
    (Icons.home_rounded, 'Home'),
    (Icons.storefront_rounded, 'Store'),
    (Icons.badge_rounded, 'Vendors'),
    (Icons.receipt_long_rounded, 'Orders'),
    (Icons.school_rounded, 'Students'),
    (Icons.tune_rounded, 'Control'),
  ];

  /// ⭐ v62: paint every page from the LAST session's cache before any
  /// network call — the panel is full of data the instant it opens.
  void _hydrateFromCache() {
    final s = _store;
    final stats = s.adminCached('/api/admin/stats/?period=$_statsPeriod');
    final sections = s.adminCached('/api/admin/sections/');
    final vendors = s.adminCached('/api/admin/vendors/');
    final orders = s.adminCached('/api/admin/orders/?kind=$_orderKind');
    final kinds = s.adminCached('/api/admin/order-kinds/');
    final students = s.adminCached('/api/admin/students/');
    final feed = s.adminCached('/api/admin/feed/');
    final coupons = s.adminCached('/api/admin/coupons/');
    final support = s.adminCached('/api/admin/support/');
    final banners = s.adminCached('/api/admin/banners/');
    setState(() {
      if (stats.isNotEmpty) _stats = stats;
      _sections = (sections['sections'] as List?) ?? _sections;
      _vendors = (vendors['vendors'] as List?) ?? _vendors;
      _orders = (orders['orders'] as List?) ?? _orders;
      final kindRows = (kinds['kinds'] as List?) ?? [];
      if (kindRows.isNotEmpty) {
        _orderKinds = [
          for (final k in kindRows) Map<String, dynamic>.from(k as Map),
        ];
      }
      _allStudents = (students['students'] as List?) ?? _allStudents;
      _feedPosts = (feed['posts'] as List?) ?? _feedPosts;
      _pinnedCount = (feed['pinned_count'] ?? _pinnedCount) as int;
      _coupons = (coupons['coupons'] as List?) ?? _coupons;
      _support = (support['requests'] as List?) ?? _support;
      _banners = (banners['banners'] as List?) ?? _banners;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ⭐ v62: cache first — data on screen in 0 ms, then refresh live.
      _hydrateFromCache();
      // ⭐ v50.1: preload EVERY page in parallel at startup — tapping or
      // swiping to any page shows its data instantly, no wait.
      for (var i = 0; i < 6; i++) {
        _loadPage(i);
      }
      // Also pre-warm the other stat periods so Daily/Weekly/Monthly
      // toggles are instant.
      _prewarmStatsPeriods();
      _prewarmOrderKinds();
    });
    // ⭐ Live stats refresh every 10 seconds while on Home.
    _liveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && _page == 0) _loadStats();
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _pageController.dispose();
    _vendorCardController.dispose();
    _studentSearch.dispose();
    _autoName.dispose();
    _autoPhone.dispose();
    _autoPass.dispose();
    super.dispose();
  }

  AppStore get _store => context.read<AppStore>();

  Future<void> _loadStats() async {
    final period = _statsPeriod;
    // ⭐ Parallel fetches — the portal stays snappy.
    final results = await Future.wait([
      _store.adminGet('/api/admin/stats/?period=$period'),
      _store.adminGet('/api/admin/live-users/'),
    ]);
    if (results[0].isNotEmpty) _statsCache[period] = results[0];
    if (!mounted) return;
    setState(() {
      if (results[0].isNotEmpty && period == _statsPeriod) {
        _stats = results[0];
      }
      _liveUsers = (results[1]['users'] as List?) ?? _liveUsers;
    });
  }

  /// ⭐ Pre-warm every vendor's portal session in parallel so tapping
  /// "Open Vendor Portal" switches instantly with zero network wait.
  Future<void> _prewarmVendorPortals() async {
    await Future.wait([
      for (final v in _vendors)
        _store.adminFetchVendorPortal((v['id'] ?? 0) as int).then((d) {
          if (d != null) _portalCache[(v['id'] ?? 0) as int] = d;
        }),
    ]);
  }

  /// ⭐ v62: fetch EVERY order-kind tab in the background (all store
  /// sections, not just the 3 built-ins) so switching tabs never waits.
  Future<void> _prewarmOrderKinds() async {
    await Future.wait([
      for (final k in _orderKinds)
        if ('${k['key']}' != _orderKind)
          _store
              .adminGet('/api/admin/orders/?kind=${k['key']}')
              .then((d) {
            _ordersCache['${k['key']}'] = (d['orders'] as List?) ?? [];
          }),
    ]);
  }

  /// ⭐ Fetch all three stat periods in the background so switching the
  /// Daily / Weekly / Monthly toggle never waits on the network.
  Future<void> _prewarmStatsPeriods() async {
    await Future.wait([
      for (final p in const ['daily', 'weekly', 'monthly'])
        if (p != _statsPeriod)
          _store.adminGet('/api/admin/stats/?period=$p').then((d) {
            if (d.isNotEmpty) _statsCache[p] = d;
          }),
    ]);
  }

  Future<void> _loadPage(int page) async {
    switch (page) {
      case 0:
        await _loadStats();
        break;
      case 1:
        final r = await Future.wait([
          _store.adminGet('/api/admin/sections/'),
          _store.adminGet('/api/admin/vendors/'),
        ]);
        if (mounted) {
          setState(() {
            _sections = (r[0]['sections'] as List?) ?? [];
            _vendors = (r[1]['vendors'] as List?) ?? [];
          });
        }
        // ⭐ v81: AUTO partners live in the Vendors page now
        _store.loadAdminAutoPartners();
        _store.loadAdminAutoCalls();
        _prewarmVendorPortals();
        break;
      case 2:
        final d = await _store.adminGet('/api/admin/vendors/');
        if (mounted) setState(() => _vendors = (d['vendors'] as List?) ?? []);
        // ⭐ v81: AUTO partners are managed from this page
        await Future.wait([
          _store.loadAdminAutoPartners(),
          _store.loadAdminAutoCalls(),
        ]);
        if (mounted) setState(() {});
        _prewarmVendorPortals();
        break;
      case 3:
        final kind = _orderKind;
        // ⭐ v61: tabs for EVERY store section, fetched with the orders
        final r = await Future.wait([
          _store.adminGet('/api/admin/orders/?kind=$kind'),
          _store.adminGet('/api/admin/order-kinds/'),
        ]);
        final rows = (r[0]['orders'] as List?) ?? [];
        _ordersCache[kind] = rows;
        final kindRows = (r[1]['kinds'] as List?) ?? [];
        final hadNewKinds = kindRows.length > _orderKinds.length;
        if (mounted) {
          setState(() {
            if (kindRows.isNotEmpty) {
              _orderKinds = [
                for (final k in kindRows)
                  Map<String, dynamic>.from(k as Map),
              ];
            }
            if (kind == _orderKind) _orders = rows;
          });
        }
        // ⭐ v62: custom sections arrived — prewarm their tabs too so
        // every pill switches instantly.
        if (hadNewKinds) _prewarmOrderKinds();
        break;
      case 4:
        // ⭐ v50.1: always fetch the full list once, then search filters
        // LOCALLY — results appear letter by letter with zero delay.
        final d = await _store.adminGet('/api/admin/students/');
        if (mounted) {
          setState(() => _allStudents = (d['students'] as List?) ?? []);
        }
        break;
      case 5:
        final r = await Future.wait([
          _store.adminGet('/api/admin/feed/'),
          _store.adminGet('/api/admin/coupons/'),
          _store.adminGet('/api/admin/support/'),
          _store.adminGet('/api/admin/banners/'), // ⭐ v58
        ]);
        if (mounted) {
          setState(() {
            _feedPosts = (r[0]['posts'] as List?) ?? [];
            _pinnedCount = (r[0]['pinned_count'] ?? 0) as int;
            _maxPinned = (r[0]['max_pinned'] ?? 15) as int;
            _coupons = (r[1]['coupons'] as List?) ?? [];
            _support = (r[2]['requests'] as List?) ?? [];
            _banners = (r[3]['banners'] as List?) ?? [];
          });
        }
        break;
      default:
        break;
    }
  }

  void _toast(String? err, String okMessage) {
    if (!mounted) return;
    showCunnectToast(context, err ?? okMessage, error: err != null);
  }

  void _goTo(int page) {
    _pageController.animateToPage(page,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          Column(children: [
            const CunnectHeader(useWordmark: false),
            // ---- portal header ----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(_navItems[_page].$2 == 'Home'
                                ? 'Admin Portal'
                                : _navItems[_page].$2,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified,
                            size: 15, color: Color(0xFFF10B1D)),
                      ]),
                      const SizedBox(height: 2),
                      Text('Signed in as ${store.adminUsername}',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 10.5)),
                    ],
                  ),
                ),
                _livePill(),
              ]),
            ),
            // ---- swipeable pages (UMS style) ----
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  _loadPage(i);
                },
                children: [
                  _homePage(),
                  _storePage(),
                  _vendorsPage(),
                  _ordersPage(),
                  _studentsPage(),
                  _controlPage(),
                ],
              ),
            ),
          ]),
          _bottomNav(),
        ]),
      ),
    );
  }

  Widget _livePill() {
    final live = _stats['live_users'] ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1738B765),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0x6B38B765)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.red,
            boxShadow: [BoxShadow(color: AppColors.red, blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 6),
        Text('$live LIVE',
            style: const TextStyle(
                color: Color(0xFFF5F5F5),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .6)),
      ]),
    );
  }

  // ------------------------------------------------------------------
  // ⭐ Floating bottom carousel nav — same style as the CUnnect homepage.
  // ------------------------------------------------------------------
  Widget _bottomNav() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).padding.bottom + 10,
      child: Center(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xF2141414),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0x26FF0000)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 20),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _navItems.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => _goTo(i),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_navItems[i].$1,
                              size: 20,
                              color: _page == i
                                  ? AppColors.red
                                  : const Color(0xFF9A9A9A)),
                          const SizedBox(height: 4),
                          Text(_navItems[i].$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: _page == i
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: _page == i
                                      ? AppColors.red
                                      : const Color(0xFF9A9A9A))),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  EdgeInsets get _pagePadding => EdgeInsets.fromLTRB(
      14, 4, 14, 110 + MediaQuery.of(context).padding.bottom);

  // ==================================================================
  // PAGE 0 — HOME: live users, impressions, traffic, transactions,
  // revenue (total + by source) with daily/weekly/monthly views.
  // ==================================================================
  Widget _homePage() {
    final s = _stats;
    final revBySource =
        (s['revenue_today_by_source'] as Map?) ?? const {};
    final totals = (s['totals'] as Map?) ?? const {};
    final points = (s['points'] as List?) ?? const [];

    return RefreshIndicator(
      color: AppColors.red,
      backgroundColor: const Color(0xFF1B1B1B),
      onRefresh: _loadStats,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pagePadding,
        children: [
          // ---- headline: active users · impressions · traffic ----
          Row(children: [
            _metric('Active Users', '${s['live_users'] ?? 0}',
                AppColors.red, Icons.podcasts_rounded),
            const SizedBox(width: 10),
            _metric('Impressions Today', _compact(s['impressions_today']),
                const Color(0xFF6EA8FE), Icons.visibility_rounded),
            const SizedBox(width: 10),
            _metric('Traffic Today', _compact(s['traffic_today']),
                const Color(0xFFB58CFF), Icons.groups_rounded),
          ]),
          const SizedBox(height: 12),
          // ---- single horizontal period bar ----
          _periodBar(),
          const SizedBox(height: 12),
          // ---- impressions & traffic trend ----
          _panel(
            title: 'Impressions & Traffic',
            subtitle: _periodSubtitle(
                'Total impressions ${_compact(totals['impressions'])} · '
                'unique traffic ${_compact(totals['traffic'])}'),
            child: _TrendBars(
              points: points,
              primaryKey: 'impressions',
              secondaryKey: 'traffic',
              primaryColor: const Color(0xFF6EA8FE),
              secondaryColor: const Color(0xFFB58CFF),
              primaryLabel: 'Impressions',
              secondaryLabel: 'Traffic',
            ),
          ),
          const SizedBox(height: 12),
          // ---- transactions + revenue today ----
          Row(children: [
            _metric('Transactions Today', '${s['transactions_today'] ?? 0}',
                const Color(0xFFD9A94E), Icons.swap_horiz_rounded),
            const SizedBox(width: 10),
            _metric(
                'Revenue Today',
                '₹${_compact(s['revenue_today'])}',
                AppColors.red,
                Icons.currency_rupee_rounded),
          ]),
          const SizedBox(height: 12),
          // ---- revenue by source ----
          _panel(
            title: 'Revenue by Source',
            subtitle: _periodSubtitle(
                'Period total ₹${_compact(totals['revenue'])}'),
            child: Column(children: [
              _sourceRow('🍔  Food', (revBySource['food'] ?? 0),
                  (totals['food'] ?? 0), const Color(0xFF6EA8FE)),
              _sourceRow('🖨  Print', (revBySource['print'] ?? 0),
                  (totals['print'] ?? 0), const Color(0xFFFF9CA4)),
              _sourceRow('🛏  Hostel', (revBySource['hostel'] ?? 0),
                  (totals['hostel'] ?? 0), const Color(0xFFB58CFF)),
              const SizedBox(height: 8),
              _TrendBars(
                points: points,
                primaryKey: 'revenue',
                primaryColor: AppColors.red,
                primaryLabel: 'Revenue ₹',
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // ---- live users list ----
          _panel(
            title: 'Live Right Now',
            subtitle:
                'Users active in the last 3 minutes. Refreshes every 10 s.',
            child: _liveUsers.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                        child: Text('No one is online right now.',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 11.5))),
                  )
                : Column(children: [
                    for (final u in _liveUsers.take(20))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.5),
                        child: Row(children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.red),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                                '${u['name'] ?? u['username']}  ·  ${u['kind']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600)),
                          ),
                          Text('${u['seconds_ago']}s',
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 10)),
                        ]),
                      ),
                  ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: () {
                _store.adminLogout();
                Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) => const AdminLoginScreen()));
              },
              icon:
                  const Icon(Icons.logout_rounded, size: 15, color: Color(0xFFFF9CA4)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0x8CF10B1D)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
              label: const Text('Logout of Admin Portal',
                  style: TextStyle(
                      color: Color(0xFFFF9CA4),
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  String _periodSubtitle(String base) {
    final label = switch (_statsPeriod) {
      'weekly' => 'last 12 weeks',
      'monthly' => 'last 12 months',
      _ => 'last 30 days',
    };
    return '$base · $label';
  }

  Widget _periodBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B2B2B)),
      ),
      child: Row(children: [
        for (final p in const [
          ('daily', 'Daily'),
          ('weekly', 'Weekly'),
          ('monthly', 'Monthly'),
        ])
          Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _statsPeriod = p.$1;
                  // ⭐ Instant: cached data renders with zero delay;
                  // a silent refresh follows in the background.
                  final cached = _statsCache[p.$1];
                  if (cached != null) _stats = cached;
                });
                _loadStats();
              },
              borderRadius: BorderRadius.circular(9),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _statsPeriod == p.$1
                      ? const Color(0x26F10B1D)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: _statsPeriod == p.$1
                          ? const Color(0x8CF10B1D)
                          : Colors.transparent),
                ),
                alignment: Alignment.center,
                child: Text(p.$2,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _statsPeriod == p.$1
                            ? const Color(0xFFFF9CA4)
                            : const Color(0xFF9A9A9A))),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _sourceRow(String label, num today, num periodTotal, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('₹${_compact(today)} today',
              style: TextStyle(
                  color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
          Text('₹${_compact(periodTotal)} in period',
              style: const TextStyle(color: AppColors.muted, fontSize: 9.5)),
        ]),
      ]),
    );
  }

  // ==================================================================
  // PAGE 1 — STORE: create sections, assign vendors to sections.
  // ==================================================================
  Widget _storePage() {
    final grouped = <String, List<dynamic>>{};
    for (final v in _vendors) {
      grouped.putIfAbsent((v['vendor_type'] ?? 'food') as String, () => [])
          .add(v);
    }
    return RefreshIndicator(
      color: AppColors.red,
      backgroundColor: const Color(0xFF1B1B1B),
      onRefresh: () => _loadPage(1),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pagePadding,
        children: [
          _panel(
            title: 'Store Sections',
            subtitle:
                'You have total control — switch any section on/off, edit its icon, lock it, or mark it coming soon. Built-in (CORE) sections can '
                'it, or mark it coming soon. Built-in (CORE) sections can '
                'be edited and hidden too; they just cannot be deleted.',
            child: Column(children: [
              // ⭐ v60: built-in AND custom sections come from the same API
              // list — every one is toggleable and editable.
              for (final sec in _sections)
                _sectionRow(
                  icon: (sec['icon'] ?? '🛍') as String,
                  title: (sec['title'] ?? '') as String,
                  subtitle:
                      '${(grouped[sec['key']] ?? []).length} vendor(s)'
                      '${(sec['builtin'] ?? false) as bool ? ' · built-in' : ''}'
                      '${(sec['coming_soon'] ?? false) as bool ? ' · COMING SOON' : ''}'
                      '${(sec['is_locked'] ?? false) as bool ? ' · LOCKED' : ''}'
                      '${(sec['is_active'] ?? true) as bool ? '' : ' · HIDDEN'}',
                  builtin: (sec['builtin'] ?? false) as bool,
                  onToggle: () async {
                    final was = (sec['is_active'] ?? true) as bool;
                    // ⭐ Optimistic: switch flips instantly.
                    setState(() => sec['is_active'] = !was);
                    final err = await _store.adminPost(
                        '/api/admin/sections/${sec['id']}/',
                        {'is_active': !was});
                    if (err != null) {
                      setState(() => sec['is_active'] = was); // roll back
                      _toast(err, '');
                    }
                  },
                  activeNow: (sec['is_active'] ?? true) as bool,
                  onEdit: () => _showSectionEditForm(sec as Map),
                  onDelete: (sec['builtin'] ?? false) as bool
                      ? null
                      : () => _confirmDelete(
                          'Remove the "${sec['title']}" section from the store?',
                          () async {
                        final idx = _sections.indexOf(sec);
                        setState(() => _sections.remove(sec));
                        final err = await _store
                            .adminDelete('/api/admin/sections/${sec['id']}/');
                        if (err != null && idx >= 0) {
                          setState(() => _sections.insert(idx, sec));
                        }
                        _toast(err, 'Section removed.');
                      }),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _showSectionForm,
                  icon: const Icon(Icons.add, size: 15),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  label: const Text('Add New Store Section'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          _panel(
            title: 'Vendors by Section',
            subtitle:
                'Add a vendor to any section — existing or newly created.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(entry.key.toUpperCase(),
                        style: const TextStyle(
                            color: Color(0xFFFF9CA4),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8)),
                  ),
                  for (final v in entry.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                              '${v['business_name']}  ·  ${v['phone']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                        InkWell(
                          onTap: () => _confirmDelete(
                              'Delete vendor "${v['business_name']}"?',
                              () async {
                            final err = await _store.adminDelete(
                                '/api/admin/vendors/${v['id']}/');
                            _toast(err, 'Vendor deleted.');
                            _loadPage(1);
                          }),
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(Icons.delete_outline,
                                size: 15, color: Color(0xFFFF9CA4)),
                          ),
                        ),
                      ]),
                    ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _showVendorForm,
                    icon: const Icon(Icons.person_add_alt_rounded,
                        size: 15, color: Color(0xFFDDDDDD)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3A3A3A)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                    label: const Text('Add New Vendor',
                        style: TextStyle(color: Color(0xFFDDDDDD))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionRow(
      {required String icon,
      required String title,
      required String subtitle,
      required bool builtin,
      VoidCallback? onToggle,
      bool activeNow = true,
      VoidCallback? onEdit,
      VoidCallback? onDelete}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 17)),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 9.5)),
            ],
          ),
        ),
        // ⭐ v60: CORE badge stays, but built-ins get the same toggle and
        // edit controls as custom sections — total admin control.
        if (builtin)
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x66D4C7A3)),
            ),
            child: const Text('CORE',
                style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 7.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
          ),
        if (onEdit != null)
          InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.edit_outlined,
                  size: 15, color: Color(0xFF9ECBFF)),
            ),
          ),
        if (onToggle != null)
          Switch(
              value: activeNow,
              activeColor: AppColors.red,
              onChanged: (_) => onToggle()),
        if (onDelete != null)
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.delete_outline,
                  size: 16, color: Color(0xFFFF9CA4)),
            ),
          ),
      ]),
    );
  }

  // ==================================================================
  // PAGE 2 — VENDORS: swipe between dedicated vendor pages; each opens
  // the vendor's EXACT portal (every bit identical to what they see).
  // ==================================================================
  // ---------------- AUTO partners (inside the Vendors page) ----------------

  /// ⭐ v81: AUTO is not a separate tab any more — this strip sits on
  /// top of the Vendors page and opens the AUTO manager.
  Widget _autoStrip() {
    final partners = context.watch<AppStore>().adminAutoPartners;
    final onDuty = partners
        .where((p) => (p['auto_online'] ?? false) == true)
        .length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x59F10B1D)),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0x2EF10B1D),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('🛺', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AUTO PARTNERS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                  partners.isEmpty
                      ? 'None yet — create one and he gets his own portal'
                      : '$onDuty of ${partners.length} on duty · opens '
                          'the AUTO portal',
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 10.5)),
            ],
          ),
        ),
        TextButton(
          onPressed: _showAutoSheet,
          child: const Text('MANAGE',
              style: TextStyle(
                  color: Color(0xFFFFABB2),
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  /// The whole AUTO manager: partners, duty switches, add / remove and
  /// the call log — opened from the Vendors page.
  Future<void> _showAutoSheet() async {
    await _store.loadAdminAutoPartners();
    await _store.loadAdminAutoCalls();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final partners = context.watch<AppStore>().adminAutoPartners;
          final others = context.watch<AppStore>().adminOtherPartners;
          final calls = context.watch<AppStore>().adminAutoCalls;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                18, 12, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                            color: const Color(0xFF3A3A3A),
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    const Text('🛺',
                        style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    const Text('AUTO PARTNERS',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('${partners.length}',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 11)),
                  ]),
                  const SizedBox(height: 6),
                  const Text(
                      'Each of them logs in with his own phone and gets the '
                      'AUTO portal — never the car console. Open any of them '
                      'from the vendor card below.',
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 11, height: 1.45)),
                  const SizedBox(height: 12),
                  for (final p in partners) _autoPartnerCard(p),
                  const SizedBox(height: 16),
                  const Text('ADD AN AUTO PARTNER',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Color(0xFF8A8A8A))),
                  const SizedBox(height: 8),
                  _autoField(_autoName, 'Partner name'),
                  const SizedBox(height: 8),
                  _autoField(_autoPhone, 'Phone (his login)',
                      keyboard: TextInputType.phone),
                  const SizedBox(height: 8),
                  _autoField(_autoPass, 'Password', obscure: true),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                      ),
                      onPressed: () async {
                        await _addAutoPartner();
                        if (ctx.mounted) setSheet(() {});
                      },
                      child: const Text('CREATE AUTO ACCOUNT',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  if (others.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text('MAKE A RIDE PARTNER AN AUTO PARTNER',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Color(0xFF8A8A8A))),
                    const SizedBox(height: 8),
                    for (final o in others) _autoOtherRow(o),
                  ],
                  const SizedBox(height: 18),
                  const Text('AUTO CALL LOG',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Color(0xFF8A8A8A))),
                  const SizedBox(height: 8),
                  if (calls.isEmpty)
                    const Text('No auto calls yet.',
                        style:
                            TextStyle(color: AppColors.muted, fontSize: 11))
                  else
                    for (final c in calls) _autoCallRow(c),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------
  // AUTO helpers — everything the AUTO manager sheet above draws with.
  // ------------------------------------------------------------------

  /// '23/9 · 18:42' from the server's ISO stamp (empty when unusable).
  String _autoTime(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final t = d.toLocal();
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${t.day}/${t.month} · $h:$m';
  }

  Widget _autoField(TextEditingController c, String label,
      {TextInputType? keyboard, bool obscure = false}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF0F0F0F),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFF2C2C2C))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFFFABB2))),
      ),
    );
  }

  /// One AUTO partner: his name, his tally and his ON / OFF DUTY switch.
  Widget _autoPartnerCard(Map<String, dynamic> p) {
    final vid = (p['vendor_id'] as num?)?.toInt() ?? 0;
    final on = (p['auto_online'] ?? false) == true;
    final name = (p['name'] ?? 'AUTO partner').toString();
    final phone = (p['phone'] ?? '').toString();
    final calls = (p['total_calls'] ?? 0).toString();
    final accepted = (p['accepted'] ?? 0).toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(11, 9, 4, 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: const Color(0x26F10B1D),
                borderRadius: BorderRadius.circular(10)),
            child: const Text('🛺', style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      phone.isEmpty
                          ? '$accepted accepted of $calls'
                          : '$phone · $accepted accepted of $calls',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 10.5)),
                ]),
          ),
          Switch(
            value: on,
            activeColor: const Color(0xFFF10B1D),
            onChanged: (v) async {
              final ok = await _store.adminSetAutoPartner(vid, true, v);
              _toast(ok ? null : 'Could not change his duty state.',
                  v ? 'He is ON DUTY.' : 'He is OFF DUTY.');
            },
          ),
        ]),
        // ⭐ v83: his portal opens from here — same as food / ride.
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 34,
          child: OutlinedButton.icon(
            onPressed: () async {
              final err = await _store.adminOpenVendorPortal({'id': vid});
              if (err != null) {
                _toast(err, '');
                return;
              }
              if (!mounted) return;
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const _AdminVendorPortalWrapper()));
              _store.adminCloseVendorPortal();
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 13),
            label: const Text('OPEN AUTO PORTAL',
                style:
                    TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFABB2),
              side: const BorderSide(color: Color(0x80F10B1D)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  /// A ride partner who is not an AUTO partner yet — one tap converts him.
  Widget _autoOtherRow(Map<String, dynamic> o) {
    final vid = (o['vendor_id'] as num?)?.toInt() ?? 0;
    final name = (o['name'] ?? 'Ride partner').toString();
    final plate = (o['vehicle_number'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(11, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF232323)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                if (plate.isNotEmpty)
                  Text(plate,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 10.5)),
              ]),
        ),
        TextButton(
          onPressed: () async {
            final ok = await _store.adminSetAutoPartner(vid, true, true);
            _toast(ok ? null : 'Could not make him an AUTO partner.',
                'He is an AUTO partner now — ON DUTY.');
          },
          child: const Text('MAKE AUTO',
              style: TextStyle(
                  color: Color(0xFFFFABB2),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  /// One line of the AUTO call log — who called, who answered, when.
  Widget _autoCallRow(Map<String, dynamic> c) {
    final st = (c['status'] ?? 'pending').toString();
    final Color tint = st == 'accepted'
        ? const Color(0xFFFFABB2)
        : (st == 'pending' ? const Color(0xFFF10B1D) : const Color(0xFF6A6A6A));
    final who = (c['student_name'] ?? 'A student').toString();
    final rider = (c['rider_name'] ?? '').toString();
    final when = _autoTime((c['created_at_iso'] ?? '').toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF232323)),
      ),
      child: Row(children: [
        Container(
            width: 5,
            height: 26,
            decoration: BoxDecoration(
                color: tint, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    rider.isEmpty
                        ? '$who — no one answered'
                        : '$who → $rider',
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    when.isEmpty
                        ? st.toUpperCase()
                        : '${st.toUpperCase()} · $when',
                    style: TextStyle(
                        color: tint,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ]),
        ),
      ]),
    );
  }

  Future<void> _addAutoPartner() async {
    final name = _autoName.text.trim();
    final phone = _autoPhone.text.trim();
    final pass = _autoPass.text;
    if (name.isEmpty || phone.isEmpty || pass.isEmpty) {
      _toast('Name, phone and password are required.', '');
      return;
    }
    final saved = await _store.adminCreateAutoPartner(name, phone, pass);
    if (!saved) {
      _toast('Could not create that account — is that phone already used?', '');
      return;
    }
    _autoName.clear();
    _autoPhone.clear();
    _autoPass.clear();
    await _store.loadAdminAutoPartners();
    await _store.loadAdminAutoCalls();
    _toast(null, '$name can log in now and gets the AUTO portal.');
  }

  Widget _vendorsPage() {
    if (_vendors.isEmpty) {
      return ListView(
        padding: _pagePadding,
        children: const [
          SizedBox(height: 80),
          Center(
              child: Text('No vendors yet — add one from the Store page.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12))),
        ],
      );
    }
    return Column(children: [
      // ⭐ v84: no AUTO strip above the cards — the swipe row is back to
      // what it was. AUTO partners are managed from the 🛺 button here.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          const Icon(Icons.swipe_rounded, size: 13, color: Color(0xFF8A8A8A)),
          const SizedBox(width: 6),
          Text('Swipe through your ${_vendors.length} vendor portals',
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
          const Spacer(),
          InkWell(
            onTap: _showAutoSheet,
            borderRadius: BorderRadius.circular(7),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0x59F10B1D)),
                color: const Color(0x1AF10B1D),
              ),
              child: const Text('🛺 AUTO',
                  style: TextStyle(
                      color: Color(0xFFFFABB2),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6)),
            ),
          ),
        ]),
      ),
      Expanded(
        child: PageView.builder(
          itemCount: _vendors.length,
          controller: _vendorCardController,
          itemBuilder: (context, i) => _vendorPortalCard(_vendors[i], i),
        ),
      ),
      SizedBox(height: 96 + MediaQuery.of(context).padding.bottom),
    ]);
  }

  Widget _vendorPortalCard(Map v, int index) {
    final type = (v['vendor_type'] ?? 'food') as String;
    final (icon, typeColor) = switch (type) {
      'printout' => ('🖨', const Color(0xFFFF9CA4)),
      'hostel' => ('🛏', const Color(0xFFB58CFF)),
      // ⭐ v66: ride partners (drivers) get their own console.
      'ride' => ('🛺', const Color(0xFFF5F5F5)),
      // ⭐ v81: AUTO partners open their own AUTO portal.
      'auto' => ('🛺', const Color(0xFFFF9CA4)),
      'food' => ('🍔', const Color(0xFFF5F5F5)),
      _ => ('🛍', AppColors.gold),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(5, 4, 5, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.4),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: typeColor.withOpacity(.12),
                border: Border.all(color: typeColor.withOpacity(.45)),
              ),
              child: Text(icon, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v['business_name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(type.toUpperCase(),
                      style: TextStyle(
                          color: typeColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8)),
                ],
              ),
            ),
            Text('${index + 1}/${_vendors.length}',
                style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ]),
          const SizedBox(height: 16),
          _kvRow('Phone (login)', '${v['phone'] ?? ''}'),
          _kvRow('Username', '${v['owner_username'] ?? ''}'),
          _kvRow('UPI ID', '${(v['upi_id'] ?? '').toString().isEmpty ? '—' : v['upi_id']}'),
          if (type == 'food')
            _kvRow('Kitchen',
                (v['kitchen_open'] ?? true) as bool ? 'OPEN' : 'CLOSED'),
          // ⭐ v81: an AUTO partner's duty state, right on his card
          if (type == 'auto') ...[
            _kvRow('Auto duty',
                (v['auto_online'] ?? true) as bool ? 'ON DUTY' : 'OFF DUTY'),
            _kvRow(
                'Auto calls',
                '${v['auto_accepted'] ?? 0} accepted of '
                '${v['auto_calls'] ?? 0}'),
          ],
          // ⭐ v50.1: admin manages the vendor's payment QR directly.
          _qrRow(v),
          const Spacer(),
          // ---- open the EXACT vendor portal ----
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () async {
                final vid = (v['id'] ?? 0) as int;
                // ⭐ Instant: use the pre-warmed session (no network wait);
                // fall back to a live fetch only if pre-warm didn't finish.
                final cached = _portalCache[vid];
                if (cached != null) {
                  _store.adminApplyVendorPortal(cached);
                } else {
                  final err = await _store
                      .adminOpenVendorPortal(Map<String, dynamic>.from(v));
                  if (err != null) {
                    _toast(err, '');
                    return;
                  }
                }
                if (!mounted) return;
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const _AdminVendorPortalWrapper()));
                _store.adminCloseVendorPortal();
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              label: const Text('Open Vendor Portal'),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton(
                  onPressed: () =>
                      _showVendorForm(existing: Map<String, dynamic>.from(v)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF3A3A3A)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Edit',
                      style: TextStyle(color: Color(0xFFDDDDDD))),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton(
                  onPressed: () => _confirmDelete(
                      'Delete vendor "${v['business_name']}"? Their login '
                      'will be removed.', () async {
                    final err = await _store
                        .adminDelete('/api/admin/vendors/${v['id']}/');
                    _toast(err, 'Vendor deleted.');
                    _loadPage(2);
                  }),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0x8CF10B1D)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Delete',
                      style: TextStyle(color: Color(0xFFFF9CA4))),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// ⭐ Payment QR row — shows status + upload / replace / remove actions.
  Widget _qrRow(Map v) {
    final hasQr = (v['qr_url'] ?? '').toString().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        const SizedBox(
          width: 110,
          child: Text('Payment QR',
              style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
        ),
        Expanded(
          child: Row(children: [
            // ⭐ v61: no status text — just the action buttons.
            const Spacer(),
            InkWell(
              onTap: () => _uploadVendorQr(v),
              borderRadius: BorderRadius.circular(7),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFF3A3A3A)),
                ),
                child: Text(hasQr ? 'REPLACE' : 'UPLOAD',
                    style: const TextStyle(
                        color: Color(0xFFDDDDDD),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6)),
              ),
            ),
            if (hasQr) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _confirmDelete(
                    'Remove the payment QR for "${v['business_name']}"?',
                    () async {
                  // ⭐ Optimistic: badge updates instantly.
                  final prev = v['qr_url'];
                  setState(() => v['qr_url'] = '');
                  final err = await _store
                      .adminVendorQr((v['id'] ?? 0) as int, remove: true);
                  if (err != null) setState(() => v['qr_url'] = prev);
                  _toast(err, 'Payment QR removed.');
                }),
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0x8CF10B1D)),
                  ),
                  child: const Text('REMOVE',
                      style: TextStyle(
                          color: Color(0xFFFF9CA4),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .6)),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Future<void> _uploadVendorQr(Map v) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final files = result?.files ?? const [];
    if (files.isEmpty || files.first.bytes == null) return;
    // ⭐ Optimistic: badge flips to "Uploaded" immediately.
    final prev = v['qr_url'];
    setState(() => v['qr_url'] = 'uploading');
    final err = await _store.adminVendorQr(
      (v['id'] ?? 0) as int,
      bytes: files.first.bytes,
      fileName: files.first.name,
    );
    if (err != null) {
      setState(() => v['qr_url'] = prev); // roll back
    }
    _toast(err, 'Payment QR uploaded — students will see it at checkout.');
  }

  Widget _kvRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 110,
          child: Text(k,
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
        ),
        Expanded(
          child: Text(v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  // ==================================================================
  // PAGE 3 — ORDERS
  // ==================================================================
  Widget _ordersPage() {
    return RefreshIndicator(
      color: AppColors.red,
      backgroundColor: const Color(0xFF1B1B1B),
      onRefresh: () => _loadPage(3),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pagePadding,
        children: [
          // ⭐ v61: one tab per store section — scrolls sideways when the
          // admin has created more stores than fit on screen.
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _orderKinds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final k = '${_orderKinds[i]['key']}';
                final t = '${_orderKinds[i]['title']}';
                final active = _orderKind == k;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _orderKind = k;
                      // ⭐ Instant switch from cache; silent refresh after.
                      _orders = _ordersCache[k] ?? [];
                    });
                    _loadPage(3);
                  },
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0x26F10B1D)
                          : const Color(0xFF161616),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: active
                              ? const Color(0x8CF10B1D)
                              : const Color(0xFF2B2B2B)),
                    ),
                    alignment: Alignment.center,
                    child: Text(t.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .4,
                            color: active
                                ? const Color(0xFFFF9CA4)
                                : const Color(0xFF9A9A9A))),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          for (final o in _orders) _orderCard(o),
          if (_orders.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(
                  child: Text('No orders found.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12))),
            ),
        ],
      ),
    );
  }

  Widget _orderCard(Map o) {
    final String title;
    final String subtitle;
    final num total;
    // ⭐ v61: the fulfilling vendor is shown on EVERY order row — stores
    // can have multiple vendors, so this is never ambiguous.
    final vendor = '${o['vendor_name'] ?? ''}';
    if (_orderKind == 'print') {
      title = (o['file_name'] ?? 'Print order') as String;
      subtitle =
          '${vendor.isEmpty ? '' : '$vendor · '}${o['pages']} pages × ${o['copies']}';
      total = (o['total_price'] ?? 0) as num;
    } else if (_orderKind == 'hostel') {
      title = (o['order_no'] ?? '') as String;
      subtitle =
          '${vendor.isEmpty ? '' : '$vendor · '}${o['recipient_name']} · ${o['recipient_mobile']}';
      total = (o['total'] ?? 0) as num;
    } else if (_orderKind == 'ride') {
      // ⭐ v84: rides sit in the Orders tabs like every other store.
      title = (o['order_no'] ?? 'Ride') as String;
      subtitle = '${o['customer_name'] ?? ''}'
          '${vendor.isEmpty ? '' : ' · $vendor'}';
      total = (o['total'] ?? 0) as num;
    } else {
      title = (o['order_number'] ?? '') as String;
      subtitle = '${o['customer_name'] ?? ''}'
          '${vendor.isEmpty ? '' : ' · $vendor'}';
      total = (o['total'] ?? 0) as num;
    }
    final status = (o['status'] ?? '') as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 10)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('₹${total.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: Color(0xFFFFABB2),
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            InkWell(
              onTap: () => _showStatusPicker(o),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D1D1D),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFF343434)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(status.toUpperCase(),
                      style: const TextStyle(
                          color: Color(0xFFD9A94E),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 3),
                  const Icon(Icons.edit, size: 9, color: Color(0xFF8A8A8A)),
                ]),
              ),
            ),
          ],
        ),
      ]),
    );
  }

  Future<void> _showStatusPicker(Map o) async {
    final statuses = switch (_orderKind) {
      'print' => [
          'pending',
          'accepted',
          'printing',
          'ready',
          'completed',
          'cancelled'
        ],
      'hostel' => ['pending', 'accepted', 'delivered', 'cancelled'],
      _ => [
          'pending',
          'accepted',
          'preparing',
          'ready',
          'out_for_delivery',
          'completed',
          'cancelled'
        ],
    };
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Text('Set order status',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          for (final s in statuses)
            ListTile(
              dense: true,
              title: Text(s.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              onTap: () async {
                Navigator.of(ctx).pop();
                final prev = o['status'];
                // ⭐ Optimistic: the chip changes the moment you tap.
                setState(() => o['status'] = s);
                final err = await _store.adminPost(
                    '/api/admin/orders/$_orderKind/${o['id']}/status/',
                    {'status': s});
                if (err != null) {
                  setState(() => o['status'] = prev); // roll back
                }
                _toast(err, 'Status updated to $s.');
              },
            ),
        ]),
      ),
    );
  }

  // ==================================================================
  // PAGE 4 — STUDENTS: allow / restrict app access.
  // ==================================================================
  Widget _studentsPage() {
    return RefreshIndicator(
      color: AppColors.red,
      backgroundColor: const Color(0xFF1B1B1B),
      onRefresh: () => _loadPage(4),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pagePadding,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFF353535)),
            ),
            child: Row(children: [
              const Icon(Icons.search_rounded,
                  size: 16, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _studentSearch,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'Search by name, UID or phone…',
                    hintStyle: TextStyle(
                        color: AppColors.placeholder, fontSize: 12),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            child: Text(
                'Disabling an account logs the student out instantly and '
                'blocks login with a clear message.',
                style: TextStyle(color: AppColors.muted, fontSize: 10)),
          ),
          const SizedBox(height: 4),
          for (final s in _students) _studentRow(s),
          if (_students.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(
                  child: Text('No students found.',
                      style:
                          TextStyle(color: AppColors.muted, fontSize: 12))),
            ),
        ],
      ),
    );
  }

  Widget _studentRow(Map s) {
    final active = (s['active'] ?? true) as bool;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active ? AppColors.line : const Color(0x59F10B1D)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s['name'] ?? ''}  (${s['uid']})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                  '${s['phone'] ?? ''}  ·  ${s['branch'] ?? ''} ${s['year'] ?? ''}'
                  '${active ? '' : '  ·  DISABLED'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: active
                          ? AppColors.muted
                          : const Color(0xFFFF9CA4),
                      fontSize: 10)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 30,
          child: OutlinedButton(
            onPressed: () async {
              final action = active ? 'disable' : 'enable';
              // ⭐ Optimistic: flip instantly, sync in background.
              setState(() => s['active'] = !active);
              final err = await _store.adminPost(
                  '/api/admin/students/${s['id']}/$action/', {});
              if (err != null) {
                setState(() => s['active'] = active); // roll back
              }
              _toast(
                  err,
                  active
                      ? 'Account disabled — the student has been logged out.'
                      : 'Account enabled.');
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: active
                      ? const Color(0x8CF10B1D)
                      : const Color(0x6B38B765)),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle:
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
            child: Text(active ? 'Disable' : 'Enable',
                style: TextStyle(
                    color: active
                        ? const Color(0xFFFF9CA4)
                        : const Color(0xFFF5F5F5))),
          ),
        ),
      ]),
    );
  }

  // ==================================================================
  // PAGE 5 — CONTROL: broadcast, feed posts, coupons, support.
  // ==================================================================
  Widget _controlPage() {
    return RefreshIndicator(
      color: AppColors.red,
      backgroundColor: const Color(0xFF1B1B1B),
      onRefresh: () => _loadPage(5),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _pagePadding,
        children: [
          // ---- broadcast (moved here from Home) ----
          _panel(
            title: 'Broadcast Notification',
            subtitle: 'Send a push notification to every installed app.',
            child: _BroadcastForm(onSend: (title, message) async {
              final err = await _store.adminPost('/api/admin/broadcast/',
                  {'title': title, 'message': message});
              _toast(err, 'Broadcast sent to all devices.');
            }),
          ),
          const SizedBox(height: 12),
          // ---- feed posts ----
          _panel(
            title: 'Feed Posts (${_feedPosts.length})',
            subtitle:
                'Everything on the CUnnect Feed. Pin up to $_maxPinned posts '
                '($_pinnedCount pinned now).',
            child: Column(children: [
              for (final n in _feedPosts.take(40))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Text(n['kind'] == 'poll' ? '🗳️' : '📢',
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                          '${(n['pinned'] ?? false) as bool ? '📌 ' : ''}${n['title'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    InkWell(
                      onTap: () async {
                        final pinned = (n['pinned'] ?? false) as bool;
                        // ⭐ Optimistic: the pin icon flips instantly.
                        setState(() {
                          n['pinned'] = !pinned;
                          _pinnedCount += pinned ? -1 : 1;
                        });
                        final err = await _store.adminPost(
                            '/api/admin/feed/${n['kind']}/${n['id']}/pin/',
                            {'pinned': !pinned});
                        if (err != null) {
                          setState(() {
                            n['pinned'] = pinned; // roll back
                            _pinnedCount += pinned ? 1 : -1;
                          });
                          _toast(err, '');
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                            (n['pinned'] ?? false) as bool
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            size: 15,
                            color: (n['pinned'] ?? false) as bool
                                ? const Color(0xFFFF9CA4)
                                : const Color(0xFF8A8A8A)),
                      ),
                    ),
                    InkWell(
                      onTap: () => _confirmDelete(
                          'Delete this feed post for everyone?', () async {
                        // ⭐ Optimistic: the row disappears instantly.
                        final idx = _feedPosts.indexOf(n);
                        setState(() => _feedPosts.remove(n));
                        final err = await _store.adminPost(
                            '/api/admin/feed/${n['kind']}/${n['id']}/delete/',
                            {});
                        if (err != null && idx >= 0) {
                          setState(() => _feedPosts.insert(idx, n));
                        }
                        _toast(err, 'Post deleted.');
                      }),
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline,
                            size: 16, color: Color(0xFFFF9CA4)),
                      ),
                    ),
                  ]),
                ),
              if (_feedPosts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Nothing on the feed yet.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11)),
                ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton(
                  onPressed: _showFeedComposer,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF3A3A3A)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9)),
                    textStyle: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('+ Create Post',
                      style: TextStyle(color: Color(0xFFDDDDDD))),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // ---- ⭐ v58: banners (create / update / delete) ----
          _panel(
            title: 'Banners (${_banners.length})',
            subtitle:
                'Student home banners — create, edit, toggle or delete.',
            child: Column(children: [
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: () => _showBannerForm(),
                  icon: const Icon(Icons.add_photo_alternate_outlined,
                      size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF9CA4),
                    side: const BorderSide(color: Color(0x8CF10B1D)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                  label: const Text('NEW BANNER'),
                ),
              ),
              const SizedBox(height: 8),
              for (final b in _banners)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 11, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF262626)),
                  ),
                  child: Row(children: [
                    // ⭐ v61: video banners show a play tile, photos a thumb
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: (b['is_video'] ?? false) as bool
                          ? Container(
                              width: 44,
                              height: 30,
                              color: const Color(0x26F10B1D),
                              child: const Icon(Icons.play_circle_outline,
                                  size: 15, color: Color(0xFFFF9CA4)))
                          : '${b['image_url'] ?? ''}'.isEmpty
                              ? Container(
                                  width: 44,
                                  height: 30,
                                  color: const Color(0xFF1E1E1E),
                                  child: const Icon(Icons.image_outlined,
                                      size: 14, color: Color(0xFF5A5A5A)))
                              : Image.network(
                                  ApiConfig.media('${b['image_url']}'),
                                  width: 44,
                                  height: 30,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                      width: 44,
                                      height: 30,
                                      color: const Color(0xFF1E1E1E))),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Position ${b['order'] ?? 0} · '
                              '${(b['is_video'] ?? false) as bool ? 'VIDEO' : 'PHOTO'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                              (b['is_active'] ?? true) as bool
                                  ? 'ACTIVE'
                                  : 'HIDDEN',
                              style: TextStyle(
                                  color: (b['is_active'] ?? true) as bool
                                      ? const Color(0xFFF5F5F5)
                                      : AppColors.muted,
                                  fontSize: 9)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showBannerForm(banner: b as Map),
                      icon: const Icon(Icons.edit_outlined,
                          size: 16, color: Color(0xFF9ECBFF)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 34, minHeight: 34),
                    ),
                    IconButton(
                      onPressed: () => _confirmDelete(
                          'Delete the "${b['title']}" banner?', () async {
                        final idx = _banners.indexOf(b);
                        setState(() => _banners.remove(b));
                        final err = await _store.adminDelete(
                            '/api/admin/banners/${b['id']}/');
                        if (err != null && mounted) {
                          setState(() => _banners.insert(idx, b));
                        }
                        _toast(err, 'Banner deleted.');
                      }),
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: Color(0xFFFF8791)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 34, minHeight: 34),
                    ),
                  ]),
                ),
              if (_banners.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('No banners yet.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          // ---- coupons ----
          _panel(
            title: 'Coupons & Offers (${_coupons.length})',
            subtitle: '% off · ₹ off · Buy 1 Get 1 Free · free add-ons.',
            child: Column(children: [
              for (final c in _coupons)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c['code']}',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800)),
                          Text('${c['label'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 9.5)),
                        ],
                      ),
                    ),
                    Switch(
                      value: (c['is_active'] ?? true) as bool,
                      activeColor: AppColors.red,
                      onChanged: (v) async {
                        // ⭐ Optimistic: flips instantly.
                        setState(() => c['is_active'] = v);
                        final err = await _store.adminPost(
                            '/api/admin/coupons/${c['id']}/',
                            {'is_active': v});
                        if (err != null) {
                          setState(() => c['is_active'] = !v);
                          _toast(err, '');
                        }
                      },
                    ),
                    InkWell(
                      onTap: () => _confirmDelete(
                          'Delete coupon ${c['code']}?', () async {
                        final idx = _coupons.indexOf(c);
                        setState(() => _coupons.remove(c));
                        final err = await _store
                            .adminDelete('/api/admin/coupons/${c['id']}/');
                        if (err != null && idx >= 0) {
                          setState(() => _coupons.insert(idx, c));
                        }
                        _toast(err, 'Coupon deleted.');
                      }),
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline,
                            size: 16, color: Color(0xFFFF9CA4)),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton(
                  onPressed: _showCouponForm,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF3A3A3A)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9)),
                    textStyle: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('+ New Coupon or Offer',
                      style: TextStyle(color: Color(0xFFDDDDDD))),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // ---- support (bottom-most) ----
          _panel(
            title: 'Support Requests (${_support.length})',
            subtitle: 'Tap a request to read it fully and acknowledge it.',
            child: Column(children: [
              for (final r in _support.take(30))
                InkWell(
                  onTap: () => _openSupportDetail(r as Map),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF262626)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${r['subject']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('${r['user']} · ${r['email']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 9.5)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: switch ('${r['status']}') {
                            'resolved' => const Color(0x1738B765),
                            'in_progress' => const Color(0x176EA8FE),
                            _ => const Color(0x17D9A94E),
                          },
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                            '${r['status']}'.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                                color: switch ('${r['status']}') {
                                  'resolved' => const Color(0xFFF5F5F5),
                                  'in_progress' => const Color(0xFF9ECBFF),
                                  _ => const Color(0xFFD9A94E),
                                },
                                fontSize: 8,
                                fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),
                ),
              if (_support.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('No support requests.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11)),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  // ---- support detail: full content + Acknowledge button ----
  void _openSupportDetail(Map r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.support_agent_rounded,
                  size: 18, color: Color(0xFFFF9CA4)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${r['subject']}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 6),
            Text('${r['user']} · ${r['email']}',
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0D),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFF2B2B2B)),
              ),
              child: SingleChildScrollView(
                child: Text('${r['message']}',
                    style: const TextStyle(
                        color: Color(0xFFC9C9C9),
                        fontSize: 12,
                        height: 1.55)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  // ⭐ Optimistic: badge switches to IN PROGRESS instantly.
                  final prev = r['status'];
                  setState(() => r['status'] = 'in_progress');
                  final err = await _store
                      .adminPost('/api/admin/support/${r['id']}/ack/', {});
                  if (err != null) setState(() => r['status'] = prev);
                  _toast(
                      err,
                      'Acknowledged — the user has been notified.');
                },
                icon: const Icon(Icons.task_alt_rounded, size: 16),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                label: const Text('Acknowledged'),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                  'Sends: "Your support request has been acknowledged by '
                  'the CUnnect team."',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 9.5)),
            ),
            const SizedBox(height: 10),
            // ⭐ v58: permanently delete this support request
            SizedBox(
              width: double.infinity,
              height: 41,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _confirmDelete('Delete this support request permanently?',
                      () async {
                    final idx = _support.indexOf(r);
                    setState(() => _support.remove(r));
                    final err = await _store.adminDelete(
                        '/api/admin/support/${r['id']}/delete/');
                    if (err != null && mounted) {
                      setState(() => _support.insert(idx, r));
                    }
                    _toast(err, 'Support request deleted.');
                  });
                },
                icon: const Icon(Icons.delete_outline, size: 15),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF8791),
                  side: const BorderSide(color: Color(0x8CF10B1D)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                label: const Text('Delete Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- forms
  /// ⭐ v58: create / edit a student-home banner (multipart image).
  /// v61: minimal banner form — pick a photo OR video + position. Done.
  Future<void> _showBannerForm({Map? banner}) async {
    final order = TextEditingController(
        text: banner == null ? '' : '${banner['order'] ?? 1}');
    Uint8List? mediaBytes;
    String? mediaName;
    bool mediaIsVideo = false;
    bool busy = false;
    final existingIsVideo = (banner?['is_video'] ?? false) as bool;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 20, 18, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(banner == null ? 'New Banner' : 'Edit Banner',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                  'Just two things: the banner media (photo or video) and '
                  'its position in the carousel.',
                  style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
              const SizedBox(height: 16),
              // ---- media picker card ----
              InkWell(
                onTap: () async {
                  final res = await FilePicker.platform.pickFiles(
                    type: FileType.media, // photos + videos
                    withData: true,
                  );
                  final f = res?.files.firstOrNull;
                  if (f == null || f.bytes == null) return;
                  final n = f.name.toLowerCase();
                  setSheet(() {
                    mediaBytes = f.bytes;
                    mediaName = f.name;
                    mediaIsVideo = n.endsWith('.mp4') ||
                        n.endsWith('.mov') ||
                        n.endsWith('.webm') ||
                        n.endsWith('.mkv') ||
                        n.endsWith('.m4v') ||
                        n.endsWith('.avi') ||
                        n.endsWith('.3gp');
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: mediaBytes != null
                            ? const Color(0x8CF10B1D)
                            : const Color(0xFF303030)),
                  ),
                  child: Column(children: [
                    Icon(
                        mediaBytes != null
                            ? (mediaIsVideo
                                ? Icons.videocam_rounded
                                : Icons.image_rounded)
                            : Icons.add_photo_alternate_outlined,
                        size: 30,
                        color: mediaBytes != null
                            ? const Color(0xFFFF9CA4)
                            : const Color(0xFF6A6A6A)),
                    const SizedBox(height: 8),
                    Text(
                        mediaName ??
                            (banner == null
                                ? 'Tap to pick a photo or video'
                                : existingIsVideo
                                    ? 'Current: video · tap to replace'
                                    : 'Current: photo · tap to replace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: mediaBytes != null
                                ? const Color(0xFFE8E8E8)
                                : AppColors.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                    if (mediaBytes != null) ...[
                      const SizedBox(height: 3),
                      Text(mediaIsVideo ? 'VIDEO' : 'PHOTO',
                          style: const TextStyle(
                              color: Color(0xFF8A8A8A),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2)),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              // ---- position field ----
              TextField(
                controller: order,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 12.5),
                decoration: cunnectInputDecoration(
                    placeholder: 'Position (1 = first, 2 = second…)'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final pos = int.tryParse(order.text.trim()) ?? 0;
                          if (pos < 1) {
                            showCunnectToast(
                                ctx, 'Enter the banner position (1 onwards).',
                                error: true);
                            return;
                          }
                          if (banner == null && mediaBytes == null) {
                            showCunnectToast(
                                ctx, 'Pick a photo or a video first.',
                                error: true);
                            return;
                          }
                          setSheet(() => busy = true);
                          final err = await _store.adminBannerSave(
                            id: banner == null
                                ? null
                                : (banner['id'] as num).toInt(),
                            fields: {'order': '$pos'},
                            imageBytes: mediaBytes,
                            imageName: mediaName,
                            fileField: 'media',
                          );
                          if (!ctx.mounted) return;
                          setSheet(() => busy = false);
                          if (err == null) Navigator.of(ctx).pop();
                          _toast(
                              err,
                              banner == null
                                  ? 'Banner created.'
                                  : 'Banner updated.');
                          _loadPage(5);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(banner == null ? 'CREATE BANNER' : 'SAVE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSectionForm() async {
    final title = TextEditingController();
    final subtitle = TextEditingController();
    final icon = TextEditingController(text: '🛍');
    bool comingSoon = false;
    bool isLocked = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 20, 18, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New Store Section',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                  'Appears as a category on the CUnnect Store page. You can '
                  'then add vendors to it.',
                  style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
              const SizedBox(height: 14),
              Row(children: [
                SizedBox(width: 84, child: _sheetField('Icon', icon)),
                const SizedBox(width: 10),
                Expanded(child: _sheetField('Section title', title)),
              ]),
              _sheetField('Short description (optional)', subtitle),
              Row(children: [
                const Expanded(
                  child: Text('Show as COMING SOON',
                      style: TextStyle(
                          color: Color(0xFFC3C3C3),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: comingSoon,
                  activeColor: AppColors.red,
                  onChanged: (v) => setSheet(() {
                    comingSoon = v;
                    if (v) isLocked = false;
                  }),
                ),
              ]),
              Row(children: [
                const Expanded(
                  child: Text('Lock (users cannot open)',
                      style: TextStyle(
                          color: Color(0xFFC3C3C3),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: isLocked,
                  activeColor: AppColors.red,
                  onChanged: (v) => setSheet(() {
                    isLocked = v;
                    if (v) comingSoon = false;
                  }),
                ),
              ]),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final err = await _store.adminPost('/api/admin/sections/', {
                      'title': title.text.trim(),
                      'subtitle': subtitle.text.trim(),
                      'icon': icon.text.trim(),
                      'coming_soon': comingSoon,
                      'is_locked': isLocked,
                    });
                    _toast(err, 'Section added to the store.');
                    _loadPage(1);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Create Section'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ⭐ v60: edit ANY store section — built-in (CORE) or custom.
  Future<void> _showSectionEditForm(Map sec) async {
    final title = TextEditingController(text: '${sec['title'] ?? ''}');
    final subtitle = TextEditingController(text: '${sec['subtitle'] ?? ''}');
    final icon = TextEditingController(text: '${sec['icon'] ?? '🛍'}');
    bool comingSoon = (sec['coming_soon'] ?? false) as bool;
    bool isLocked = (sec['is_locked'] ?? false) as bool;
    final builtin = (sec['builtin'] ?? false) as bool;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 20, 18, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Edit Store Section',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                if (builtin) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0x66D4C7A3)),
                    ),
                    child: const Text('CORE',
                        style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                  ),
                ],
              ]),
              const SizedBox(height: 4),
              Text(
                  builtin
                      ? 'Changes apply across the app instantly. Built-in '
                          'sections cannot be deleted — switch them off to '
                          'hide them.'
                      : 'Changes apply on the CUnnect Store page instantly.',
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 10.5)),
              const SizedBox(height: 14),
              Row(children: [
                SizedBox(width: 84, child: _sheetField('Icon', icon)),
                const SizedBox(width: 10),
                Expanded(child: _sheetField('Section title', title)),
              ]),
              _sheetField('Short description (optional)', subtitle),
              Row(children: [
                const Expanded(
                  child: Text('Show as COMING SOON',
                      style: TextStyle(
                          color: Color(0xFFC3C3C3),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: comingSoon,
                  activeColor: AppColors.red,
                  onChanged: (v) => setSheet(() {
                    comingSoon = v;
                    if (v) isLocked = false;
                  }),
                ),
              ]),
              // ⭐ v85: LOCK — lock glyph on the hub / store card, tap
              // does nothing (no toast, no open). Hides "COMING SOON".
              Row(children: [
                const Expanded(
                  child: Text('Lock (users cannot open)',
                      style: TextStyle(
                          color: Color(0xFFC3C3C3),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: isLocked,
                  activeColor: AppColors.red,
                  onChanged: (v) => setSheet(() {
                    isLocked = v;
                    if (v) comingSoon = false;
                  }),
                ),
              ]),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                    'Locked tiles show a lock icon. Tapping them does '
                    'nothing — no message, no open.',
                    style: TextStyle(color: AppColors.muted, fontSize: 10)),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final err = await _store
                        .adminPost('/api/admin/sections/${sec['id']}/', {
                      'title': title.text.trim(),
                      'subtitle': subtitle.text.trim(),
                      'icon': icon.text.trim(),
                      'coming_soon': comingSoon,
                      'is_locked': isLocked,
                    });
                    _toast(err, 'Section updated.');
                    _loadPage(1);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showVendorForm({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(
        text: (existing?['business_name'] ?? '') as String);
    final phone =
        TextEditingController(text: (existing?['phone'] ?? '') as String);
    final password = TextEditingController();
    final upi =
        TextEditingController(text: (existing?['upi_id'] ?? '') as String);
    String vtype = (existing?['vendor_type'] ?? 'food') as String;
    // ⭐ v66: the BUILT-IN types are always offered (food / printout /
    // hostel / ride), then any custom store section you created. Earlier
    // the built-ins only appeared when there were no sections at all,
    // so "Ride Partner" never showed up in a live store.
    final sectionKeys = <String>{
      for (final sec in _sections) '${sec['key'] ?? ''}',
    };
    final types = <(String, String)>[
      ('food', '🍔 Food'),
      ('printout', '🖨 Printout'),
      ('hostel', '🛏 Hostel'),
      ('ride', '🛺 Ride Partner'),
      // ⭐ v81: an AUTO partner — he gets his own AUTO portal.
      ('auto', '🛺 AUTO Partner'),
      for (final sec in _sections)
        if (!{'food', 'printout', 'hostel', 'ride', 'auto'}
            .contains('${sec['key'] ?? ''}'))
          ((sec['key'] ?? '') as String,
              '${sec['icon'] ?? '🛍'} ${sec['title'] ?? ''}'),
    ];
    // ⭐ keep the existing vendor's type selectable even if it is a
    // legacy section that is no longer in the list.
    if (vtype.isNotEmpty &&
        !types.any((t) => t.$1 == vtype) &&
        !sectionKeys.contains(vtype)) {
      types.add((vtype, vtype));
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 20, 18, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existing == null ? 'Add Vendor' : 'Edit Vendor',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                _sheetField('Business name', name),
                _sheetField('Phone (login number)', phone,
                    keyboard: TextInputType.phone),
                _sheetField(
                    existing == null
                        ? 'Password'
                        : 'New password (leave empty to keep)',
                    password,
                    obscure: true),
                _sheetField('UPI ID (optional)', upi),
                const SizedBox(height: 4),
                const Text('Section / vendor type',
                    style: TextStyle(
                        color: Color(0xFFAAAAAA),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in types)
                      InkWell(
                        onTap: () => setSheet(() => vtype = t.$1),
                        borderRadius: BorderRadius.circular(9),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: vtype == t.$1
                                ? const Color(0x26F10B1D)
                                : const Color(0xFF0D0D0D),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                                color: vtype == t.$1
                                    ? const Color(0x8CF10B1D)
                                    : const Color(0xFF303030)),
                          ),
                          child: Text(t.$2,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: vtype == t.$1
                                      ? const Color(0xFFFF9CA4)
                                      : const Color(0xFF9A9A9A))),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final body = <String, dynamic>{
                        'business_name': name.text.trim(),
                        'phone': phone.text.trim(),
                        'vendor_type': vtype,
                        'upi_id': upi.text.trim(),
                      };
                      if (password.text.isNotEmpty) {
                        body['password'] = password.text;
                      }
                      final err = existing == null
                          ? await _store.adminPost('/api/admin/vendors/', body)
                          : await _store.adminPost(
                              '/api/admin/vendors/${existing['id']}/', body);
                      _toast(
                          err,
                          existing == null
                              ? 'Vendor created.'
                              : 'Vendor updated.');
                      _loadPage(1);
                      _loadPage(2);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                    child: Text(
                        existing == null ? 'Create Vendor' : 'Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCouponForm() async {
    final code = TextEditingController();
    final value = TextEditingController();
    final minOrder = TextEditingController();
    final offerText = TextEditingController();
    String dtype = 'percentage';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final isOffer = dtype == 'bogo' || dtype == 'addon';
          return Padding(
            padding: EdgeInsets.fromLTRB(
                18, 20, 18, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New Coupon or Offer',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  _sheetField('Code (e.g. WELCOME10)', code),
                  const Text('Offer type',
                      style: TextStyle(
                          color: Color(0xFFAAAAAA),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in const [
                        ('percentage', '% OFF'),
                        ('fixed', '₹ OFF'),
                        ('bogo', 'BUY 1 GET 1'),
                        ('addon', 'FREE ADD-ON'),
                      ])
                        InkWell(
                          onTap: () => setSheet(() => dtype = t.$1),
                          borderRadius: BorderRadius.circular(9),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 9),
                            decoration: BoxDecoration(
                              color: dtype == t.$1
                                  ? const Color(0x26F10B1D)
                                  : const Color(0xFF0D0D0D),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                  color: dtype == t.$1
                                      ? const Color(0x8CF10B1D)
                                      : const Color(0xFF303030)),
                            ),
                            child: Text(t.$2,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: dtype == t.$1
                                        ? const Color(0xFFFF9CA4)
                                        : const Color(0xFF9A9A9A))),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (isOffer)
                    _sheetField(
                        dtype == 'bogo'
                            ? 'Offer details (e.g. Buy 1 Burger, Get 1 Free)'
                            : 'Offer details (e.g. Free Coke with every Pizza)',
                        offerText)
                  else
                    Row(children: [
                      Expanded(
                        child: _sheetField(
                            dtype == 'percentage' ? '% value' : '₹ value',
                            value,
                            keyboard: TextInputType.number),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _sheetField('Min order ₹ (optional)', minOrder,
                            keyboard: TextInputType.number),
                      ),
                    ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        final err =
                            await _store.adminPost('/api/admin/coupons/', {
                          'code': code.text.trim(),
                          'discount_type': dtype,
                          'discount_value':
                              double.tryParse(value.text.trim()) ?? 0,
                          'minimum_order_value':
                              double.tryParse(minOrder.text.trim()) ?? 0,
                          'offer_text': offerText.text.trim(),
                        });
                        _toast(err, 'Coupon created.');
                        _loadPage(5);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                      child: const Text('Create'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showFeedComposer() async {
    final title = TextEditingController();
    final message = TextEditingController();
    final question = TextEditingController();
    final optionControllers = <TextEditingController>[
      TextEditingController(),
      TextEditingController(),
    ];
    Uint8List? mediaBytes;
    String? mediaName;
    bool includePoll = false;
    bool posting = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 20, 18, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Create Feed Post',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                    'Post any mix of text, media (image or video) and a '
                    'poll. Media keeps its original aspect ratio.',
                    style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                const SizedBox(height: 14),
                _sheetField('Title (optional)', title),
                _sheetField('Message (optional)', message, maxLines: 3),
                InkWell(
                  onTap: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.media,
                      withData: true,
                    );
                    final files = result?.files ?? const [];
                    if (files.isNotEmpty && files.first.bytes != null) {
                      setSheet(() {
                        mediaBytes = files.first.bytes;
                        mediaName = files.first.name;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D0D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: mediaBytes != null
                              ? const Color(0x8CF10B1D)
                              : const Color(0xFF303030)),
                    ),
                    child: Row(children: [
                      Icon(
                          mediaBytes != null
                              ? Icons.check_circle_outline
                              : Icons.add_photo_alternate_outlined,
                          size: 17,
                          color: mediaBytes != null
                              ? const Color(0xFFFF9CA4)
                              : const Color(0xFF8A8A8A)),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                            mediaBytes != null
                                ? (mediaName ?? 'Media attached')
                                : 'Attach image or video (optional)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: mediaBytes != null
                                    ? const Color(0xFFFF9CA4)
                                    : const Color(0xFF9A9A9A),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (mediaBytes != null)
                        InkWell(
                          onTap: () => setSheet(() {
                            mediaBytes = null;
                            mediaName = null;
                          }),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Color(0xFF8A8A8A)),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Expanded(
                    child: Text('Include a poll',
                        style: TextStyle(
                            color: Color(0xFFC3C3C3),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                  ),
                  Switch(
                    value: includePoll,
                    activeColor: AppColors.red,
                    onChanged: (v) => setSheet(() => includePoll = v),
                  ),
                ]),
                if (includePoll) ...[
                  _sheetField('Poll question', question),
                  for (var i = 0; i < optionControllers.length; i++)
                    Row(children: [
                      Expanded(
                        child: _sheetField(
                            'Option ${i + 1}', optionControllers[i]),
                      ),
                      if (optionControllers.length > 2)
                        Padding(
                          padding: const EdgeInsets.only(left: 6, bottom: 12),
                          child: InkWell(
                            onTap: () => setSheet(
                                () => optionControllers.removeAt(i)),
                            child: const Icon(Icons.remove_circle_outline,
                                size: 17, color: Color(0xFFFF9CA4)),
                          ),
                        ),
                    ]),
                  if (optionControllers.length < 10)
                    InkWell(
                      onTap: () => setSheet(() =>
                          optionControllers.add(TextEditingController())),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('+ Add option',
                            style: TextStyle(
                                color: Color(0xFFFF9CA4),
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: posting
                        ? null
                        : () async {
                            final options = [
                              for (final c in optionControllers)
                                if (c.text.trim().isNotEmpty) c.text.trim(),
                            ];
                            final hasText = title.text.trim().isNotEmpty ||
                                message.text.trim().isNotEmpty;
                            final hasPoll = includePoll &&
                                question.text.trim().isNotEmpty;
                            if (!hasText && !hasPoll && mediaBytes == null) {
                              showCunnectToast(ctx,
                                  'Add some text, media or a poll first.',
                                  error: true);
                              return;
                            }
                            if (includePoll &&
                                (question.text.trim().isEmpty ||
                                    options.length < 2)) {
                              showCunnectToast(ctx,
                                  'A poll needs a question and at least 2 options.',
                                  error: true);
                              return;
                            }
                            setSheet(() => posting = true);
                            final err = await _store.adminFeedPost(
                              title: title.text.trim(),
                              message: message.text.trim(),
                              question:
                                  includePoll ? question.text.trim() : '',
                              options: includePoll ? options : const [],
                              mediaBytes: mediaBytes,
                              mediaName: mediaName,
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            _toast(err, 'Posted to the CUnnect Feed.');
                            _loadPage(5);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                    child: posting
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Post to Feed'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String message, VoidCallback onYes) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101010),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Are you sure?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        content: Text(message,
            style: const TextStyle(
                color: AppColors.muted, fontSize: 12, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Color(0xFFFF9CA4),
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (yes == true) onYes();
  }

  // ------------------------------------------------------------- shared
  String _compact(dynamic n) {
    final v = (n is num) ? n : num.tryParse('$n') ?? 0;
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  }

  Widget _metric(String label, String value, Color color, IconData icon) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.lineSoft),
          ),
          child: Column(children: [
            Icon(icon, size: 15, color: color.withOpacity(.75)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 8.5)),
          ]),
        ),
      );

  Widget _panel(
          {required String title, String? subtitle, required Widget child}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 10.5)),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Widget _sheetField(String label, TextEditingController controller,
      {TextInputType? keyboard, bool obscure = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            obscureText: obscure,
            maxLines: maxLines,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF0D0D0D),
              contentPadding: const EdgeInsets.all(11),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF353535)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------
// ⭐ Wrapper that shows the vendor's EXACT portal with a small admin strip
// on top, so the admin always knows they are inside a vendor's account.
// ------------------------------------------------------------------------
class _AdminVendorPortalWrapper extends StatelessWidget {
  const _AdminVendorPortalWrapper();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return Scaffold(
      backgroundColor: AppColors.page,
      body: Column(children: [
        SafeArea(
          bottom: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1C0A0D),
              border: Border(bottom: BorderSide(color: Color(0x59F10B1D))),
            ),
            child: Row(children: [
              const Icon(Icons.admin_panel_settings_rounded,
                  size: 14, color: Color(0xFFFF9CA4)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                    'ADMIN VIEW · ${store.vendor.businessName} — exactly '
                    'what this vendor sees',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFFF9CA4),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .4)),
              ),
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0x8CF10B1D)),
                  ),
                  child: const Text('EXIT',
                      style: TextStyle(
                          color: Color(0xFFFF9CA4),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8)),
                ),
              ),
            ]),
          ),
        ),
        const Expanded(child: VendorShell()),
      ]),
    );
  }
}

// ------------------------------------------------------------------------
// ⭐ Minimal elegant trend bars — no chart library needed.
// ------------------------------------------------------------------------
class _TrendBars extends StatelessWidget {
  final List<dynamic> points;
  final String primaryKey;
  final String? secondaryKey;
  final Color primaryColor;
  final Color? secondaryColor;
  final String primaryLabel;
  final String? secondaryLabel;

  const _TrendBars({
    required this.points,
    required this.primaryKey,
    this.secondaryKey,
    required this.primaryColor,
    this.secondaryColor,
    required this.primaryLabel,
    this.secondaryLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
            child: Text('No data yet — stats build up as the app is used.',
                style: TextStyle(color: AppColors.muted, fontSize: 10.5))),
      );
    }
    final shown = points.length > 16
        ? points.sublist(points.length - 16)
        : points;
    num maxV = 1;
    for (final p in shown) {
      final a = (p[primaryKey] ?? 0) as num;
      maxV = a > maxV ? a : maxV;
      if (secondaryKey != null) {
        final b = (p[secondaryKey] ?? 0) as num;
        maxV = b > maxV ? b : maxV;
      }
    }
    return Column(children: [
      SizedBox(
        height: 84,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final p in shown)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              height: 70 *
                                      ((p[primaryKey] ?? 0) as num) /
                                      maxV +
                                  2,
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(.85),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                              ),
                            ),
                          ),
                          if (secondaryKey != null) ...[
                            const SizedBox(width: 1.5),
                            Expanded(
                              child: Container(
                                height: 70 *
                                        ((p[secondaryKey] ?? 0) as num) /
                                        maxV +
                                    2,
                                decoration: BoxDecoration(
                                  color: (secondaryColor ?? primaryColor)
                                      .withOpacity(.7),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 5),
      Row(children: [
        Text('${shown.first['label']}',
            style: const TextStyle(color: AppColors.muted, fontSize: 8.5)),
        const Spacer(),
        Text('${shown.last['label']}',
            style: const TextStyle(color: AppColors.muted, fontSize: 8.5)),
      ]),
      const SizedBox(height: 7),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _legend(primaryColor, primaryLabel),
        if (secondaryKey != null && secondaryLabel != null) ...[
          const SizedBox(width: 14),
          _legend(secondaryColor ?? primaryColor, secondaryLabel!),
        ],
      ]),
    ]);
  }

  Widget _legend(Color c, String label) => Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(color: AppColors.muted, fontSize: 9)),
      ]);
}

// ------------------------------------------------------------------------
class _BroadcastForm extends StatefulWidget {
  final Future<void> Function(String title, String message) onSend;

  const _BroadcastForm({required this.onSend});

  @override
  State<_BroadcastForm> createState() => _BroadcastFormState();
}

class _BroadcastFormState extends State<_BroadcastForm> {
  final _title = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextField(
        controller: _title,
        style: const TextStyle(fontSize: 12.5),
        decoration: _dec('Notification title'),
      ),
      const SizedBox(height: 9),
      TextField(
        controller: _message,
        maxLines: 2,
        style: const TextStyle(fontSize: 12.5),
        decoration: _dec('Message'),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        height: 40,
        child: ElevatedButton(
          onPressed: _sending
              ? null
              : () async {
                  if (_title.text.trim().isEmpty ||
                      _message.text.trim().isEmpty) {
                    showCunnectToast(
                        context, 'Enter both a title and a message.',
                        error: true);
                    return;
                  }
                  setState(() => _sending = true);
                  await widget.onSend(
                      _title.text.trim(), _message.text.trim());
                  if (mounted) {
                    setState(() => _sending = false);
                    _title.clear();
                    _message.clear();
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Send to All Devices'),
        ),
      ),
    ]);
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppColors.placeholder, fontSize: 11.5),
        filled: true,
        fillColor: const Color(0xFF0D0D0D),
        contentPadding: const EdgeInsets.all(11),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF353535)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.red),
        ),
      );
}
