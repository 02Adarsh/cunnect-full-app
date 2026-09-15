import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart' show DashboardBanner;
import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../auth/student_login_screen.dart';
import '../chat/chat_home_screen.dart';
import '../chat/chat_under_construction_screen.dart';
import '../customer/food_home_screen.dart';
import '../customer/my_orders_screen.dart';
import '../store/store_home_screen.dart';
import '../ums/ums_login_screen.dart';
import '../ums/ums_dashboard_screen.dart';
import '../support_form_screen.dart';
import '../vendor/vendor_login_screen.dart';
import '../vendor/vendor_shell.dart';

/// Student dashboard hub — same structure as templates/dashboard.html:
/// logo header, greeting, banner slider, floating bottom nav,
/// profile panel and support popup.
class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  final _pageController = PageController();
  int _currentBanner = 0;
  Timer? _notifTimer;
  final Set<int> _shownNotif = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>()
        ..loadDashboardBanners()
        ..loadNotifications()
        ..umsAutoScrape();
    });
    // ⭐ har 30 sec notifications poll — order accept/reject/delivery turant
    _notifTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) context.read<AppStore>().loadNotifications();
    });
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _maybeNotifToast(AppStore store) {
    final fresh = store.notifications
        .where((n) => !n.isRead && !_shownNotif.contains(n.id))
        .toList();
    if (fresh.isEmpty) return;
    final latest = fresh.first;
    _shownNotif.add(latest.id);
    showCunnectToast(context, '${latest.title}: ${latest.message}');
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final banners = store.dashboardBanners;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeNotifToast(store));

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
                                    child: CunnectImage(banners[index].imageUrl, fit: BoxFit.contain),
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xF2141414),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0x26FF0000)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 20)],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.school, 'UMS', () {
                final store = context.read<AppStore>();
                final logged = (store.umsUid ?? '').isNotEmpty;
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => logged
                        ? const UmsDashboardScreen()
                        : const UmsLoginScreen()));
              }),
              _navItem(Icons.restaurant, 'Food', () {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const FoodHomeScreen()));
              }),
              _navItem(Icons.shopping_bag, 'Store', () {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const StoreHomeScreen()));
              }),
              _navItem(Icons.chat_bubble_outline, 'Chat', () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ChatUnderConstructionScreen()));
              }),
              _navItem(Icons.storefront, 'Partner', () {
                // ⭐ vendor logged-in hai to dobara login nahi — seedha dashboard
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ApiConfig.vendorToken != null
                        ? const VendorShell()
                        : const VendorLoginScreen()));
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, VoidCallback onTap) {
    return _NavItemTile(icon: icon, label: label, onTap: onTap);
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
              padding: const EdgeInsets.fromLTRB(18, 32, 18, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x8CFF0000)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(.62), blurRadius: 50, offset: const Offset(0, 18)),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -32,
                    right: -18,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xFF373737)),
                        alignment: Alignment.center,
                        child: const Text('×',
                            style: TextStyle(color: Colors.white, fontSize: 20, height: 1)),
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
                  _profileLink(Icons.receipt, 'My Orders', () {
                    Navigator.of(context).pop();
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const MyOrdersScreen()));
                  }),
                  _profileLink(Icons.headset_mic, 'Contact Us', () {
                    Navigator.of(context).pop();
                    _openSupportForm();
                  }),
                  _profileLink(Icons.chat_bubble_outline, 'Chat', () {
                    Navigator.of(context).pop();
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                        builder: (_) => const ChatUnderConstructionScreen()));
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

  Widget _profileLink(IconData icon, String label, VoidCallback onTap, {bool logout = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: logout ? const Color(0x61FF0000) : const Color(0xFF303030)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.red),
            const SizedBox(width: 11),
            Text(label,
                style: TextStyle(
                    color: logout ? const Color(0xFFFF9CA5) : const Color(0xFFE8E8E8),
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
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
          Center(child: CunnectImage(banner.imageUrl, fit: BoxFit.contain)),
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




/// ⭐ tap pe icon turant RED hota hai, chhodte hi wapas — hover jaisa flash
class _NavItemTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavItemTile(
      {required this.icon, required this.label, required this.onTap});
  @override
  State<_NavItemTile> createState() => _NavItemTileState();
}

class _NavItemTileState extends State<_NavItemTile> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final color =
        _pressed ? const Color(0xFFF10B1D) : const Color(0xFFDDDDDD);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 24, color: color),
            const SizedBox(height: 5),
            Text(widget.label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
