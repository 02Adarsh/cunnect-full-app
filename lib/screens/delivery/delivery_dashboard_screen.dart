import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../customer/notifications_screen.dart';
import 'delivery_login_screen.dart';

/// Same layout as delivery_dashboard.html.
class DeliveryDashboardScreen extends StatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  State<DeliveryDashboardScreen> createState() => _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState extends State<DeliveryDashboardScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().refreshDeliveryDashboard();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) context.read<AppStore>().refreshDeliveryDashboard();
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
    final ready = store.readyOrders;
    final active = store.outForDeliveryOrders;
    final history = store.deliveredOrders;
    final unread = store.unreadCountFor(AppStore.customerUserId);

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
            InkWell(
              onTap: () => store.enableDeliveryAlerts(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 31,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF373737)),
                ),
                alignment: Alignment.center,
                child: Text(
                  store.deliveryAlertsEnabled ? 'Alerts On' : 'Enable Alerts',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: store.deliveryAlertsEnabled ? const Color(0xFF9BE7B4) : const Color(0xFFEEEEEE),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            InkWell(
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 33,
                height: 31,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF373737)),
                ),
                alignment: Alignment.center,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Text('🔔', style: TextStyle(fontSize: 15)),
                    if (unread > 0)
                      Positioned(
                        top: -7,
                        right: -9,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                              color: AppColors.red, borderRadius: BorderRadius.circular(99)),
                          alignment: Alignment.center,
                          child: Text('${unread > 99 ? '99+' : unread}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 9),
            GestureDetector(
              onTap: () {
                store.deliveryLogout();
                Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const DeliveryLoginScreen()));
              },
              child: const Text('Logout',
                  style: TextStyle(
                      color: Color(0xFFFF9CA5), fontSize: 10.5, fontWeight: FontWeight.w800)),
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
          Container(
            padding: const EdgeInsets.fromLTRB(14, 21, 14, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivery Dashboard',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text("Claim ready orders and verify the customer's delivery OTP.",
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          _section(
            title: 'Ready to Deliver',
            count: '${ready.length} Available',
            children: ready.isEmpty
                ? [const _EmptyBox(text: 'No ready orders available right now.')]
                : [
                    for (final order in ready)
                      _ReadyOrderCard(order: order),
                  ],
          ),
          _section(
            title: 'My Active Deliveries',
            count: '${active.length} Active',
            children: active.isEmpty
                ? [const _EmptyBox(text: 'You have no active deliveries.')]
                : [
                    for (final order in active) _ActiveDeliveryCard(order: order),
                  ],
          ),
          _section(
            title: 'Delivery History',
            count: 'Latest 10',
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: history.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text('Verified deliveries will appear here.',
                              style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < history.length; i++)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                border: i > 0
                                    ? const Border(top: BorderSide(color: AppColors.line))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(history[i].orderNumber,
                                            style: const TextStyle(
                                                fontSize: 11.5, fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 4),
                                        Text(
                                            '${history[i].vendorName} · ${history[i].customerName}\n${_formatDate(history[i].deliveredAt ?? history[i].updatedAt)}',
                                            style: const TextStyle(
                                                color: AppColors.muted, fontSize: 10, height: 1.4)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('₹${history[i].totalAmount.round()}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white)),
                                      const SizedBox(height: 3),
                                      const Text('Delivered ✓',
                                          style: TextStyle(
                                              color: Color(0xFF93E7AE),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ],
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
                      color: Color(0xFFFF8791), fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
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

class _ReadyOrderCard extends StatelessWidget {
  final Order order;

  const _ReadyOrderCard({required this.order});

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
                    Text(order.vendorName,
                        style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  ],
                ),
              ),
              Text('₹${order.totalAmount.round()}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: AppColors.line),
                  bottom: BorderSide(color: AppColors.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < order.items.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == order.items.length - 1 ? 0 : 3),
                    child: Text('${order.items[i].itemName} × ${order.items[i].quantity}',
                        style: const TextStyle(
                            color: Color(0xFFC9C9C9), fontSize: 11, height: 1.5)),
                  ),
              ],
            ),
          ),
          Text.rich(
            TextSpan(children: [
              const TextSpan(
                  text: 'Deliver to:\n',
                  style: TextStyle(color: Color(0xFFFF9DA5), fontWeight: FontWeight.w700)),
              TextSpan(text: '${order.customerName} · ${order.customerPhone}\n'),
              TextSpan(text: order.deliveryAddress),
              if (order.landmark.isNotEmpty) TextSpan(text: '\n${order.landmark}'),
            ]),
            style: const TextStyle(color: Color(0xFFD6D6D6), fontSize: 11, height: 1.45),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 13),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final store = context.read<AppStore>();
                  final error = await store.claimDeliveryOrder(order.id);
                  if (!context.mounted) return;
                  if (error != null) {
                    showCunnectToast(context, error, error: true);
                  } else {
                    showCunnectToast(context, '${order.orderNumber} claimed — deliver it now!');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                child: const Text('Claim This Delivery'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveDeliveryCard extends StatefulWidget {
  final Order order;

  const _ActiveDeliveryCard({required this.order});

  @override
  State<_ActiveDeliveryCard> createState() => _ActiveDeliveryCardState();
}

class _ActiveDeliveryCardState extends State<_ActiveDeliveryCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

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
                    Text(order.vendorName,
                        style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  ],
                ),
              ),
              Text('₹${order.totalAmount.round()}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: AppColors.line),
                  bottom: BorderSide(color: AppColors.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < order.items.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == order.items.length - 1 ? 0 : 3),
                    child: Text('${order.items[i].itemName} × ${order.items[i].quantity}',
                        style: const TextStyle(
                            color: Color(0xFFC9C9C9), fontSize: 11, height: 1.5)),
                  ),
              ],
            ),
          ),
          Text.rich(
            TextSpan(children: [
              const TextSpan(
                  text: 'Deliver to:\n',
                  style: TextStyle(color: Color(0xFFFF9DA5), fontWeight: FontWeight.w700)),
              TextSpan(text: '${order.customerName} · ${order.customerPhone}\n'),
              TextSpan(text: order.deliveryAddress),
              if (order.landmark.isNotEmpty) TextSpan(text: '\n${order.landmark}'),
            ]),
            style: const TextStyle(color: Color(0xFFD6D6D6), fontSize: 11, height: 1.45),
          ),
          Padding(
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
                      final error = await context
                          .read<AppStore>()
                          .verifyDeliveryOtp(order.id, _controller.text);
                      if (!context.mounted) return;
                      if (error != null) {
                        showCunnectToast(context, error, error: true);
                      } else {
                        showCunnectToast(context, 'Delivery completed ✓');
                        _controller.clear();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                    child: const Text('Verify OTP'),
                  ),
                ),
              ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF363636)),
      ),
      alignment: Alignment.center,
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
    );
  }
}
