import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// ⭐ v60: Hostel Essentials store — product menu with expandable bars
/// (name + MRP + add-to-cart), a live cart total, and the standard
/// QR / UPI payment section at the bottom.
class HostelEssentialsScreen extends StatefulWidget {
  const HostelEssentialsScreen({super.key});

  @override
  State<HostelEssentialsScreen> createState() => _HostelEssentialsScreenState();
}

class _HostelEssentialsScreenState extends State<HostelEssentialsScreen> {
  final _rName = TextEditingController();
  final _rMobile = TextEditingController();
  final _address = TextEditingController(text: 'Chandigarh University UP');
  final _txnId = TextEditingController();
  bool _busy = false;
  String? _qrB64;
  String? _qrUrl;
  String? _qrErr;
  bool _qrLoading = false;
  String? _error;
  Map<String, dynamic>? _placed; // placed order -> success screen

  /// product id -> quantity in cart
  final Map<int, int> _cart = {};

  /// product id currently expanded (only one open at a time)
  int? _expandedId;

  /// ⭐ v61: product id -> current photo page (dot indicators)
  final Map<int, int> _photoPage = {};

  Timer? _qrDebounce;
  double _qrAmount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<AppStore>();
      await store.loadHostelInfo();
      if (!mounted) return;
      _refreshQr(); // initial QR (no amount until items are added)
    });
  }

  @override
  void dispose() {
    _qrDebounce?.cancel();
    for (final c in [_rName, _rMobile, _address, _txnId]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _products(AppStore store) => [
        for (final p in (store.hostelInfo['products'] as List? ?? []))
          (p as Map).cast<String, dynamic>(),
      ];

  double _total(AppStore store) {
    double t = 0;
    for (final p in _products(store)) {
      final qty = _cart[p['id'] as int] ?? 0;
      if (qty > 0) t += ((p['mrp'] ?? 0) as num).toDouble() * qty;
    }
    return t;
  }

  String _money(num v) =>
      v % 1 == 0 ? '₹${v.toInt()}' : '₹${v.toStringAsFixed(2)}';

  // ---------------- QR (amount-embedded, debounced) ----------------

  void _refreshQr() {
    final store = context.read<AppStore>();
    final vid = store.hostelInfo['vendor_id'];
    if (vid == null) return;
    final amount = _total(store);
    if (amount == _qrAmount && _qrB64 != null) return;
    _qrDebounce?.cancel();
    _qrDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      _qrAmount = amount;
      setState(() {
        _qrLoading = true;
        _qrErr = null;
      });
      final data = await store.fetchUpiQr(
          vid as int, amount > 0 ? amount : null);
      if (!mounted) return;
      setState(() {
        _qrLoading = false;
        if (data == null || data['error'] != null) {
          _qrErr = data == null
              ? 'QR could not load — check your network and retry.'
              : '${data['error']}';
        } else {
          _qrB64 = (data['qr_b64'] ?? '').toString();
          final rawUrl = (data['qr_url'] ?? '').toString();
          _qrUrl = rawUrl.isEmpty ? '' : ApiConfig.media(rawUrl);
        }
      });
    });
  }

  /// QR image widget (URL preferred, else base64) — rendered from one place.
  Widget _qrImage(double size) {
    if (_qrUrl != null && _qrUrl!.isNotEmpty) {
      return Image.network(_qrUrl!, width: size, height: size);
    }
    return Image.memory(base64Decode(_qrB64!), width: size, height: size);
  }

  /// ⭐ QR tap -> full-screen enlarge (dark overlay, tap-anywhere / × close).
  void _showQrFullScreen(BuildContext context, double amount) {
    if (_qrB64 == null && (_qrUrl == null || _qrUrl!.isEmpty)) return;
    showDialog(
      context: context,
      barrierColor: const Color(0xF2000000),
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size.width - 56;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Column(children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 14, 0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => Navigator.of(dialogContext).pop(),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF3A3A3A)),
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 18, color: Color(0xFFCCCCCC)),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20)),
                  child: _qrImage(size.clamp(180.0, 340.0)),
                ),
                const SizedBox(height: 18),
                Text(
                    amount > 0
                        ? 'Scan to pay  ${_money(amount)}'
                        : 'Scan to pay',
                    style: const TextStyle(
                        color: Color(0xFFF2F2F2),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .3)),
                const SizedBox(height: 5),
                const Text('Tap anywhere to close',
                    style: TextStyle(
                        color: Color(0xFF8A8A8A), fontSize: 10.5)),
                const Spacer(),
              ]),
            ),
          ),
        );
      },
    );
  }

  // ---------------- order ----------------

  Future<void> _placeOrder(AppStore store) async {
    if (_busy) return;
    final items = [
      for (final e in _cart.entries)
        if (e.value > 0) {'product_id': e.key, 'qty': e.value},
    ];
    if (items.isEmpty) {
      setState(() =>
          _error = 'Add at least one product to your cart first.');
      return;
    }
    final txn = _txnId.text.trim();
    if (txn.length < 6) {
      setState(() => _error =
          'Paste the UPI transaction ID from your payment app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await store.placeHostelOrder({
      'recipient_name': _rName.text.trim(),
      'recipient_mobile': _rMobile.text.trim(),
      'address': _address.text.trim(),
      'payment_ref': txn,
      'txn_id': txn,
      'items': items,
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res['error'] != null) {
        _error = '${res['error']}';
      } else {
        _placed = (res['order'] as Map?)?.cast<String, dynamic>();
      }
    });
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final info = store.hostelInfo;
    final products = _products(store);
    final upi = (info['upi_id'] ?? '').toString();
    // ⭐ v55: an uploaded QR alone also enables UPI payment.
    final hasQr = (info['has_qr'] ?? false) as bool;
    // ⭐ v61: vendor can close the store from their portal
    final storeOpen = (info['store_open'] ?? true) as bool;
    final total = _total(store);
    final itemCount =
        _cart.values.fold<int>(0, (a, b) => a + (b > 0 ? b : 0));

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: _placed != null
            ? _successView()
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 40),
                children: [
                  SizedBox(
                    height: 64,
                    child: Stack(alignment: Alignment.center, children: [
                      Positioned(
                        left: -8,
                        child: IconButton(
                          icon: const Text('‹',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  height: 1)),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const Text('HOSTEL ESSENTIALS',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5)),
                    ]),
                  ),
                  // ⭐ v61: hero shows the VENDOR-controlled storefront —
                  // store name + description come straight from the portal.
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2A0E12), Color(0xFF151517)]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x59F10B1D)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0x29F10B1D),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: const Color(0x59F10B1D)),
                        ),
                        child: const Center(
                            child:
                                Text('🛏', style: TextStyle(fontSize: 26))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${info['store_name'] ?? ''}'.trim().isNotEmpty
                                    ? '${info['store_name']}'
                                    : 'Set up your room, your way',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(
                                '${info['store_description'] ?? ''}'
                                        .trim()
                                        .isNotEmpty
                                    ? '${info['store_description']}'
                                    : 'Pick only the essentials you need — tap any '
                                        'product to see its details and photos, add '
                                        'it to your cart and pay in one go. '
                                        'Delivered right to your hostel.',
                                style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                    height: 1.45)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                  // ⭐ v61: store closed banner — ordering pauses gracefully
                  if (!storeOpen) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0x1FF10B1D),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0x59F10B1D)),
                      ),
                      child: Row(children: const [
                        Icon(Icons.nightlight_round,
                            size: 15, color: Color(0xFFFFABB2)),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                              'Store is closed right now — browse freely, '
                              'ordering resumes as soon as it reopens.',
                              style: TextStyle(
                                  color: Color(0xFFFFABB2),
                                  fontSize: 11,
                                  height: 1.4,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // ⭐ product menu — expandable bars
                  _sectionTitle('PRODUCTS'),
                  if (products.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.panel,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Center(
                        child: Text(
                            'Products are being added — check back soon.',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 11)),
                      ),
                    ),
                  for (final p in products) _productBar(p),
                  const SizedBox(height: 6),
                  // ⭐ live cart summary
                  if (itemCount > 0) _cartSummary(products, total, itemCount),
                  const SizedBox(height: 14),
                  // recipient manual
                  _sectionTitle('RECIPIENT DETAILS'),
                  _box(_rName, 'Recipient name'),
                  const SizedBox(height: 10),
                  _box(_rMobile, 'Recipient mobile number',
                      keyboard: TextInputType.phone),
                  const SizedBox(height: 10),
                  _box(_address, 'Delivery address'),
                  const SizedBox(height: 14),
                  // payment
                  _sectionTitle(total > 0
                      ? 'PAYMENT — ${_money(total)} UPI TRANSFER'
                      : 'PAYMENT — UPI TRANSFER'),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (upi.isEmpty && !hasQr)
                          const Text(
                              'UPI ID will be added soon — COD until then.',
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 11))
                        else ...[
                          Center(
                            child: _qrLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(26),
                                    child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.red)))
                                : (_qrB64 != null &&
                                            _qrB64!.isNotEmpty) ||
                                        (_qrUrl != null &&
                                            _qrUrl!.isNotEmpty)
                                    ? GestureDetector(
                                        onTap: () => _showQrFullScreen(
                                            context, total),
                                        child: Column(children: [
                                          Container(
                                              padding:
                                                  const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              child: _qrImage(168)),
                                          const SizedBox(height: 7),
                                          Row(
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: const [
                                                Icon(
                                                    Icons
                                                        .zoom_out_map_rounded,
                                                    size: 11,
                                                    color:
                                                        Color(0xFF7A7A7A)),
                                                SizedBox(width: 4),
                                                Text('Tap QR to enlarge',
                                                    style: TextStyle(
                                                        color: Color(
                                                            0xFF7A7A7A),
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        letterSpacing: .3)),
                                              ]),
                                        ]),
                                      )
                                    : InkWell(
                                        onTap: () {
                                          _qrAmount = -1;
                                          _refreshQr();
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text(
                                              _qrErr ??
                                                  'QR could not load — tap to retry',
                                              style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 11)),
                                        ),
                                      ),
                          ),
                          const SizedBox(height: 12),
                          // ---- elegant UPI ID strip (copy chip) ----
                          if (upi.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141414),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                    color: const Color(0xFF2C2C2C)),
                              ),
                              child: Row(children: [
                                const Icon(
                                    Icons
                                        .account_balance_wallet_outlined,
                                    size: 16,
                                    color: Color(0xFFFFD34D)),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('PAY TO UPI ID',
                                          style: TextStyle(
                                              color: Color(0xFF8A8A8A),
                                              fontSize: 8,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.1)),
                                      const SizedBox(height: 2),
                                      Text(upi,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: .4,
                                              color: Color(0xFFF4F4F4))),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    Clipboard.setData(
                                        ClipboardData(text: upi));
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                            content:
                                                Text('UPI ID copied')));
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0x1AF10B1D),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      border: Border.all(
                                          color: const Color(0x40F10B1D)),
                                    ),
                                    child: Row(children: const [
                                      Icon(Icons.copy_rounded,
                                          size: 11,
                                          color: Color(0xFFFFABB2)),
                                      SizedBox(width: 4),
                                      Text('COPY',
                                          style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: .6,
                                              color: Color(0xFFFFABB2))),
                                    ]),
                                  ),
                                ),
                              ]),
                            ),
                          const SizedBox(height: 10),
                          // ⭐ v60: concise bullet-point payment steps
                          const PaymentSteps(),
                        ],
                        const SizedBox(height: 6),
                        _box(_txnId, 'UPI Transaction ID (paste here)'),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Color(0xFFF10B1D), fontSize: 11)),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      // ⭐ v61: ordering pauses while the store is closed
                      onPressed: (_busy || !storeOpen)
                          ? null
                          : () => _placeOrder(store),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              !storeOpen
                                  ? 'STORE CLOSED'
                                  : total > 0
                                      ? 'PLACE ORDER • ${_money(total)}'
                                      : 'PLACE ORDER',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ---------------- product bar (expandable) ----------------

  Widget _productBar(Map<String, dynamic> p) {
    final id = p['id'] as int;
    final qty = _cart[id] ?? 0;
    final expanded = _expandedId == id;
    final mrp = ((p['mrp'] ?? 0) as num);
    // ⭐ v61: live stock — 0 means unlimited (tracking off)
    final stock = ((p['stock'] ?? 0) as num).toInt();
    final photos = [
      for (final ph in (p['photos'] as List? ?? []))
        '${(ph as Map)['url'] ?? ''}',
    ];
    final desc = '${p['description'] ?? ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: expanded ? const Color(0x59F10B1D) : AppColors.line),
      ),
      child: Column(children: [
        // ---- the bar: name left, MRP + add right ----
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () =>
              setState(() => _expandedId = expanded ? null : id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0x2EF10B1D),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                    child: Text('${p['emoji'] ?? '🛒'}',
                        style: const TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Row(children: [
                      AnimatedRotation(
                        turns: expanded ? .5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.keyboard_arrow_down_rounded,
                            size: 13, color: Color(0xFF7A7A7A)),
                      ),
                      const SizedBox(width: 3),
                      Text(expanded ? 'Hide details' : 'View details',
                          style: const TextStyle(
                              color: Color(0xFF7A7A7A),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .3)),
                      // ⭐ v61: low-stock nudge (only when tracking is on)
                      if (stock > 0 && stock <= 5) ...[
                        const SizedBox(width: 7),
                        Text('Only $stock left',
                            style: const TextStyle(
                                color: Color(0xFFFFD34D),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .3)),
                      ],
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(_money(mrp),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFFD34D))),
              const SizedBox(width: 11),
              qty == 0
                  ? _AddButton(
                      onTap: () => setState(() {
                            _cart[id] = 1;
                            _refreshQr();
                          }))
                  : _qtyStepper(id, qty, stock),
            ]),
          ),
        ),
        // ---- dropdown: description + photos ----
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 1, color: const Color(0xFF232323)),
                const SizedBox(height: 11),
                if (desc.isNotEmpty)
                  Text(desc,
                      style: const TextStyle(
                          color: Color(0xFFB9B9B9),
                          fontSize: 11.5,
                          height: 1.5))
                else
                  const Text('No description added yet.',
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 11)),
                // ⭐ v61: swipeable photo gallery — one photo at a time,
                // swipe left/right, with dot indicators underneath.
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 11),
                  SizedBox(
                    height: 158,
                    child: PageView.builder(
                      itemCount: photos.length,
                      onPageChanged: (i) =>
                          setState(() => _photoPage[id] = i),
                      itemBuilder: (_, i) => Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            ApiConfig.media(photos[i]),
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFF1C1C1C),
                              child: const Icon(
                                  Icons.broken_image_outlined,
                                  size: 18,
                                  color: AppColors.muted),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (photos.length > 1) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < photos.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.symmetric(
                                horizontal: 2.5),
                            width: (_photoPage[id] ?? 0) == i ? 15 : 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: (_photoPage[id] ?? 0) == i
                                  ? const Color(0xFFFF9CA4)
                                  : const Color(0xFF3A3A3A),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  /// − qty + stepper shown once the product is in the cart.
  /// ⭐ v61: qty is clamped to live stock when tracking is on (stock > 0).
  Widget _qtyStepper(int id, int qty, int stock) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.red),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => setState(() {
            final next = qty - 1;
            if (next <= 0) {
              _cart.remove(id);
            } else {
              _cart[id] = next;
            }
            _refreshQr();
          }),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: Text('−',
                style: TextStyle(
                    color: Color(0xFFF4F4F4),
                    fontSize: 15,
                    height: 1,
                    fontWeight: FontWeight.w400)),
          ),
        ),
        Text('$qty',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFFF4F4F4))),
        InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () {
            // ⭐ v61: never let the cart exceed the live stock
            final cap = stock > 0 ? (stock < 99 ? stock : 99) : 99;
            if (qty >= cap) {
              if (stock > 0) {
                showCunnectToast(context,
                    'Only $stock in stock — that is the maximum.',
                    error: true);
              }
              return;
            }
            setState(() {
              _cart[id] = qty + 1;
              _refreshQr();
            });
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: Text('+',
                style: TextStyle(
                    color: Color(0xFFF4F4F4),
                    fontSize: 15,
                    height: 1,
                    fontWeight: FontWeight.w400)),
          ),
        ),
      ]),
    );
  }

  /// Cart summary card — every line item + the grand total.
  Widget _cartSummary(
      List<Map<String, dynamic>> products, double total, int count) {
    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF20141A), Color(0xFF141416)]),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x40F10B1D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.shopping_cart_outlined,
                size: 13, color: Color(0xFFFFABB2)),
            const SizedBox(width: 6),
            Text('YOUR CART · $count ITEM${count == 1 ? '' : 'S'}',
                style: const TextStyle(
                    color: Color(0xFFFFABB2),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
          ]),
          const SizedBox(height: 9),
          for (final p in products)
            if ((_cart[p['id'] as int] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        '${p['name']}  ×${_cart[p['id'] as int]}',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                  Text(
                      _money(((p['mrp'] ?? 0) as num) *
                          (_cart[p['id'] as int] ?? 0)),
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE8E8E8))),
                ]),
              ),
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.only(top: 9),
            decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: Color(0xFF2C2430)))),
            child: Row(children: [
              const Expanded(
                child: Text('Total',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
              Text(_money(total),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFFD34D))),
            ]),
          ),
        ],
      ),
    );
  }

  // ---------------- success ----------------

  Widget _successView() {
    final o = _placed!;
    final items = [
      for (final it in (o['items'] as List? ?? []))
        (it as Map).cast<String, dynamic>(),
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          shrinkWrap: true,
          children: [
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Color(0x2416A34A)),
                child: const Icon(Icons.check_circle,
                    size: 46, color: Color(0xFF7ED98B)),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text('ORDER ACCEPTED ✓',
                  style:
                      TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text('Order No: ${o['order_no']}',
                  style: const TextStyle(
                      color: Color(0xFFFFD34D),
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(children: [
                for (final it in items)
                  _kv('${it['name']} ×${it['qty']}',
                      _money(((it['mrp'] ?? 0) as num) *
                          ((it['qty'] ?? 1) as num))),
                if (items.isNotEmpty)
                  const Divider(color: Color(0xFF2A2A2A), height: 16),
                _kv('Recipient', '${o['recipient_name']}'),
                _kv('Mobile', '${o['recipient_mobile']}'),
                _kv('Address', '${o['address']}'),
                _kv('Paid', '${_money((o['total'] ?? 0) as num)} (UPI)'),
              ]),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D1D21),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('BACK TO STORE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- small helpers ----------------

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 11))),
          Text(v,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
      );

  Widget _box(TextEditingController c, String hint,
          {TextInputType? keyboard}) =>
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C0C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF363636)),
        ),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: AppColors.placeholder, fontSize: 12.5),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          ),
        ),
      );
}

/// ⭐ Pop-animated "+" add button — same feel as the food section.
class _AddButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AddButton({required this.onTap});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 340));
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.25), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 1), weight: 55),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: InkWell(
        onTap: () {
          widget.onTap();
          _controller.forward(from: 0);
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.red),
          ),
          alignment: Alignment.center,
          child: const Text('+',
              style: TextStyle(
                  color: Color(0xFFF4F4F4),
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                  height: 1)),
        ),
      ),
    );
  }
}
