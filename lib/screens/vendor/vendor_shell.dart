import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';

import '../ride/auto_console_screen.dart';
import '../../theme/app_colors.dart';
import '../printout/print_vendor_dashboard_screen.dart';
import 'hostel_products_screen.dart';
import 'hostel_vendor_screen.dart';
import 'vendor_dashboard_screen.dart';
import 'vendor_earnings_screen.dart';
import 'vendor_menu_screen.dart';
import 'vendor_profile_screen.dart';
import '../ride/rider_console_screen.dart';

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
        // ⭐ v61: the hostel vendor's tab is their product catalogue
        if (store.vendor.vendorType == 'hostel') {
          store.loadVendorHostelProducts();
        } else {
          store.loadVendorMenu();
        }
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
        // ⭐ v61: hostel vendor manages their whole catalogue here —
        // products, stock, photos, storefront description, open/close.
        if (isHostel) return const HostelProductsScreen(key: ValueKey('store'));
        return const VendorMenuScreen(key: ValueKey('menu'), inShell: true);
      case 3:
        return const VendorEarningsScreen(key: ValueKey('earnings'), inShell: true);
      default:
        return const VendorProfileScreen(key: ValueKey('profile'), inShell: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ Print partners get their own dedicated dashboard (orders +
    // settings) — the food nav tabs are not relevant for them.
    if (context.watch<AppStore>().vendor.vendorType == 'printout') {
      return const PrintVendorDashboardScreen();
    }
    // ⭐ v81: AUTO partners are their own account type — they get the
    // AUTO portal and never see car bookings, fares or ride OTPs.
    if (context.watch<AppStore>().vendor.vendorType == 'auto') {
      return const AutoConsoleScreen();
    }
    // ⭐ v66: ride partners get their own console (requests, OTP,
    // pricing) — the food/orders tabs make no sense for a driver.
    if (context.watch<AppStore>().vendor.vendorType == 'ride') {
      return const RiderConsoleScreen();
    }
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
                  child: _navItem(
                      i,
                      const ['⌂', '▣', '☰', '₹', '◉'][i],
                      [
                        'Home',
                        'Orders',
                        // ⭐ v61: hostel partners see "Store", not "Menu"
                        context.watch<AppStore>().vendor.vendorType ==
                                'hostel'
                            ? 'Store'
                            : 'Menu',
                        'Earnings',
                        'Profile'
                      ][i])),
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
