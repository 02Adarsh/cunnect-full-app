import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'vendor_dashboard_screen.dart';
import 'vendor_menu_screen.dart';

/// Vendor Delivery Panel — same layout as vendor_delivery_panel.html.
class VendorDeliveryScreen extends StatelessWidget {
  const VendorDeliveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        toolbarHeight: 62,
        automaticallyImplyLeading: false,
        titleSpacing: 14,
        title: Row(
          children: [
            const CunnectBrand(),
            const Spacer(),
            Text(store.vendor.businessName,
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(width: 8),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF202020)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                _tab(context, 'Overview', false,
                    () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const VendorDashboardScreen()))),
                const SizedBox(width: 9),
                _tab(context, 'Delivery', true, null),
                const SizedBox(width: 9),
                _tab(context, 'Menu', false,
                    () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const VendorMenuScreen()))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 19, 14, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivery Panel',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('Start delivery and verify customer OTP from your Partner Portal.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          _section(
            title: 'Ready to Deliver',
            count: '${store.readyOrders.length} Ready',
            children: store.readyOrders.isEmpty
                ? [const _EmptyBox(text: 'No orders are ready for delivery.')]
                : [
                    for (final order in store.readyOrders)
                      _DeliveryOrderCard(
                        order: order,
                        statusLabel: 'Ready for Delivery',
                        statusColor: const Color(0xFFFFD394),
                        statusBorder: const Color(0x80FFAA37),
                        address: true,
                        action: _StartDeliveryButton(orderId: order.id),
                      ),
                  ],
          ),
          _section(
            title: 'Out for Delivery',
            count: '${store.outForDeliveryOrders.length} Active',
            children: store.outForDeliveryOrders.isEmpty
                ? [const _EmptyBox(text: 'No active deliveries right now.')]
                : [
                    for (final order in store.outForDeliveryOrders)
                      _DeliveryOrderCard(
                        order: order,
                        statusLabel: 'Out for Delivery',
                        statusColor: const Color(0xFF9ECBFF),
                        statusBorder: const Color(0x804BA3FF),
                        address: true,
                        note:
                            'The 4-digit OTP is shown on the customer Food Dashboard. Enter it to complete the delivery.',
                        action: _OtpVerifyForm(orderId: order.id),
                      ),
                  ],
          ),
          _section(
            title: 'Delivery History',
            count: 'Latest 10',
            children: store.deliveredOrders.isEmpty
                ? [const _EmptyBox(text: 'Verified completed deliveries will appear here.')]
                : [
                    for (final order in store.deliveredOrders)
                      _DeliveryOrderCard(
                        order: order,
                        statusLabel: 'Delivered ✓',
                        statusColor: const Color(0xFF9BE7B4),
                        statusBorder: const Color(0x8038B765),
                        showDeliveredAt: true,
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, bool active, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: active ? const Color(0x1FF10B1D) : Colors.transparent,
          border: Border.all(color: active ? AppColors.red : const Color(0xFF363636)),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active ? const Color(0xFFFFABB2) : const Color(0xFFAAAAAA),
            )),
      ),
    );
  }

  Widget _section({required String title, required String count, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 17, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(count,
                  style: const TextStyle(
                      color: Color(0xFFFF8B95), fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _DeliveryOrderCard extends StatelessWidget {
  final Order order;
  final String statusLabel;
  final Color statusColor;
  final Color statusBorder;
  final bool address;
  final String? note;
  final Widget? action;
  final bool showDeliveredAt;

  const _DeliveryOrderCard({
    required this.order,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBorder,
    this.address = false,
    this.note,
    this.action,
    this.showDeliveredAt = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.orderNumber,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      showDeliveredAt
                          ? '${order.customerName} · ${_formatDate(order.deliveredAt ?? order.updatedAt)}'
                          : '${order.customerName} · ${order.customerPhone}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              Text('₹${order.totalAmount.round()}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: statusBorder),
            ),
            child: Text(statusLabel,
                style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w800)),
          ),
          if (address)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(
                      text: 'Address:\n',
                      style: TextStyle(color: Color(0xFFFFABB2), fontWeight: FontWeight.w700)),
                  TextSpan(text: order.deliveryAddress),
                  if (order.landmark.isNotEmpty) TextSpan(text: '\n${order.landmark}'),
                ]),
                style: const TextStyle(color: Color(0xFFD2D2D2), fontSize: 11, height: 1.55),
              ),
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(note!,
                  style: const TextStyle(color: Color(0xFFA7D8FF), fontSize: 10.5, height: 1.4)),
            ),
          if (action != null) action!,
        ],
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    var hour = dateTime.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dateTime.hour < 12 ? 'AM' : 'PM';
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day} ${months[dateTime.month - 1]}, $hour:$minute $ampm';
  }
}

class _StartDeliveryButton extends StatelessWidget {
  final int orderId;

  const _StartDeliveryButton({required this.orderId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () async {
            showCunnectToast(context, 'Starting delivery…');
            final error = await context.read<AppStore>().startDelivery(orderId);
            if (context.mounted && error != null) {
              showCunnectToast(context, error, error: true);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          child: const Text('Start Delivery'),
        ),
      ),
    );
  }
}

class _OtpVerifyForm extends StatefulWidget {
  final int orderId;

  const _OtpVerifyForm({required this.orderId});

  @override
  State<_OtpVerifyForm> createState() => _OtpVerifyFormState();
}

class _OtpVerifyFormState extends State<_OtpVerifyForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, letterSpacing: 4),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'OTP',
                  hintStyle: const TextStyle(color: AppColors.placeholder, letterSpacing: 1),
                  filled: true,
                  fillColor: const Color(0xFF0C0C0C),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 11),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: Color(0xFF3B3B3B)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: AppColors.red),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            width: 88,
            child: ElevatedButton(
              onPressed: () async {
                showCunnectToast(context, 'Verifying OTP…');
                final error = await context
                    .read<AppStore>()
                    .verifyVendorDeliveryOtp(widget.orderId, _controller.text);
                if (!context.mounted) return;
                if (error != null) {
                  showCunnectToast(context, error, error: true);
                } else {
                  showCunnectToast(context, 'OTP verified — delivery completed ✓');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              child: const Text('Verify OTP'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final String text;

  const _EmptyBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF363636), style: BorderStyle.solid),
      ),
      alignment: Alignment.center,
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
    );
  }
}
