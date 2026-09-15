import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';

import '../../theme/app_colors.dart';
import 'hostel_vendor_screen.dart';
import 'vendor_dashboard_screen.dart';
import 'vendor_earnings_screen.dart';
import 'vendor_menu_screen.dart';
import 'vendor_profile_screen.dart';

/// Vendor portal shell with the same 5-tab bottom nav
/// (Home, Orders, Menu, Earnings, Profile) as vendor_dashboard.html.
class VendorShell extends StatefulWidget {
  const VendorShell({super.key});

  @override
  State<VendorShell> createState() => _VendorShellState();
}

class _VendorShellState extends State<VendorShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = context.read<AppStore>();
      store.refreshVendorDashboard();
      store.loadVendorMenu();
    });
  }

  void _loadTab(int index) {
    final store = context.read<AppStore>();
    switch (index) {
      case 0:
      case 1:
        store.refreshVendorDashboard();
        break;
      case 2:
        store.loadVendorMenu();
        break;
      case 3:
        store.loadVendorEarnings();
        break;
      default:
        break;
    }
  }

  Widget get _body {
    final isHostel = context.read<AppStore>().vendor.vendorType == 'hostel';
    switch (_tab) {
      case 0:
      case 1:
        if (isHostel) return const HostelVendorScreen();
        return _tab == 0
            ? const VendorDashboardScreen(key: ValueKey('home'))
            : const VendorDashboardScreen(
                key: ValueKey('orders'), focusOrders: true);
      case 2:
        if (isHostel) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Text(
                  '🛏 Hostel Essentials Pack\n8-in-1 • ₹1799\n\nOrders appear in the "Orders" tab.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9d9d9d), fontSize: 12, height: 1.6)),
            ),
          );
        }
        return const VendorMenuScreen(key: ValueKey('menu'), inShell: true);
      case 3:
        return const VendorEarningsScreen(key: ValueKey('earnings'), inShell: true);
      default:
        return const VendorProfileScreen(key: ValueKey('profile'), inShell: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(bottom: false, child: _body),
      bottomNavigationBar: Container(
        height: 72 + MediaQuery.of(context).padding.bottom,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          color: Color(0xFF141414),
          border: Border(top: BorderSide(color: Color(0x73F10B1D))),
          boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, -10))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < 5; i++)
              Expanded(
                  child: _navItem(i, const ['⌂', '▣', '☰', '₹', '◉'][i],
                      const ['Home', 'Orders', 'Menu', 'Earnings', 'Profile'][i])),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int index, String icon, String label) {
    final active = _tab == index;
    return InkWell(
      onTap: () {
        setState(() => _tab = index);
        _loadTab(index);
      },
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon,
                style: TextStyle(
                    fontSize: 18, height: 1, color: active ? AppColors.red : const Color(0xFFAAAAAA))),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: active ? AppColors.red : const Color(0xFFAAAAAA),
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
