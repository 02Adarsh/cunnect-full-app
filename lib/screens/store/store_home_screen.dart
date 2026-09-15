import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../printout/printout_home_screen.dart';
import 'hostel_essentials_screen.dart';

/// ⭐ store_home.html (original) ka exact mirror — hero + search +
/// category grid (Printout live, baaki COMING SOON).
class StoreHomeScreen extends StatefulWidget {
  const StoreHomeScreen({super.key});

  @override
  State<StoreHomeScreen> createState() => _StoreHomeScreenState();
}

class _StoreHomeScreenState extends State<StoreHomeScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(String keywords) =>
      _query.isEmpty || keywords.contains(_query);

  @override
  Widget build(BuildContext context) {
    const printoutKw = 'printout print photocopy binding lamination documents';
    const fmcgKw = 'fmcg groceries snacks drinks daily essentials';
    const hostelKw =
        'hostel essentials pack mattress pillow bucket jug rope clips hanger mat';
    final printoutOn = _matches(printoutKw);
    final fmcgOn = _matches(fmcgKw);
    final hostelOn = _matches(hostelKw);
    final visible =
        (printoutOn ? 1 : 0) + (fmcgOn ? 1 : 0) + (hostelOn ? 1 : 0);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 35),
          children: [
            SizedBox(
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: -8,
                    child: IconButton(
                      icon: const Text('‹',
                          style: TextStyle(
                              color: Colors.white, fontSize: 25, height: 1)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const CunnectWordmark(),
                ],
              ),
            ),
            // hero
            Container(
              padding: const EdgeInsets.all(18),
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
                  const Text('🛍 CAMPUS MARKETPLACE',
                      style: TextStyle(
                          color: Color(0xFFFFABB2),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  const Text('CUnnect Store',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  const Text(
                      'Everything you need around campus, in one place. '
                      'Select a category to explore.',
                      style: TextStyle(
                          color: Color(0xFFB2B2B2), fontSize: 12, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // search
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF353535)),
              ),
              child: Row(
                children: [
                  const Text('⌕',
                      style: TextStyle(color: AppColors.muted, fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (v) =>
                          setState(() => _query = v.toLowerCase().trim()),
                      style: const TextStyle(fontSize: 12.5),
                      decoration: const InputDecoration(
                        hintText: 'Search store categories...',
                        hintStyle: TextStyle(
                            color: AppColors.placeholder, fontSize: 12.5),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // section head
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 21, 2, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Shop by Category',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  Text('$visible categor${visible == 1 ? 'y' : 'ies'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                ],
              ),
            ),
            if (visible == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text('No category found. Try another search term.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
              ),
            if (hostelOn)
              _categoryCard(
                '🛏',
                'Hostel Essentials Pack',
                '8-in-1 — Mattress, Pillow, Bucket, Jug, Rope, Clips, Hanger, Foot Mat. FREE Diet Coke!',
                null,
                () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const HostelEssentialsScreen())),
              ),
            if (printoutOn)
              _categoryCard(
                '🖨',
                'Printout Services',
                'PDF print, color print, photocopy, binding and lamination.',
                null,
                () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PrintoutHomeScreen())),
              ),
            if (fmcgOn)
              _categoryCard(
                '🛒',
                'FMCG & Groceries',
                'Snacks, drinks and daily essentials.',
                'COMING SOON',
                () => showCunnectToast(context,
                    'FMCG & Groceries store is coming soon on CUnnect.'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _categoryCard(String icon, String title, String sub, String? badge,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0x2EF10B1D),
              ),
              alignment: Alignment.center,
              child: Text(icon, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0x66D4C7A3)),
                          ),
                          child: Text(badge,
                              style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(sub,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 11, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
