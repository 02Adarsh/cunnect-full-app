import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<AppStore>().loadStoreSections());
  }

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
        'hostel essentials mattress pillow bucket jug rope clips hanger mat';
    // ⭐ v60: built-in sections are now admin-controlled — hidden when the
    // admin switches them off, "coming soon" badge when flagged.
    final builtin = context.watch<AppStore>().builtinSections;
    bool activeOf(String key) =>
        (builtin[key]?['is_active'] ?? true) as bool;
    bool soonOf(String key) =>
        (builtin[key]?['coming_soon'] ?? false) as bool;
    bool lockedOf(String key) =>
        (builtin[key]?['is_locked'] ?? false) as bool;
    final printoutOn = _matches(printoutKw) && activeOf('printout');
    final fmcgOn = _matches(fmcgKw);
    final hostelOn = _matches(hostelKw) && activeOf('hostel');
    final customSections = context.watch<AppStore>().storeSections;
    final customOn = [
      for (final sec in customSections)
        if (_matches('${sec['title']} ${sec['subtitle']}'.toLowerCase())) sec,
    ].length;
    final visible = (printoutOn ? 1 : 0) +
        (fmcgOn ? 1 : 0) +
        (hostelOn ? 1 : 0) +
        customOn;

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
                (builtin['hostel']?['icon'] ?? '🛏') as String,
                (builtin['hostel']?['title'] ?? 'Hostel Essentials')
                    as String,
                ((builtin['hostel']?['subtitle'] ?? '') as String).isNotEmpty
                    ? (builtin['hostel']?['subtitle'] ?? '') as String
                    : 'Mattress, pillow, bucket and everything your room needs.',
                lockedOf('hostel')
                    ? null
                    : (soonOf('hostel') ? 'COMING SOON' : null),
                locked: lockedOf('hostel'),
                () {
                  // ⭐ v85: locked = silent (no toast, no open)
                  if (lockedOf('hostel')) return;
                  if (soonOf('hostel')) {
                    showCunnectToast(context,
                        'Hostel Essentials is coming soon on CUnnect.');
                  } else {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const HostelEssentialsScreen()));
                  }
                },
              ),
            if (printoutOn)
              _categoryCard(
                (builtin['printout']?['icon'] ?? '🖨') as String,
                (builtin['printout']?['title'] ?? 'Printout Services')
                    as String,
                ((builtin['printout']?['subtitle'] ?? '') as String)
                        .isNotEmpty
                    ? (builtin['printout']?['subtitle'] ?? '') as String
                    : 'PDF print, color print, photocopy, binding and lamination.',
                lockedOf('printout')
                    ? null
                    : (soonOf('printout') ? 'COMING SOON' : null),
                locked: lockedOf('printout'),
                () {
                  if (lockedOf('printout')) return;
                  if (soonOf('printout')) {
                    showCunnectToast(context,
                        'Printout Services is coming soon on CUnnect.');
                  } else {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PrintoutHomeScreen()));
                  }
                },
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
            // ⭐ Custom sections created from the admin portal.
            for (final sec in context.watch<AppStore>().storeSections)
              if (_matches('${sec['title']} ${sec['subtitle']}'
                  .toLowerCase()))
                _categoryCard(
                  (sec['icon'] ?? '🛍') as String,
                  (sec['title'] ?? '') as String,
                  (sec['subtitle'] ?? '') as String,
                  ((sec['is_locked'] ?? false) as bool)
                      ? null
                      : ((sec['coming_soon'] ?? false) as bool
                          ? 'COMING SOON'
                          : null),
                  locked: (sec['is_locked'] ?? false) as bool,
                  () {
                    if ((sec['is_locked'] ?? false) as bool) return;
                    showCunnectToast(
                        context,
                        (sec['coming_soon'] ?? false) as bool
                            ? '${sec['title']} is coming soon on CUnnect.'
                            : '${sec['title']} — vendors are being onboarded. '
                                'Stay tuned!');
                  },
                ),
          ],
        ),
      ),
    );
  }

  Widget _categoryCard(String icon, String title, String sub, String? badge,
      VoidCallback onTap, {bool locked = false}) {
    return InkWell(
      // ⭐ v86: locked cards swallow the tap — no toast, no navigation.
      // Only the lock glyph shows; the section name is hidden.
      onTap: locked ? null : onTap,
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: locked
                    ? const Color(0x22FFFFFF)
                    : const Color(0x2EF10B1D),
              ),
              alignment: Alignment.center,
              child: locked
                  ? const Icon(Icons.lock_rounded,
                      size: 20, color: Color(0xFFAAAAAA))
                  : Text(icon, style: const TextStyle(fontSize: 20)),
            ),
            if (!locked) ...[
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
                              border: Border.all(
                                  color: const Color(0x66D4C7A3)),
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
                            color: AppColors.muted,
                            fontSize: 11,
                            height: 1.4)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
