import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// ⭐ v83: the student's HOSTEL ESSENTIALS orders — the same page the
/// printout section has ("My Orders" at the top right): live status
/// (pending → accepted → delivered / cancelled) and the hand-over OTP
/// the hostel vendor has to type in before he can complete the order.
class MyHostelOrdersScreen extends StatefulWidget {
  const MyHostelOrdersScreen({super.key});

  @override
  State<MyHostelOrdersScreen> createState() => _MyHostelOrdersScreenState();
}

class _MyHostelOrdersScreenState extends State<MyHostelOrdersScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadMyHostelOrders();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) context.read<AppStore>().loadMyHostelOrders();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<AppStore>().myHostelOrders;

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('My Hostel Orders',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      ),
      body: orders.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bed_outlined,
                      size: 34, color: Color(0xFF303030)),
                  const SizedBox(height: 10),
                  Text('No hostel orders yet',
                      style:
                          TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
              itemCount: orders.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OrderCard(
                    order: Map<String, dynamic>.from(orders[index])),
              ),
            ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;

  const _OrderCard({required this.order});

  String get _status => (order['status'] ?? 'pending').toString();

  Color get _statusColor {
    switch (_status) {
      case 'delivered':
        return const Color(0xFF7ED98B);
      case 'cancelled':
        return AppColors.red;
      case 'accepted':
        return const Color(0xFF38BDF8);
      default:
        return const Color(0xFFFFD34D); // pending — gold
    }
  }

  String get _label {
    switch (_status) {
      case 'delivered':
        return 'DELIVERED';
      case 'cancelled':
        return 'CANCELLED / REJECTED';
      case 'accepted':
        return 'ACCEPTED';
      default:
        return 'WAITING FOR THE VENDOR';
    }
  }

  @override
  Widget build(BuildContext context) {
    final no = (order['order_no'] ?? '').toString();
    final items = (order['items'] as List? ?? []);
    final summary = items.isEmpty
        ? 'Hostel Essentials'
        : [
            for (final it in items)
              '${(it as Map)['name']} ×${it['qty']}'
          ].join(', ');
    final otp = (order['delivery_otp'] ?? '').toString();
    final verified = (order['otp_verified'] ?? false) == true;
    final total = (order['total'] as num? ?? 0).round();
    final when = (order['created_at'] ?? '').toString();
    final recipient = (order['recipient_name'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(no.isEmpty ? 'Hostel order' : no,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(.14),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: _statusColor.withOpacity(.5)),
              ),
              child: Text(_label,
                  style: TextStyle(
                      color: _statusColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              _chip(summary),
              if (recipient.isNotEmpty) _chip('For: $recipient'),
            ],
          ),
          // ⭐ v80/v83: the OTP the student reads out at the door — the
          // hostel vendor types it in before the order can be completed.
          if (otp.isNotEmpty && !verified) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0x1AF10B1D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x80F10B1D)),
              ),
              child: Column(children: [
                const Text('Show this OTP to collect your order',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFFFFB0B7),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text(otp,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 7)),
              ]),
            ),
          ] else if (_status == 'accepted') ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0x1438BDF8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x8038BDF8)),
              ),
              child: const Text(
                  'Accepted — the vendor is getting your order ready.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF9ECBFF),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700)),
            ),
          ],
          if (verified && otp.isEmpty && _status == 'delivered') ...[
            const SizedBox(height: 10),
            const Text('OTP verified — order handed over.',
                style: TextStyle(
                    color: Color(0xFF7ED98B),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 9),
          Row(children: [
            Text('₹$total',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800)),
            const Spacer(),
            if (when.isNotEmpty)
              Text(when,
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 10.5)),
          ]),
          if (otp.isNotEmpty && !verified) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: otp));
                  if (context.mounted) {
                    showCunnectToast(context, 'OTP copied');
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('COPY OTP',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFB0B7),
                  side: const BorderSide(color: Color(0x80F10B1D)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1D1D),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFF2C2C2C)),
        ),
        child: Text(label,
            style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
      );
}
