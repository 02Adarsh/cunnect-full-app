import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../services/ring_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// ⭐ Hostel vendor portal: pack orders list — order no, orderer (auto
/// login) name+mobile, recipient name+mobile, address, UTR, status.
class HostelVendorScreen extends StatefulWidget {
  const HostelVendorScreen({super.key});

  @override
  State<HostelVendorScreen> createState() => _HostelVendorScreenState();
}

class _HostelVendorScreenState extends State<HostelVendorScreen> {
  /// ⭐ v84: the hostel portal rings for 20 seconds on a brand-new order
  /// — the same ring every other partner portal uses.
  final Set<String> _seenOrders = <String>{};
  bool _ordersLoadedOnce = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<AppStore>().loadVendorHostelOrders());
    _pollTimer = Timer.periodic(
        const Duration(seconds: 5), (_) {
      if (mounted) context.read<AppStore>().loadVendorHostelOrders();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _ringOnNewOrders(AppStore store) {
    final ids =
        store.vendorHostelOrders.map((o) => '${o['id']}').toSet();
    if (!_ordersLoadedOnce) {
      _seenOrders.addAll(ids);
      _ordersLoadedOnce = true;
      return;
    }
    final fresh = ids.difference(_seenOrders);
    if (fresh.isEmpty) return;
    _seenOrders.addAll(fresh);
    RingService.ring(key: fresh.first);
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted':
        return const Color(0xFF38BDF8);
      case 'delivered':
        return const Color(0xFF7ED98B);
      case 'cancelled':
        return const Color(0xFFF10B1D);
      default:
        return const Color(0xFFFFD34D);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final orders = store.vendorHostelOrders;
    _ringOnNewOrders(store);
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => store.loadVendorHostelOrders(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
            children: [
              const SizedBox(height: 10),
              const Text('🛏 HOSTEL ESSENTIALS ORDERS',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              Text('${orders.length} order${orders.length == 1 ? '' : 's'}',
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 10)),
              const SizedBox(height: 12),
              if (orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: Text('No orders received yet.',
                        style:
                            TextStyle(color: AppColors.muted, fontSize: 12)),
                  ),
                ),
              for (final o in orders) _orderCard(store, o),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orderCard(AppStore store, Map<String, dynamic> o) {
    final status = '${o['status']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('${o['order_no']}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFFD34D))),
            const Spacer(),
            Text('${o['created_at']}',
                style:
                    const TextStyle(color: AppColors.muted, fontSize: 9.5)),
          ]),
          const SizedBox(height: 8),
          _row('ORDERED BY (LOGIN ID)', ''),
          _row('  Name', '${o['orderer_name']}'),
          _row('  UID', '${o['orderer_uid']}'),
          _row('  UPI', '${o['customer_upi']}'.isEmpty ? '—' : '${o['customer_upi']}'),
          _row('  Txn ID',
              '${o['txn_id'] ?? ''}'.isNotEmpty
                  ? '${o['txn_id']}'
                  : ('${o['txn_last4']}'.isEmpty
                      ? '—'
                      : '****${o['txn_last4']}')),
          _row('  Mobile',
              '${o['orderer_mobile']}'.isEmpty
                  ? 'Visible after you accept the order'
                  : '${o['orderer_mobile']}'),
          const SizedBox(height: 8),
          _row('RECIPIENT', ''),
          _row('  Name', '${o['recipient_name']}'),
          _row('  Mobile',
              '${o['recipient_mobile']}'.isEmpty
                  ? 'Visible after you accept the order'
                  : '${o['recipient_mobile']}'),
          const SizedBox(height: 8),
          // ⭐ v60: ordered products (name × qty = amount)
          if ((o['items'] as List? ?? []).isNotEmpty) ...[
            _row('ITEMS', ''),
            for (final it in (o['items'] as List))
              _row('  ${(it as Map)['name']}',
                  '×${it['qty']}  ·  ₹${((it['mrp'] ?? 0) as num) * ((it['qty'] ?? 1) as num)}'),
            const SizedBox(height: 8),
          ],
          _row('Address', '${o['address']}'),
          _row('Payment ref',
              '${o['payment_ref']}'.isEmpty ? '—' : '${o['payment_ref']}'),
          _row('Total', '₹${o['total']}'),
          const SizedBox(height: 10),
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(status).withOpacity(.15),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: _statusColor(status).withOpacity(.5)),
              ),
              child: Text(status.toUpperCase(),
                  style: TextStyle(
                      color: _statusColor(status),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800)),
            ),
            const Spacer(),
            if (status == 'pending')
              _btn('ACCEPT', const Color(0xFF16A34A), () async {
                await store.vendorHostelStatus(o['id'] as int, 'accepted');
                await store.loadVendorHostelOrders();
              }),
            if (status == 'accepted')
              _btn('DELIVERED', const Color(0xFFC9C9C9),
                  () => _deliverWithOtp(context, o)),
            if (status == 'pending' || status == 'accepted')
              _btn('CANCEL', const Color(0xFFF10B1D), () async {
                await store.vendorHostelStatus(o['id'] as int, 'cancelled');
                await store.loadVendorHostelOrders();
              }),
          ]),
        ],
      ),
    );
  }

  /// ⭐ v80: an order is only delivered once the OTP the student reads
  /// out at the door has been typed in and verified.
  Future<void> _deliverWithOtp(
      BuildContext context, Map<String, dynamic> o) async {
    final ctl = TextEditingController();
    var busy = false;
    final ok = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                decoration: const BoxDecoration(
                  color: Color(0xFF0E0E0E),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(22)),
                  border: Border(top: BorderSide(color: Color(0x33FFFFFF))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                              color: const Color(0xFF3A3A3A),
                              borderRadius: BorderRadius.circular(2))),
                    ),
                    const SizedBox(height: 16),
                    const Text('Enter the delivery OTP',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 7),
                    Text(
                        'Ask ${o['recipient_name'] ?? 'the student'} for the '
                        '4-digit OTP on their screen and type it here. The '
                        'order is marked delivered as soon as it matches.',
                        style: const TextStyle(
                            color: Color(0xFF9E9E9E),
                            fontSize: 12.5,
                            height: 1.45)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ctl,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      autofocus: true,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          letterSpacing: 10,
                          fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '----',
                        hintStyle:
                            const TextStyle(color: Color(0xFF4A4A4A)),
                        filled: true,
                        fillColor: const Color(0xFF151515),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide:
                              const BorderSide(color: Color(0xFF303030)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide:
                              const BorderSide(color: AppColors.red),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: busy
                            ? null
                            : () async {
                                setLocal(() => busy = true);
                                final err = await context
                                    .read<AppStore>()
                                    .hostelVerifyOtp(
                                        o['id'] as int, ctl.text);
                                if (!ctx.mounted) return;
                                setLocal(() => busy = false);
                                if (err != null) {
                                  showCunnectToast(ctx, err, error: true);
                                  return;
                                }
                                Navigator.of(ctx).pop(true);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.red,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('VERIFY AND DELIVER',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ) ??
        false;
    ctl.dispose();
    if (ok && context.mounted) {
      showCunnectToast(context, 'Order marked delivered');
    }
  }

  Widget _btn(String label, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(.6)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _row(String k, String v) => v.isEmpty
      ? Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(k,
              style: const TextStyle(
                  color: Color(0xFFFFABB2),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8)),
        )
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            SizedBox(
                width: 92,
                child: Text(k,
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 10.5))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600))),
          ]),
        );
}
