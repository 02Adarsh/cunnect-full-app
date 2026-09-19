import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'food_home_screen.dart';
import 'order_success_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _noteController = TextEditingController();
  final _txnController = TextEditingController();
  String? _qrB64;
  String? _qrUrl;
  String _qrUpiId = '';
  bool _qrLoading = false;
  bool _placing = false;
  String _paymentMethod = 'upi';
  String? _selectedCoupon;

  @override
  void initState() {
    super.initState();
    // ⭐ v55: UPI is the pre-selected method, so the QR must load
    // immediately on open — previously it only loaded when the user
    // tapped the UPI option, forcing a manual Retry every time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _paymentMethod == 'upi') {
        _loadQr(context.read<AppStore>());
      }
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _txnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    if (store.cart.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.page,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            const CunnectHeader(),
            Expanded(child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Your cart is empty.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const FoodHomeScreen()),
                    (route) => route.isFirst),
                child: const Text('Browse Food',
                    style: TextStyle(
                        color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
          ]),
        ),);
    }

    final applied = store.appliedCoupon;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const CunnectHeader(),
          Expanded(child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 150),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 21, 0, 17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Checkout', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                    SizedBox(height: 3),
                    Text('Almost there — review your order details.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              _divider(),
              _sectionTitle('Contact details'),
              _fieldLabel('Full name', hint: '(from profile)'),
              _readOnlyField(store.customerName),
              _fieldLabel('Mobile number', hint: '(from profile)'),
              _readOnlyField(store.customerPhone),
              const SizedBox(height: 6),
              _fieldLabel('Order note', hint: '(optional)'),
              TextField(
                controller: _noteController,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
                decoration: cunnectInputDecoration(placeholder: 'Any instruction for your order?'),
              ),
              _sectionGap(),
              _sectionTitle('Delivery address'),
              _fieldLabel('Address / hostel / block'),
              const _ReadOnlyMultiline(text: AppStore.defaultAddress),
              const SizedBox(height: 11),
              _fieldLabel('Landmark', hint: '(optional)'),
              _readOnlyField(AppStore.defaultLandmark),
              _sectionGap(),
              _sectionTitle('Have a coupon?'),
              _couponRow(store, applied != null),
              if (applied != null)
                Container(
                  margin: const EdgeInsets.only(top: 9),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x1A3DB260),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x6B3DB260)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: applied.code,
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            TextSpan(
                                text:
                                    ' applied — you save ₹${store.couponDiscount.round()}'),
                          ]),
                          style: const TextStyle(color: Color(0xFF9BE1AD), fontSize: 11.5),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          store.removeCoupon();
                          // ⭐ v56: total changed back — refresh the QR
                          // so the embedded amount stays exact.
                          if (_paymentMethod == 'upi') _loadQr(store);
                          showCunnectToast(context, 'Coupon removed.');
                        },
                        child: const Text('Remove',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                      'Choose an available coupon and tap Apply before placing the order.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
                ),
              _sectionGap(),
              _sectionTitle('Payment method'),
              _paymentOption(
                value: 'upi',
                title: 'UPI',
                subtitle: 'Payment gateway setup pending',
              ),
              const SizedBox(height: 9),
              _paymentOption(
                value: 'cash',
                title: 'Pay at counter',
                subtitle: 'COD is currently unavailable',
                enabled: false,
              ),
              _sectionGap(),
              if (_paymentMethod == 'upi') ...[
                _upiPanel(store),
                _sectionGap(),
              ],
              _sectionTitle('Order summary'),
              for (final cartItem in store.cart)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: CunnectImage(cartItem.foodItem.image,
                            width: 40, height: 40, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DishNameWithMark(
                                name: cartItem.foodItem.name,
                                isVeg: cartItem.foodItem.isVeg,
                                style: const TextStyle(
                                    color: Color(0xFFEDEDED),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('Qty: ${cartItem.quantity}',
                                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      Text('₹${cartItem.subtotal.round()}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              _priceRow('Item total', '₹${store.cartTotal.round()}'),
              if (applied != null)
                _priceRow('Coupon discount (${applied.code})',
                    '− ₹${store.couponDiscount.round()}',
                    valueColor: const Color(0xFF9BE1AD)),
              _priceRow('Delivery fee', 'FREE'),
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('To pay',
                        style: TextStyle(
                            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    Text('₹${store.finalTotal.round()}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          _footer(context, store),
        ],
      ),
    ),
        ]),
      ),);
  }

  Widget _summaryPlaceholder() => Container(
      width: 40, height: 40, color: const Color(0xFF222222),
      alignment: Alignment.center, child: const Text('🍽️', style: TextStyle(fontSize: 15)));

  Widget _couponRow(AppStore store, bool hasApplied) {
    final available = store.availableCoupons;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: null,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.muted),
                dropdownColor: const Color(0xFF1C1C1C),
                hint: Text(
                  hasApplied
                      ? '${store.appliedCoupon?.code} — ${store.appliedCoupon?.discountLabel} applied'
                      : 'Select a coupon',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: hasApplied ? const Color(0xFF9BE1AD) : AppColors.placeholder),
                ),
                items: [
                  for (final coupon in available)
                    DropdownMenuItem(
                      value: coupon.code,
                      child: Text('${coupon.code} — ${coupon.discountLabel}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFFF6F6F6))),
                    ),
                ],
                onChanged: (value) => setState(() => _selectedCoupon = value),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 42,
          child: OutlinedButton(
            onPressed: () async {
              final result = await store.applyCoupon(_selectedCoupon ?? '');
              if (!context.mounted) return;
              // ⭐ v56: the total changed — refresh the QR so the amount
              // embedded in it (auto-filled on scan) stays exact.
              if (result.success && _paymentMethod == 'upi') {
                _loadQr(store);
              }
              if (result.showPopup) {
                _showCouponPopup(result.message);
              } else {
                showCunnectToast(context, result.message, error: !result.success);
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: AppColors.red),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Apply'),
          ),
        ),
      ],
    );
  }

  void _showCouponPopup(String message) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Coupon applied',
      barrierColor: Colors.black.withOpacity(.72),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondary) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340,
              padding: const EdgeInsets.fromLTRB(23, 48, 23, 21),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xB3F10B1D)),
                gradient: const LinearGradient(
                    begin: Alignment(-0.7, -0.7),
                    end: Alignment(0.7, 0.7),
                    colors: [Color(0xFF242424), Color(0xFF111111)]),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(.7), blurRadius: 48, offset: const Offset(0, 18)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('COUPON APPLIED',
                      style: TextStyle(
                          color: Color(0xFFA9A9A9),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .9)),
                  const SizedBox(height: 9),
                  const Text('Discount unlocked!',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 11),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFC4C4C4), fontSize: 13, height: 1.45)),
                  const SizedBox(height: 19),
                  SizedBox(
                    width: double.infinity,
                    height: 47,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      child: const Text('YAY!'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _paymentOption({required String value, required String title, required String subtitle, bool enabled = true}) {
    final selected = enabled && _paymentMethod == value;
    return InkWell(
      onTap: !enabled
          ? () => showCunnectToast(context, 'COD is currently unavailable', error: true)
          : () {
              setState(() => _paymentMethod = value);
              if (value == 'upi') _loadQr(context.read<AppStore>());
            },
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? const Color(0x14F10B1D) : AppColors.cardDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.red : const Color(0xFF343434)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 19, color: selected ? AppColors.red : AppColors.muted),
              const SizedBox(width: 11),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF242424)),
                alignment: Alignment.center,
                child: const Text('₹', style: TextStyle(color: AppColors.red, fontSize: 14)),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, AppStore store) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(14, 11, 14, MediaQuery.of(context).padding.bottom + 12),
        decoration: const BoxDecoration(
          color: AppColors.footerBg,
          border: Border(top: BorderSide(color: Color(0xFF363636))),
          boxShadow: [BoxShadow(color: Color(0x4D000000), blurRadius: 28, offset: Offset(0, -9))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total amount', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                Text('₹${store.finalTotal.round()}',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: _placing ? null : () async {
                  if (_paymentMethod == 'upi') {
                    if (_txnController.text.trim().length < 6) {
                      showCunnectToast(context,
                          'Paste the full transaction ID from your payment app.',
                          error: true);
                      return;
                    }
                  }
                  setState(() => _placing = true);
                  String? error;
                  try {
                    error = await store.placeOrder(
                        paymentMethod: _paymentMethod,
                        orderNote: _noteController.text.trim(),
                        txnId: _txnController.text.trim());
                  } finally {
                    if (mounted) setState(() => _placing = false);
                  }
                  if (!context.mounted) return;
                  if (error != null) {
                    showCunnectToast(context, error, error: true);
                  } else {
                    Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const OrderSuccessScreen()),
                        (route) => route.isFirst);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                child: _placing
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Text('Place Order'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- helpers ----------
  Widget _divider() => const Divider(height: 1, thickness: 1, color: AppColors.line);

  Widget _sectionGap() => const SizedBox(height: 19);

  Future<void> _loadQr(AppStore store) async {
    if (store.cart.isEmpty) return;
    setState(() => _qrLoading = true);
    final data = await store.fetchUpiQr(
        store.cart.first.foodItem.vendorId, store.finalTotal.round());
    if (!mounted) return;
    setState(() {
      _qrLoading = false;
      _qrB64 = (data?['qr_b64'] ?? '') as String;
      // ⭐ v54: uploaded QR arrives as a relative /media/ URL — make
      // it absolute so Image.network can actually load it.
      final rawUrl = (data?['qr_url'] ?? '') as String;
      _qrUrl = rawUrl.isEmpty ? '' : ApiConfig.media(rawUrl);
      _qrUpiId = (data?['upi_id'] ?? '') as String;
    });
  }

  Widget _upiPanel(AppStore store) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('UPI Payment',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Center(
            child: _qrLoading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: SizedBox(width: 26, height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5)),
                  )
                : (_qrB64 == null || _qrB64!.isEmpty) &&
                        (_qrUrl == null || _qrUrl!.isEmpty)
                    ? Column(children: [
                        const Text('QR could not load — the partner has not set a UPI.',
                            style: TextStyle(color: AppColors.muted, fontSize: 11)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _loadQr(store),
                          child: const Text('Retry',
                              style: TextStyle(color: Color(0xFFFF9CA5),
                                  fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ])
                    : GestureDetector(
                        onTap: () => _showQrFullScreen(context, store),
                        child: Column(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _qrImage(168),
                          ),
                          const SizedBox(height: 7),
                          Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.zoom_out_map_rounded,
                                    size: 11, color: Color(0xFF7A7A7A)),
                                SizedBox(width: 4),
                                Text('Tap QR to enlarge',
                                    style: TextStyle(
                                        color: Color(0xFF7A7A7A),
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: .3)),
                              ]),
                        ]),
                      ),
          ),
          // ⭐ v55: elegant UPI ID strip (copy chip) — exactly like the
          // hostel store payment section.
          if (_qrUpiId.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFF2C2C2C)),
              ),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 16, color: Color(0xFFFFD34D)),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PAY TO UPI ID',
                          style: TextStyle(
                              color: Color(0xFF8A8A8A),
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1)),
                      const SizedBox(height: 2),
                      Text(_qrUpiId,
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
                    Clipboard.setData(ClipboardData(text: _qrUpiId));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('UPI ID copied')));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x1AF10B1D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x40F10B1D)),
                    ),
                    child: Row(children: const [
                      Icon(Icons.copy_rounded,
                          size: 11, color: Color(0xFFFFABB2)),
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
          ],
          const SizedBox(height: 12),
          // ⭐ v60: concise bullet-point payment steps
          const PaymentSteps(),
          const SizedBox(height: 8),
          _fieldLabel('Transaction ID', hint: '(paste the full ID after payment)'),
          TextField(
            controller: _txnController,
            keyboardType: TextInputType.text,
            style: const TextStyle(fontSize: 13),
            decoration: cunnectInputDecoration(placeholder: 'e.g. 509912345678'),
          ),
        ],
      ),
    );
  }

  /// QR image widget (URL preferred, else base64) — one render path.
  Widget _qrImage(double size) {
    if (_qrUrl != null && _qrUrl!.isNotEmpty) {
      return Image.network(_qrUrl!, width: size, height: size);
    }
    return Image.memory(base64Decode(_qrB64!), width: size, height: size);
  }

  /// ⭐ QR tap -> full-screen enlarge (dark overlay, tap-anywhere / × close)
  /// — same experience as the hostel store payment section.
  void _showQrFullScreen(BuildContext context, AppStore store) {
    final hasQr = (_qrB64 != null && _qrB64!.isNotEmpty) ||
        (_qrUrl != null && _qrUrl!.isNotEmpty);
    if (!hasQr) return;
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
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: const Color(0xFF3A3A3A)),
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: _qrImage(size),
                      ),
                      const SizedBox(height: 14),
                      Text('Scan to pay ₹${store.finalTotal.round()}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      if (_qrUpiId.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(_qrUpiId,
                            style: const TextStyle(
                                color: Color(0xFFBDBDBD), fontSize: 11)),
                      ],
                      const SizedBox(height: 6),
                      const Text('Tap anywhere to close',
                          style: TextStyle(
                              color: Color(0xFF8A8A8A), fontSize: 10)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title,
            style: const TextStyle(color: Color(0xFFF2F2F2), fontSize: 14, fontWeight: FontWeight.w800)),
      );

  Widget _fieldLabel(String label, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$label '),
          if (hint != null)
            TextSpan(
                text: hint,
                style: const TextStyle(fontWeight: FontWeight.w400, color: Color(0xFF777777))),
        ]), style: const TextStyle(color: Color(0xFFB7B7B7), fontSize: 11.5, fontWeight: FontWeight.w600)),
      );

  Widget _readOnlyField(String value) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 42,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF303030)),
        ),
        child: Text(value, style: const TextStyle(color: Color(0xFFC8C8C8), fontSize: 13)),
      );

  Widget _priceRow(String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(value,
                style: TextStyle(color: valueColor ?? AppColors.muted, fontSize: 12)),
          ],
        ),
      );
}

class _ReadOnlyMultiline extends StatelessWidget {
  final String text;

  const _ReadOnlyMultiline({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF303030)),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFFC8C8C8), fontSize: 13, height: 1.4)),
    );
  }
}
