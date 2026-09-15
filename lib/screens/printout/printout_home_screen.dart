import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'my_print_orders_screen.dart';
import 'print_vendor_shop_screen.dart';

/// ⭐ printout_home.html (original) ka exact mirror — hero + vendor cards.
class PrintoutHomeScreen extends StatefulWidget {
  const PrintoutHomeScreen({super.key});

  @override
  State<PrintoutHomeScreen> createState() => _PrintoutHomeScreenState();
}

class _PrintoutHomeScreenState extends State<PrintoutHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadPrintVendors();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final vendors = store.printVendors;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 30),
          children: [
            SizedBox(
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: -4,
                    child: IconButton(
                      icon: const Text('‹',
                          style: TextStyle(
                              color: Colors.white, fontSize: 25, height: 1)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const CunnectWordmark(),
                  Positioned(
                    right: -2,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const MyPrintOrdersScreen())),
                      child: const Text('My Orders',
                          style: TextStyle(
                              color: AppColors.red,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
            // hero
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x59F10B1D)),
                gradient: const LinearGradient(
                  colors: [Color(0xFF291014), Color(0xFF151515)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0x2EF10B1D),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🖨', style: TextStyle(fontSize: 20)),
                  ),
                  const Text('Printout Services',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  const Text(
                      'Choose an approved campus printout partner. Print, '
                      'photocopy, binding and document services.',
                      style: TextStyle(
                          color: Color(0xFFB2B2B2), fontSize: 12, height: 1.4)),
                ],
              ),
            ),
            // section head
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 21, 6, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Available Print Partners',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  Text('${vendors.length} partners',
                      style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                ],
              ),
            ),
            if (vendors.isEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 15),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF343434), style: BorderStyle.solid, width: 1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Center(
                  child: Text('No printout partner is available right now.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
              ),
            for (final v in vendors) _vendorCard(v),
          ],
        ),
      ),
    );
  }

  Widget _vendorCard(PrintVendor v) {
    final initials =
        v.businessName.length >= 2 ? v.businessName.substring(0, 2).toUpperCase() : v.businessName.toUpperCase();
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0x8CF10B1D)),
              color: const Color(0xFF291014),
            ),
            alignment: Alignment.center,
            child: Text(initials,
                style: const TextStyle(
                    color: Color(0xFFFFABB2),
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(v.phone.isEmpty ? 'Campus Print Partner' : v.phone,
                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
              ],
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PrintVendorShopScreen(vendor: v))),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.red),
              ),
              child: const Text('Order Print',
                  style: TextStyle(
                      color: Color(0xFFFF9CA5),
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
