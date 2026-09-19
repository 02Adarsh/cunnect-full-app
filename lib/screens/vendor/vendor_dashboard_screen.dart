import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../customer/notifications_screen.dart';
import 'vendor_delivery_screen.dart';
import 'vendor_earnings_screen.dart';
import 'vendor_menu_screen.dart';
import 'vendor_profile_screen.dart';

class VendorDashboardScreen extends StatefulWidget {
  final bool focusOrders;

  const VendorDashboardScreen({super.key, this.focusOrders = false});

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  final _ordersKey = GlobalKey();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = context.read<AppStore>();
      store.refreshVendorDashboard();
      store.loadVendorNotifications();
    });
    // ⭐ orders poll every 15 sec — near-realtime even if FCM is blocked
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final store = context.read<AppStore>();
      store.refreshVendorDashboard();
      store.loadVendorNotifications();
    });
    if (widget.focusOrders) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ordersContext = _ordersKey.currentContext;
        if (ordersContext != null) {
          Scrollable.ensureVisible(ordersContext,
              duration: const Duration(milliseconds: 350), alignment: 0.05);
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final incoming = store.vendorIncomingOrders;
    final active = store.vendorActiveOrders;
    final unread = store.unreadCountFor(AppStore.vendorUserId);

    final body = ListView(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + MediaQuery.of(context).padding.bottom + 72),
      children: [
        _buildHeader(context, store, unread),
        _buildOverview(store),
        if (!store.kitchenOpen)
          Container(
            margin: const EdgeInsets.only(bottom: 13),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x1AF10B1D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x8CF10B1D)),
            ),
            child: const Text(
              'Kitchen is closed. Students currently cannot order your items.',
              style: TextStyle(color: Color(0xFFFFABB2), fontSize: 11),
            ),
          ),
        _buildMetrics(store, incoming.length),
        const SizedBox(height: 18),
        _incomingPanel(store, incoming),
        const SizedBox(height: 15),
        _activePanel(store, active),
        const SizedBox(height: 15),
        _historyPanel(store),
      ],
    );
    // Inside the shell a Scaffold already exists; when pushed standalone
    // (e.g. from the Delivery panel tabs) add one so text renders
    // correctly (yellow-underline fix).
    if (Scaffold.maybeOf(context) != null) return body;
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(bottom: false, child: body),
    );
  }

  Widget _buildHeader(BuildContext context, AppStore store, int unread) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const CunnectBrand(fontSize: 24),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
          _actionChip('Delivery',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const VendorDeliveryScreen()))),
          const SizedBox(width: 7),
          _actionChip(
            store.vendorAlertsEnabled ? 'Alerts On' : 'Enable Alerts',
            activeColor: store.vendorAlertsEnabled ? const Color(0xFF9BE7B4) : null,
            onTap: () => setState(() => store.vendorAlertsEnabled = true),
          ),
          const SizedBox(width: 7),
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NotificationsScreen(forVendor: true))),
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
          const SizedBox(width: 7),
          InkWell(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const VendorProfileScreen())),
            child: Row(
              children: [
                Container(
                  width: 35,
                  height: 35,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF261014),
                    border: Border.all(color: const Color(0xB3F10B1D)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    store.vendor.businessName.substring(0, 2).toUpperCase(),
                    style: const TextStyle(
                        color: Color(0xFFFF9AA3), fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(String label, {VoidCallback? onTap, Color? activeColor}) {
    return InkWell(
      onTap: onTap,
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
        child: Text(label,
            style: TextStyle(
                color: activeColor ?? const Color(0xFFEEEEEE),
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildOverview(AppStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 19, 0, 19),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store.vendor.businessName,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.7)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: InkWell(
            onTap: () {
              final opening = !store.kitchenOpen;
              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: const Color(0xFF1C1C1C),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: AppColors.line)),
                  title: Text(opening ? 'Open the kitchen?' : 'Close the kitchen?',
                      style: const TextStyle(fontSize: 15)),
                  content: Text(
                    opening
                        ? 'Turning the kitchen on makes all menu items available to students. Continue?'
                        : 'Turning Kitchen Off will make all your menu items unavailable to students. Continue?',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel', style: TextStyle(color: AppColors.muted))),
                    TextButton(
                        onPressed: () {
                          store.setKitchenOpen(opening);
                          Navigator.pop(dialogContext);
                        },
                        child: Text(opening ? 'Open' : 'Close',
                            style: const TextStyle(color: AppColors.red))),
                  ],
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                    color: store.kitchenOpen
                        ? const Color(0x7338B765)
                        : const Color(0xA6F10B1D)),
                color: store.kitchenOpen ? const Color(0x1738B765) : const Color(0x1FF10B1D),
              ),
              child: Text(
                store.kitchenOpen
                    ? '● Kitchen Open — Click to Close'
                    : '● Kitchen Closed — Click to Open',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: store.kitchenOpen ? const Color(0xFF9BE7B4) : const Color(0xFFFFABB2),
                ),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(AppStore store, int incomingCount) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Metric(
            label: 'NEW ORDERS',
            value: '$incomingCount',
            note: 'Waiting for your response'),
      ],
    );
  }

  void _dial(BuildContext context, String phone) {
    if (phone.isEmpty) return;
    Clipboard.setData(ClipboardData(text: phone));
    showCunnectToast(context, 'Copied $phone — dialing');
    launchUrl(Uri.parse('tel:$phone'));
  }

  String _customerMeta(Order o) => [
        if (o.customerUid.isNotEmpty) o.customerUid,
        if (o.customerPhone.isNotEmpty)
          '📞 ${o.customerPhone}'
        else if (o.status == 'pending')
          '📞 visible after accept',
        if (o.customerHostel.isNotEmpty)
          '${o.customerHostel}${o.customerRoom.isNotEmpty ? ' · Rm ${o.customerRoom}' : ''}',
        if (o.customerBranch.isNotEmpty) o.customerBranch,
        if (o.customerUpi.isNotEmpty) 'UPI: ${o.customerUpi}',
        if (o.txnId.isNotEmpty)
          'Txn ID: ${o.txnId}'
        else if (o.txnLast4.isNotEmpty) 'Txn: ****${o.txnLast4}',
      ].join(' · ');

  Widget _incomingPanel(AppStore store, List<Order> incoming) {
    return Panel(
      child: Column(
        key: _ordersKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 16, 15, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Incoming Orders',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('${incoming.length} Pending',
                    style: const TextStyle(
                        color: Color(0xFFFF7782), fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: incoming.isEmpty
                ? const _EmptyState(text: 'No new orders right now.')
                : Column(
                    children: [
                      for (final order in incoming)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
                          decoration: BoxDecoration(
                            border: order != incoming.first
                                ? const Border(top: BorderSide(color: AppColors.line))
                                : null,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(order.orderNumber,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0x21F10B1D),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: const Text('NEW',
                                              style: TextStyle(
                                                  color: Color(0xFFFF8C96),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      order.items
                                          .map((i) => '${i.itemName} × ${i.quantity}')
                                          .join(' · '),
                                      style: const TextStyle(
                                          color: AppColors.muted, fontSize: 10.5, height: 1.35),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '₹${order.totalAmount.round()} · ${order.customerName}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700),
                                    ),
                                    if (_customerMeta(order).isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      GestureDetector(onTap: () => _dial(context, order.customerPhone), child: Text(_customerMeta(order),
                                          style: const TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 10, height: 1.3))), 
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                children: [
                                  _orderButton('Accept', AppColors.red, Colors.white,
                                      () => store.vendorUpdateOrderStatus(order.id, 'accept')),
                                  const SizedBox(height: 6),
                                  _orderButton('Reject', Colors.transparent,
                                      const Color(0xFFBBBBBB),
                                      () => store.vendorUpdateOrderStatus(order.id, 'reject'),
                                      borderColor: const Color(0xFF444444)),

                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 11),
        ],
      ),
    );
  }

  Widget _activePanel(AppStore store, List<Order> active) {
    return Panel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 16, 15, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Active Orders',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('${active.length} In Progress',
                    style: const TextStyle(
                        color: Color(0xFFAAAAAA), fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: active.isEmpty
                ? const _EmptyState(text: 'No active orders right now.')
                : Column(
                    children: [
                      for (var i = 0; i < active.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
                          decoration: BoxDecoration(
                            border: i > 0
                                ? const Border(top: BorderSide(color: AppColors.line))
                                : null,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(active[i].orderNumber,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 4),
                                    StatusChip(status: active[i].status, pill: true),
                                    const SizedBox(height: 4),
                                    Text(
                                      active[i].items
                                          .map((it) => '${it.itemName} × ${it.quantity}')
                                          .join(' · '),
                                      style: const TextStyle(
                                          color: AppColors.muted, fontSize: 10.5, height: 1.35),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '₹${active[i].totalAmount.round()} · ${active[i].customerName}${active[i].customerUid.isNotEmpty ? ' (${active[i].customerUid})' : ''}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700),
                                    ),
                                    if (active[i].customerPhone.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      GestureDetector(onTap: () => _dial(context, active[i].customerPhone), child: Text('📞 ${active[i].customerPhone}',
                                          style: const TextStyle(
                                              color: Color(0xFF7ED98B),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800)))
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (active[i].status == OrderStatus.accepted)
                                _orderButton('Start Preparing', const Color(0xFF2E9D55),
                                    Colors.white,
                                    () => store.vendorUpdateOrderStatus(active[i].id, 'prepare'))
                              else if (active[i].status == OrderStatus.preparing)
                                _orderButton('Mark Ready', const Color(0xFF2E9D55), Colors.white,
                                    () => store.vendorUpdateOrderStatus(active[i].id, 'ready'))
                              else if (active[i].status == OrderStatus.ready)
                                GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const VendorDeliveryScreen())),
                                  child: const Text('Open Delivery\nPanel',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          color: Color(0xFFFF9DA5),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          height: 1.4)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 11),
        ],
      ),
    );
  }

  Widget _earningsPanel(AppStore store) {
    final weekly = store.weeklyEarnings;
    final maxValue = weekly.fold<double>(0, (m, e) => e.value > m ? e.value : m);

    return Panel(
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Daily Earnings',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    SizedBox(height: 5),
                    Text('Completed orders only · Last 7 days',
                        style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${store.todayEarnings.round()}',
                      style: const TextStyle(
                          fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.7)),
                  const SizedBox(height: 2),
                  const Text('TODAY',
                      style: TextStyle(
                          color: Color(0xFF8BDDAA), fontSize: 9, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 17),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final entry in weekly)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: maxValue > 0
                                ? (entry.value / maxValue) * 105 + (entry.value > 0 ? 0 : 4)
                                : 4,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFF33746), Color(0xFF9D0D17)],
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(entry.key,
                              style: const TextStyle(color: Color(0xFF777777), fontSize: 9)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Last 7 days total',
                    style: TextStyle(color: AppColors.muted, fontSize: 10)),
                Text('₹${store.weekTotal.round()}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyPanel(AppStore store) {
    final history = store.vendorOrderHistory;

    return Panel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 16, 15, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('Order History',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('Latest 10',
                    style: TextStyle(
                        color: Color(0xFFAAAAAA), fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: history.isEmpty
                ? const _EmptyState(
                    text: 'Completed and cancelled orders will appear here.')
                : Column(
                    children: [
                      for (var i = 0; i < history.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
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
                                            fontSize: 11, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 3),
                                    Text(
                                        '${history[i].customerName} · ${_formatDate(history[i].updatedAt)}',
                                        style: const TextStyle(
                                            color: AppColors.muted, fontSize: 10)),
                                    if (history[i].customerPhone.isNotEmpty)
                                      Text('📞 ${history[i].customerPhone}',
                                          style: const TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 10)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('₹${history[i].totalAmount.round()}',
                                      style: const TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 5),
                                  StatusChip(status: history[i].status, pill: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 13),
        ],
      ),
    );
  }

  Widget _menuPanel(AppStore store) {
    final items = store.menuItems;

    return Panel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 16, 15, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Menu availability',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                GestureDetector(
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const VendorMenuScreen())),
                  child: const Text('Manage menu',
                      style: TextStyle(
                          color: Color(0xFFFF7782), fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: items.isEmpty
                ? const _EmptyState(text: 'No food items added yet.')
                : Column(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
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
                                    DishNameWithMark(
                                        name: items[i].name,
                                        isVeg: items[i].isVeg,
                                        style: const TextStyle(
                                            fontSize: 11.5, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 3),
                                    Text(
                                        '₹${items[i].price.round()} · ${items[i].category}',
                                        style: const TextStyle(
                                            color: AppColors.muted, fontSize: 10)),
                                  ],
                                ),
                              ),
                              _Toggle(
                                value: items[i].isAvailable,
                                onChanged: (_) => store.toggleItemAvailability(items[i].id),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 13),
        ],
      ),
    );
  }

  Widget _orderButton(String label, Color background, Color foreground, VoidCallback onTap,
      {Color? borderColor}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        constraints: const BoxConstraints(minWidth: 65),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(7),
          border: borderColor != null ? Border.all(color: borderColor) : null,
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(color: foreground, fontSize: 10, fontWeight: FontWeight.w800)),
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

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String note;

  const _Metric({required this.label, required this.value, required this.note});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 87),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.muted, fontSize: 9.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            Text(value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.7)),
            const SizedBox(height: 5),
            Text(note, style: const TextStyle(color: Color(0xFF8BDDAA), fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 33,
        height: 19,
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: value ? AppColors.red : const Color(0xFF444444),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 13,
            height: 13,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.white : const Color(0xFFDDDDDD),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;

  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 13),
      child: Center(
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      ),
    );
  }
}
