import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// Like my_print_orders.html — the student's print orders, 5s live poll.
class MyPrintOrdersScreen extends StatefulWidget {
  final bool justPlaced;

  const MyPrintOrdersScreen({super.key, this.justPlaced = false});

  @override
  State<MyPrintOrdersScreen> createState() => _MyPrintOrdersScreenState();
}

class _MyPrintOrdersScreenState extends State<MyPrintOrdersScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadMyPrintOrders();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) context.read<AppStore>().loadMyPrintOrders();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final orders = store.printOrders;

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('My Print Orders',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      ),
      body: orders.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.print_outlined, size: 34, color: Color(0xFF303030)),
                  const SizedBox(height: 10),
                  Text(widget.justPlaced ? 'Order placed ✓' : 'No print orders yet',
                      style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
              itemCount: orders.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OrderCard(order: orders[index]),
              ),
            ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final PrintOrder order;

  const _OrderCard({required this.order});

  Color get _statusColor {
    switch (order.status) {
      case PrintOrderStatus.completed:
        return const Color(0xFFF5F5F5);
      case PrintOrderStatus.rejected:
        return AppColors.red;
      case PrintOrderStatus.pending:
        return const Color(0xFF9E9E9E);
      default:
        return const Color(0xFFF5F5F5);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Expanded(
                child: Text(order.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(.14),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(order.status.label.toUpperCase(),
                    style: TextStyle(
                        color: _statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              _chip('Partner: ${order.vendorName}'),
              _chip('${order.bwPages} B/W pg'),
              if (order.colorPages > 0) _chip('${order.colorPages} color pg'),
              _chip('${order.copies} copies'),
              _chip(order.printSide == 'double' ? 'Double side' : 'Single side'),
            ],
          ),
          // ⭐ v80: the OTP the student shows at the counter — the print
          // partner has to type it in before the job can be completed.
          if (order.deliveryOtp.isNotEmpty && !order.otpVerified) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0x1AF10B1D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x80F10B1D)),
              ),
              child: Column(
                children: [
                  const Text('Show this OTP at the counter to collect',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFFFFB0B7),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(order.deliveryOtp,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 7)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 9),
          Row(
            children: [
              Text('₹${order.totalPrice.round()}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                  '${order.createdAt.day}/${order.createdAt.month} '
                  '${order.createdAt.hour.toString().padLeft(2, '0')}:'
                  '${order.createdAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
            ],
          ),
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
            style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
      );
}
