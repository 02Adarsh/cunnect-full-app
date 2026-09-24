import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart' show DashboardBanner;
import '../../services/api_client.dart';
import '../../widgets/feed_video.dart';
import '../../services/app_store.dart';
import '../../services/app_portal.dart';
import '../ride/ride_home_screen.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../auth/student_login_screen.dart';
import '../customer/food_home_screen.dart';
import '../notices/notice_board_screen.dart';
import '../customer/my_orders_screen.dart';
import '../store/store_home_screen.dart';
import '../ums/ums_login_screen.dart';
import '../ums/ums_dashboard_screen.dart';
import '../legal_screen.dart';
import '../support_form_screen.dart';
import '../vendor/vendor_login_screen.dart';
import '../vendor/vendor_shell.dart';
import '../../widgets/broadcast_card.dart';

/// Student dashboard hub — same structure as templates/dashboard.html:
/// logo header, greeting, banner slider, floating bottom nav,
/// profile panel and support popup.
class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen>
    with WidgetsBindingObserver {
  final _pageController = PageController();
  int _currentBanner = 0;
  Timer? _notifTimer;

  @override
  void initState() {
    super.initState();
    // ⭐ v75: back on the student side — rider / vendor pushes must not
    // raise their popups or ring here.
    ActivePortal.set(AppPortal.student);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>()
        ..loadDashboardBanners()
        ..loadNotifications()
        ..loadStoreSections() // ⭐ v60: admin flags for Food/Store entries
        ..umsAutoScrape();
      // ⭐ v73: a tapped broadcast opens right here on the home page.
      if (mounted) BroadcastCard.showIfPending(context);
    });
    WidgetsBinding.instance.addObserver(this);
    // ⭐ notifications poll every 30 sec — order accept/reject/delivery instantly
    _notifTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) context.read<AppStore>().loadNotifications();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ⭐ v73: coming back from the notification tray also shows the card
    if (state == AppLifecycleState.resumed && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) BroadcastCard.showIfPending(context);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ⭐ the footer green toast (Order accepted etc.) was removed at the user's request.

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    // ⭐ Account disabled / session revoked -> return to login instantly.
    if (store.studentSessionLost) {
      store.studentSessionLost = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const StudentLoginScreen()),
            (route) => false);
        showCunnectToast(context,
            'Your account has been disabled by the CUnnect team.',
            error: true);
      });
    }
    final banners = store.dashboardBanners;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: [
          // red ambient blur like body::before
          Positioned(
            top: 120,
            right: -150,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.red.withOpacity(.18), blurRadius: 180),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const CunnectWordmark(fontSize: 42, letterSpacing: -2.5),
                      InkWell(
                        onTap: _openProfilePanel,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: store.studentPhotoUrl.isNotEmpty
                              ? ClipOval(
                                  child: CunnectImage(
                                      ApiConfig.media(store.studentPhotoUrl),
                                      width: 48,
                                      height: 48),
                                )
                              : const Icon(Icons.person,
                                  color: Colors.white, size: 22),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text('${_greeting()}, ${store.customerName}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: double.infinity,
                      child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF111111),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: const Color(0xFF252525)),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(.7),
                                        blurRadius: 40,
                                        offset: const Offset(0, 15)),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: PageView.builder(
                                  controller: _pageController,
                                  itemCount: banners.length,
                                  onPageChanged: (i) => setState(() => _currentBanner = i),
                                  itemBuilder: (context, index) => GestureDetector(
                                    onTap: () => _openLightbox(banners[index]),
                                    // ⭐ v62: video banners autoplay muted;
                                    // tapping them opens the fullscreen
                                    // lightbox (tap goes to onTap, not
                                    // play/pause).
                                    child: banners[index].isVideo
                                        ? feedVideo(banners[index].videoUrl,
                                            autoplay: true,
                                            muted: true,
                                            onTap: () => _openLightbox(
                                                banners[index]))
                                        : CunnectImage(banners[index].imageUrl,
                                            fit: BoxFit.contain),
                                  ),
                                ),
                              ),
                              if (banners.length > 1)
                                Positioned(
                                  bottom: 18,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(banners.length, (index) {
                                      final active = index == _currentBanner;
                                      return GestureDetector(
                                        onTap: () {
                                          setState(() => _currentBanner = index);
                                          _pageController.animateToPage(index,
                                              duration: const Duration(milliseconds: 300),
                                              curve: Curves.easeOut);
                                        },
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.symmetric(horizontal: 4),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: active ? Colors.red : const Color(0xFF555555),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 126),
              ],
            ),
          ),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).padding.bottom + 10,
      child: Center(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.symmetric(horizontal: 10),
          // ⭐ v70b: slightly slimmer side padding — every tile keeps
          // more room for its label on small phones.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xF2141414),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0x26FF0000)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 20)],
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              // ⭐ v72: ALL SIX tiles fit on the screen
              // (UMS · Food · Store · Feed · Ride · Partner). The bar is
              // still swipeable, so on a very narrow phone the last
              // icon is one small drag away instead of being squeezed.
              final itemWidth = box.maxWidth / 6;
              // ⭐ v86: ORIGINAL Material icons stay forever. Admin lock
              // only swaps the glyph for a lock and HIDES the label.
              // Tap on a locked tile does nothing (no toast, no open).
              final builtin = context.watch<AppStore>().builtinSections;
              bool lockedOf(String key) =>
                  (builtin[key]?['is_locked'] ?? false) as bool;
              bool activeOf(String key) =>
                  (builtin[key]?['is_active'] ?? true) as bool;
              final items = <({
                IconData icon,
                String label,
                bool locked,
                VoidCallback onTap
              })>[
                (
                  icon: Icons.school,
                  label: 'UMS',
                  locked: false,
                  onTap: () {
                    final store = context.read<AppStore>();
                    final logged = (store.umsUid ?? '').isNotEmpty;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => logged
                            ? const UmsDashboardScreen()
                            : const UmsLoginScreen()));
                  }
                ),
                (
                  icon: Icons.restaurant,
                  label: 'Food',
                  locked: lockedOf('food') || !activeOf('food'),
                  onTap: () {
                    if (lockedOf('food') || !activeOf('food')) return;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const FoodHomeScreen()));
                  }
                ),
                (
                  icon: Icons.shopping_bag,
                  label: 'Store',
                  locked: lockedOf('store') || !activeOf('store'),
                  onTap: () {
                    if (lockedOf('store') || !activeOf('store')) return;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const StoreHomeScreen()));
                  }
                ),
                (
                  icon: Icons.dynamic_feed_outlined,
                  label: 'Feed',
                  locked: lockedOf('feed') || !activeOf('feed'),
                  onTap: () {
                    if (lockedOf('feed') || !activeOf('feed')) return;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const CunnectFeedScreen()));
                  }
                ),
                (
                  icon: Icons.local_taxi_rounded,
                  label: 'Ride',
                  locked: lockedOf('ride') || !activeOf('ride'),
                  onTap: () {
                    if (lockedOf('ride') || !activeOf('ride')) return;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const RideHomeScreen()));
                  }
                ),
                (
                  icon: Icons.storefront,
                  label: 'Partner',
                  locked: false,
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ApiConfig.vendorToken != null
                            ? const VendorShell()
                            : const VendorLoginScreen()));
                  }
                ),
              ];
              return ScrollConfiguration(
                // no glow/overscroll chrome — the bar stays clean
                behavior: const _NoGlowScroll(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (final item in items)
                        SizedBox(
                          width: itemWidth,
                          child: _navItem(
                            item.icon,
                            item.label,
                            item.locked ? () {} : item.onTap,
                            locked: item.locked,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, VoidCallback onTap,
      {bool locked = false}) {
    return _NavItemTile(
        icon: icon, label: label, locked: locked, onTap: onTap);
  }

  void _openProfilePanel() {
    final store = context.read<AppStore>();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Profile',
      barrierColor: Colors.black.withOpacity(.63),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondary) {
        return Align(
          alignment: const Alignment(0.95, -0.82),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 330,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x8CFF0000)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(.62), blurRadius: 50, offset: const Offset(0, 18)),
                ],
              ),
              child: Stack(
                children: [
                  // ⭐ the cross is now INSIDE the Stack — when it sat outside
                  // (negative offset) taps did not work (hit-test clip issue).
                  Positioned(
                    top: 0,
                    right: 0,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xFF373737)),
                        alignment: Alignment.center,
                        child: const Icon(Icons.close,
                            size: 17, color: Colors.white),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x1FFF0000),
                      border: Border.all(color: Colors.red, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: store.studentPhotoUrl.isNotEmpty
                        ? ClipOval(
                            child: CunnectImage(
                                ApiConfig.media(store.studentPhotoUrl),
                                width: 66,
                                height: 66),
                          )
                        : Text(
                            store.customerName.isEmpty
                                ? 'S'
                                : store.customerName[0].toUpperCase(),
                            style: const TextStyle(
                                color: Color(0xFFFF9CA5),
                                fontSize: 25,
                                fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 10),
                  Text(store.customerName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      store.studentEmail.isNotEmpty
                          ? store.studentEmail
                          : 'CUnnect Campus Member',
                      style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
                  const SizedBox(height: 21),
                  Builder(builder: (ctx) {
                    final b = context.read<AppStore>().builtinSections;
                    final locked =
                        (b['my_orders']?['is_locked'] ?? false) as bool;
                    if (locked) {
                      // lock only — no "My Orders" text under it
                      return _profileLink(Icons.lock_rounded, '', () {},
                          locked: true);
                    }
                    return _profileLink(Icons.receipt, 'My Orders', () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const MyOrdersScreen()));
                    });
                  }),
                  _profileLink(Icons.headset_mic, 'Contact Us', () {
                    Navigator.of(context).pop();
                    _openSupportForm();
                  }),
                  // ⭐ v53: CUnnect Feed link removed from the profile
                  // panel at the user's request (feed remains on the
                  // dashboard nav).
                  // ⭐ v52: in-app legal pages
                  _profileLink(Icons.gavel_rounded, 'Terms & Conditions', () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LegalScreen(initialTab: 0)));
                  }),
                  _profileLink(Icons.privacy_tip_outlined, 'Privacy Policy', () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LegalScreen(initialTab: 1)));
                  }),
                  _profileLink(Icons.logout, 'Logout', () {
                    store.studentLogout();
                    Navigator.of(context).pop();
                    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const StudentLoginScreen()),
                        (route) => false);
                  }, logout: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _profileLink(IconData icon, String label, VoidCallback onTap,
      {bool logout = false, bool locked = false}) {
    final fg = locked
        ? const Color(0xFF666666)
        : (logout ? const Color(0xFFFF9CA5) : const Color(0xFFEEEEEE));
    return GestureDetector(
      onTap: locked ? () {} : onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: locked
                  ? const Color(0xFF2A2A2A)
                  : (logout
                      ? const Color(0x59F10B1D)
                      : const Color(0xFF262626))),
        ),
        child: Row(children: [
          Icon(locked ? Icons.lock_rounded : icon,
              size: 18, color: fg),
          const SizedBox(width: 10),
          // ⭐ v86: locked rows hide the real label (no section name).
          Text(locked ? '' : label,
              style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  void _openSupportForm() {
    openCunnectSupportForm(context);
  }

  void _openLightbox(DashboardBanner banner) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Banner',
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondary) => Stack(
        children: [
          Center(
              // ⭐ v62: fullscreen video plays WITH sound, tap = play/pause
              child: banner.isVideo
                  ? feedVideo(banner.videoUrl, autoplay: true)
                  : CunnectImage(banner.imageUrl, fit: BoxFit.contain)),
          Positioned(
            top: 18,
            right: 18,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xE6191919),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF4A4A4A)),
                ),
                alignment: Alignment.center,
                child: const Text('×',
                    style: TextStyle(color: Colors.white, fontSize: 27, height: 1)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}




/// ⭐ v70: keeps the bottom bar's horizontal swipe free of the
/// Android overscroll glow.
class _NoGlowScroll extends ScrollBehavior {
  const _NoGlowScroll();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}


/// ⭐ the icon turns RED instantly on tap and reverts on release — a hover-like flash
class _NavItemTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool locked;
  final VoidCallback onTap;
  const _NavItemTile(
      {required this.icon,
      required this.label,
      this.locked = false,
      required this.onTap});
  @override
  State<_NavItemTile> createState() => _NavItemTileState();
}

class _NavItemTileState extends State<_NavItemTile> {
  bool _pressed = false;
  bool _moved = false;
  Offset? _start;
  Timer? _hold;

  void _light() {
    _hold?.cancel();
    _hold = null;
    if (!_pressed) setState(() => _pressed = true);
  }

  void _dim() {
    _hold?.cancel();
    if (!_pressed) {
      _hold = null;
      return;
    }
    // ⭐ hold the red for a beat so even the quickest tap is visible
    // (the tap itself fires immediately - only the colour lingers).
    _hold = Timer(const Duration(milliseconds: 90), () {
      _hold = null;
      if (mounted && _pressed) setState(() => _pressed = false);
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  /// ⭐ v70b: the tile listens to RAW pointer events on purpose.
  /// Inside the swipeable bar a GestureDetector's onTapDown only fires
  /// once the gesture arena is settled — i.e. together with onTapUp —
  /// so the red flash was never visible. Listener fires the instant
  /// the finger lands, whatever the arena decides later.
  @override
  Widget build(BuildContext context) {
    final locked = widget.locked;
    final color = locked
        ? const Color(0xFF888888)
        : (_pressed ? const Color(0xFFF10B1D) : const Color(0xFFDDDDDD));
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (locked) return; // ⭐ v85: locked tiles never flash or open
        _start = e.position;
        _moved = false;
        _light();
      },
      onPointerMove: (e) {
        if (locked) return;
        // scrolling the bar must NOT leave a tile stuck on red
        if (_start != null && (e.position - _start!).distance > 10) {
          _moved = true;
          _dim();
        }
      },
      onPointerUp: (_) {
        if (locked) return;
        final tapped = !_moved;
        _moved = false;
        _start = null;
        _dim();
        if (tapped) widget.onTap();
      },
      onPointerCancel: (_) {
        if (locked) return;
        _moved = false;
        _start = null;
        _dim();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⭐ v86: locked = lock glyph ONLY. Original Material icon
            // otherwise. Label is HIDDEN when locked (no section name).
            if (locked)
              const Icon(Icons.lock_rounded, size: 22, color: Color(0xFF888888))
            else
              Icon(widget.icon, size: 24, color: color),
            if (!locked) ...[
              const SizedBox(height: 5),
              // ⭐ v70b: the label NEVER wraps — on narrow phones it
              // scales down instead of dropping a letter ("Partne/r").
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(widget.label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(color: color, fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
