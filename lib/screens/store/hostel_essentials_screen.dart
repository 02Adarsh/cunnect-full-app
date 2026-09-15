import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../theme/app_colors.dart';

/// ⭐ Hostel Essentials 8-in-1 pack — description + order (auto login
/// details + manual recipient) + UPI payment + ORDER ACCEPTED screen.
class HostelEssentialsScreen extends StatefulWidget {
  const HostelEssentialsScreen({super.key});

  @override
  State<HostelEssentialsScreen> createState() => _HostelEssentialsScreenState();
}

class _HostelEssentialsScreenState extends State<HostelEssentialsScreen> {
  final _rName = TextEditingController();
  final _rMobile = TextEditingController();
  final _address = TextEditingController(text: 'Chandigarh University');
  final _senderUpi = TextEditingController();
  final _txn4 = TextEditingController();
  bool _busy = false;
  String? _qrB64;
  String? _qrUrl;
  String? _qrErr;
  bool _qrLoading = false;
  String? _error;
  Map<String, dynamic>? _placed; // placed order -> success screen

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<AppStore>();
      final info = await store.loadHostelInfo();
      final vid = info['vendor_id'];
      if (!mounted || vid == null) return;
      _loadQr(store, vid as int);
    });
  }

  @override
  void dispose() {
    for (final c in [_rName, _rMobile, _address, _senderUpi, _txn4]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadQr(AppStore store, int vendorId) async {
    setState(() {
      _qrLoading = true;
      _qrErr = null;
    });
    final data = await store.fetchUpiQr(vendorId, 1799);
    if (!mounted) return;
    setState(() {
      _qrLoading = false;
      if (data == null || data['error'] != null) {
        _qrErr = data == null
            ? 'QR could not load — check your network and retry.'
            : '${data['error']}';
      } else {
        _qrB64 = (data['qr_b64'] ?? '').toString();
        _qrUrl = (data['qr_url'] ?? '').toString();
      }
    });
  }

  Future<void> _placeOrder(AppStore store) async {
    if (_busy) return;
    final sender = _senderUpi.text.trim();
    final t4 = _txn4.text.trim();
    if (sender.isEmpty) {
      setState(() => _error = 'Enter your UPI ID.');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(t4)) {
      setState(() => _error = 'Enter the last 4 digits of the transaction ID.');
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
      'payment_ref': t4,
      'customer_upi': sender,
      'txn_last4': t4,
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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final info = store.hostelInfo;
    final auto = (info['auto'] as Map?)?.cast<String, dynamic>() ?? {};
    final items = (info['items'] as List?)?.map((e) => '$e').toList() ??
        ['Mattress', 'Pillow', 'Bucket', 'Bathing Jug', 'Rope', 'Clothes Clips', 'Hanger', 'Foot Mat'];
    final upi = (info['upi_id'] ?? '').toString();

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: _placed != null ? _successView() : ListView(
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
                            color: Colors.white, fontSize: 25, height: 1)),
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
            // ⭐ hero details card (banner hata diya)
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
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
                              Text('🎒', style: TextStyle(fontSize: 26))),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hostel Essentials Pack',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800)),
                          SizedBox(height: 3),
                          Text('8-in-1 starter kit — everything your room needs',
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 11)),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Text('₹1799',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFFD34D))),
                    const SizedBox(width: 10),
                    Text('WORTH ₹${info['worth'] ?? 2500}+',
                        style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0x2416A34A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('🥤 ${info['freebie'] ?? 'FREE Diet Coke'}',
                          style: const TextStyle(
                              color: Color(0xFF7ED98B),
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // ⭐ what's inside — 2-col icon grid
            _sectionTitle("WHAT'S INSIDE"),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 3.4,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x14F10B1D),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: const Color(0x33F10B1D)),
                      ),
                      child: Row(children: [
                        Text(_itemEmoji(i),
                            style: const TextStyle(fontSize: 17)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(items[i],
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // auto details
            _sectionTitle('YOUR DETAILS (AUTO FROM LOGIN)'),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(children: [
                _kv('Name', '${auto['name'] ?? ''}'),
                _kv('User ID', '${auto['uid'] ?? ''}'),
                _kv('Mobile',
                    (auto['mobile'] ?? '').toString().isEmpty
                        ? '— (add it in your profile)'
                        : '${auto['mobile']}'),
              ]),
            ),
            const SizedBox(height: 14),
            // recipient manual
            _sectionTitle('RECIPIENT DETAILS (MANUAL)'),
            _box(_rName, 'Recipient name'),
            const SizedBox(height: 10),
            _box(_rMobile, 'Recipient mobile number',
                keyboard: TextInputType.phone),
            const SizedBox(height: 10),
            _box(_address, 'Delivery address'),
            const SizedBox(height: 14),
            // payment
            _sectionTitle('PAYMENT — ₹1799 UPI TRANSFER'),
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
                  if (upi.isEmpty)
                    const Text('UPI ID will be added soon — COD until then.',
                        style:
                            TextStyle(color: AppColors.muted, fontSize: 11))
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
                          : _qrB64 != null
                              ? Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  child: _qrUrl != null &&
                                          _qrUrl!.isNotEmpty
                                      ? Image.network(_qrUrl!,
                                          width: 168, height: 168)
                                      : Image.memory(
                                          base64Decode(_qrB64!),
                                          width: 168,
                                          height: 168))
                              : InkWell(
                                  onTap: () {
                                    final vid = info['vendor_id'];
                                    if (vid != null) {
                                      _loadQr(store, vid as int);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                        _qrErr ?? 'QR could not load — tap to retry',
                                        style: const TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 11)),
                                  ),
                                ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          size: 16, color: Color(0xFFFFD34D)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(upi,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .5)),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: upi));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('UPI ID copied')));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0x1AF10B1D),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Text('COPY',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFFFABB2))),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                        '1) Scan the QR and pay ₹1799\n2) Enter your UPI ID and the last 4 digits of the transaction ID below\n3) Tap PLACE ORDER',
                        style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 10.5,
                            height: 1.5)),
                  ],
                  const SizedBox(height: 10),
                  _box(_senderUpi, 'Your UPI ID (sender)'),
                  const SizedBox(height: 10),
                  _box(_txn4, 'Transaction ID — last 4 digits',
                      keyboard: TextInputType.number),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!,
                    style:
                        const TextStyle(color: Color(0xFFF10B1D), fontSize: 11)),
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
                onPressed: _busy ? null : () => _placeOrder(store),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('PLACE ORDER • ₹1799',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _successView() {
    final o = _placed!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0x2416A34A)),
            child:
                const Icon(Icons.check_circle, size: 46, color: Color(0xFF7ED98B)),
          ),
          const SizedBox(height: 16),
          const Text('ORDER ACCEPTED ✓',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Order No: ${o['order_no']}',
              style: const TextStyle(
                  color: Color(0xFFFFD34D),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(children: [
              _kv('Recipient', '${o['recipient_name']}'),
              _kv('Mobile', '${o['recipient_mobile']}'),
              _kv('Address', '${o['address']}'),
              _kv('Paid', '₹${o['total']} (UPI)'),
            ]),
          ),
          const SizedBox(height: 12),
          const Text('🥤 FREE Chilled Diet Coke with your delivery!',
              style: TextStyle(color: Color(0xFF7ED98B), fontSize: 12)),
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
        ]),
      ),
    );
  }

  static const _emojis = ['🛏️', '🛌', '🪣', '🚿', '', '🧷', '👕', '🩴'];
  String _itemEmoji(int i) => i < _emojis.length ? _emojis[i] : '🎁';

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
              width: 82,
              child: Text(k,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 11))),
          Expanded(
              child: Text(v,
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600))),
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
