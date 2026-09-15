import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// Print vendor ka dashboard — incoming orders + status actions (5s poll).
class PrintVendorDashboardScreen extends StatefulWidget {
  const PrintVendorDashboardScreen({super.key});

  @override
  State<PrintVendorDashboardScreen> createState() =>
      _PrintVendorDashboardScreenState();
}

class _PrintVendorDashboardScreenState extends State<PrintVendorDashboardScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadPrintVendorDashboard();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) context.read<AppStore>().loadPrintVendorDashboard();
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
    final orders = store.printVendorOrders;
    final pending = orders.where((o) => o.status == PrintOrderStatus.pending).length;
    final active = orders
        .where((o) =>
            o.status == PrintOrderStatus.accepted ||
            o.status == PrintOrderStatus.printing)
        .length;
    final done =
        orders.where((o) => o.status == PrintOrderStatus.completed).length;

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Print Orders',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          Row(
            children: [
              Expanded(child: _metric('Pending', '$pending', const Color(0xFFD9A94E))),
              const SizedBox(width: 10),
              Expanded(child: _metric('In Progress', '$active', const Color(0xFF6EA8FE))),
              const SizedBox(width: 10),
              Expanded(child: _metric('Completed', '$done', AppColors.green)),
            ],
          ),
          const SizedBox(height: 16),
          if (orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text('No print orders received yet.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
            ),
          for (final order in orders)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OrderCard(order: order),
            ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.lineSoft),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
          ],
        ),
      );
}

class _OrderCard extends StatelessWidget {
  final PrintOrder order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final actions = store.printNextActions(order);

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
                  color: const Color(0x26F10B1D),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(order.status.label.toUpperCase(),
                    style: const TextStyle(
                        color: Color(0xFFFF9CA5),
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
              _chip('${order.bwPages} B/W pg'),
              if (order.colorPages > 0) _chip('${order.colorPages} color pg'),
              _chip('${order.copies} copies'),
              _chip(order.printSide == 'double' ? 'Double side' : 'Single side'),
              _chip('₹${order.totalPrice.round()}'),
            ],
          ),
          if (order.bwPageRanges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('B/W: ${order.bwPageRanges}',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
            ),
          if (order.colorPageRanges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Color: ${order.colorPageRanges}',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
            ),
          if (order.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('“${order.note}”',
                  style: const TextStyle(
                      color: Color(0xFFCFCFCF), fontSize: 11.5, fontStyle: FontStyle.italic)),
            ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (label, action) in actions) ...[
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ElevatedButton(
                        onPressed: () => store.updatePrintOrderStatus(order.id, action),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: action == 'reject'
                              ? const Color(0xFF2A1214)
                              : AppColors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9)),
                          textStyle: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                        child: Text(label),
                      ),
                    ),
                  ),
                  if (action != actions.last.$2) const SizedBox(width: 8),
                ],
              ],
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
            style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
      );
}
