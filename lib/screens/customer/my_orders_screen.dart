import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'food_home_screen.dart';

/// ⭐ My Orders — FOOD + PRINTOUT + HOSTEL + RIDE (+ AUTO calls),
/// all orders in one place.
/// `mode: 'food'` → food orders only (for the food app's Orders button).
class MyOrdersScreen extends StatefulWidget {
  final String mode; // 'all' | 'food'

  const MyOrdersScreen({super.key, this.mode = 'all'});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  Timer? _timer;
  int _ticks = 0;
  String _filter = 'all'; // all | food | print | hostel | ride
  bool _booting = true; // ⭐ v87: first full pull in flight

  @override
  void initState() {
    super.initState();
    // Same 3-second live status refresh as my_orders.html.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _reloadAll(force: true);
      if (mounted) setState(() => _booting = false);
    });
    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      final store = context.read<AppStore>();
      store.refreshOrderStatuses();
      if (widget.mode == 'food') return;
      // ⭐ v87: every 3s the other tabs re-fetch too — ALL stays live.
      _ticks++;
      await _reloadAll();
    });
  }

  Future<void> _reloadAll({bool force = false}) async {
    final store = context.read<AppStore>();
    // ⭐ v87: ALWAYS pull print/hostel/ride/auto in dashboard mode.
    // Each loader is isolated — one failure cannot wipe the others.
    // food-only mode still skips the non-food endpoints.
    Future safe(Future Function() job, String tag) async {
      try {
        await job();
      } catch (e) {
        debugPrint('[MyOrders] $tag failed: $e');
      }
    }

    final jobs = <Future>[safe(store.refreshCustomerOrders, 'food')];
    if (widget.mode != 'food') {
      jobs.addAll([
        safe(store.loadMyPrintOrders, 'print'),
        safe(store.loadMyHostelOrders, 'hostel'),
        safe(store.loadRides, 'ride'),
        safe(store.loadMyAutoCalls, 'auto'),
      ]);
    } else if (force) {
      // food tab of food-home: only food
    }
    await Future.wait(jobs);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final orders = store.customerOrders;
    final prints = store.printOrders;
    final hostels = store.myHostelOrders;
    // ⭐ v85: active ride sits on top of the past list so ALL / RIDE
    // never hide an in-progress booking.
    final rides = <dynamic>[
      if (store.activeRide != null) store.activeRide!,
      ...store.pastRides,
    ];
    final autos = store.myAutoCalls;
    final foodOnly = widget.mode == 'food';
    final showFood = foodOnly || _filter == 'all' || _filter == 'food';
    final showPrint = !foodOnly && (_filter == 'all' || _filter == 'print');
    final showHostel = !foodOnly && (_filter == 'all' || _filter == 'hostel');
    final showRide = !foodOnly && (_filter == 'all' || _filter == 'ride');
    final allEmpty = (!showFood || orders.isEmpty) &&
        (!showPrint || prints.isEmpty) &&
        (!showHostel || hostels.isEmpty) &&
        (!showRide || (rides.isEmpty && autos.isEmpty));

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const CunnectHeader(),
          Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 21, 14, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My Orders',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    foodOnly
                        ? 'Your food orders — with live status.'
                        : 'Food, printout, hostel & rides — all in one place.',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.red,
                    boxShadow: [BoxShadow(color: AppColors.red, blurRadius: 8)],
                  ),
                ),
                const SizedBox(width: 6),
                const Text('Live status updates enabled',
                    style: TextStyle(color: Color(0xFF91E8AD), fontSize: 10.5)),
              ],
            ),
          ),
          // ⭐ filter tabs — All / Food / Printout / Hostel (dashboard mode me)
          if (!foodOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _tab('ALL', 'all'),
                  _tab('FOOD', 'food'),
                  _tab('PRINT', 'print'),
                  _tab('HOSTEL', 'hostel'),
                  _tab('RIDE', 'ride'),
                ],
              ),
            ),
          ),
          if (!foodOnly && _booting)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: Color(0xFFF10B1D),
                backgroundColor: Color(0x22F10B1D),
              ),
            ),
          Expanded(
            child: (allEmpty && !_booting)
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No orders yet',
                            style: TextStyle(
                                color: Color(0xFFEEEEEE),
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                            foodOnly
                                ? 'Your placed food orders will appear here.'
                                : 'Your food, printout, hostel & ride orders '
                                    'will appear here.',
                            style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (_) => const FoodHomeScreen()),
                              (route) => route.isFirst),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22)),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          child: const Text('Browse Store'),
                        ),
                      ],
                    ),
                  )
                : allEmpty && _booting
                    ? const Center(
                        child: Text('Loading food, print, hostel & rides…',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 13)))
                    : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 9, 14, 20),
                    children: [
                      // ---------------- FOOD ----------------
                      if (showFood) ...[
                        _sectionHead('🍔', 'FOOD ORDERS', orders.length),
                        if (orders.isEmpty)
                          _none('No food orders yet.')
                        else
                          for (final order in orders)
                            _OrderCard(order: order),
                        const SizedBox(height: 18),
                      ],
                      // ---------------- PRINTOUT ----------------
                      if (showPrint) ...[
                        _sectionHead('🖨', 'PRINTOUT ORDERS', prints.length),
                        if (prints.isEmpty)
                          _none('No printout orders yet.')
                        else
                          for (final p in prints) _PrintCard(order: p),
                        const SizedBox(height: 18),
                      ],
                      // ---------------- HOSTEL ----------------
                      if (showHostel) ...[
                        _sectionHead('🛏', 'HOSTEL ESSENTIALS', hostels.length),
                        if (hostels.isEmpty)
                          _none('No hostel pack orders yet.')
                        else
                          for (final h in hostels) _HostelCard(order: h),
                        const SizedBox(height: 18),
                      ],
                      // ---------------- RIDE + AUTO (v83) ----------------
                      if (showRide) ...[
                        _sectionHead('🚗', 'RIDES', rides.length),
                        if (rides.isEmpty)
                          _none('No rides yet.')
                        else
                          for (final r in rides)
                            _RideRow(ride: Map<String, dynamic>.from(r as Map)),
                        const SizedBox(height: 16),
                        _sectionHead('🛺', 'AUTO CALLS', autos.length),
                        if (autos.isEmpty)
                          _none('No auto calls yet.')
                        else
                          for (final a in autos)
                            _AutoRow(call: Map<String, dynamic>.from(a)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    ),
        ]),
      ),);
  }

  Widget _sectionHead(String icon, String title, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 4),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 7),
            Text(title,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
            const Spacer(),
            Text('$count',
                style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _none(String msg) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        child: Text(msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      );

  Widget _tab(String label, String key) {
    final active = _filter == key;
    return InkWell(
      onTap: () {
        setState(() => _filter = key);
        // ⭐ v85: switching tabs re-pulls so the list is never stale.
        _reloadAll(force: true);
      },
      borderRadius: BorderRadius.circular(9),
      child: Container(
        margin: const EdgeInsets.only(right: 7),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0x2EF10B1D) : const Color(0xFF101010),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: active ? const Color(0x80F10B1D) : const Color(0xFF303030)),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? const Color(0xFFFF9CA5) : const Color(0xFF9A9A9A),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .6)),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// FOOD order card (original)
// ---------------------------------------------------------------------
class _OrderCard extends StatelessWidget {
  final Order order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final showOtp =
        order.status == OrderStatus.outForDelivery && !order.otpVerified;
    final time = order.updatedAt;
    final hour = ((time.hour % 12) == 0 ? 12 : time.hour % 12);
    final minute = time.minute.toString().padLeft(2, '0');
    final ampm = time.hour < 12 ? 'AM' : 'PM';

    return Container(
      margin: const EdgeInsets.only(top: 11),
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
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(order.vendorName,
                        style:
                            const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ],
                ),
              ),
              StatusChip(status: order.status),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 13),
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
                    padding: EdgeInsets.only(
                        bottom: i == order.items.length - 1 ? 0 : 4),
                    child: Text(
                        '${order.items[i].itemName} × ${order.items[i].quantity}',
                        style: const TextStyle(
                            color: Color(0xFFC8C8C8),
                            fontSize: 11,
                            height: 1.55)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(order.status.customerCopy,
                style:
                    const TextStyle(color: AppColors.muted, fontSize: 10.5)),
          ),
          if (showOtp)
            Container(
              margin: const EdgeInsets.only(top: 11),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0x1AF10B1D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x80F10B1D)),
              ),
              child: Column(
                children: [
                  const Text('Share this OTP with the delivery partner at delivery',
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
          Padding(
            padding: const EdgeInsets.only(top: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹${order.totalAmount.round()}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Text('Updated $hour:$minute $ampm',
                    style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// PRINTOUT order card
// ---------------------------------------------------------------------
class _PrintCard extends StatelessWidget {
  final PrintOrder order;

  const _PrintCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 11),
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
                    Text(order.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(order.vendorName,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 11)),
                  ],
                ),
              ),
              _chip(order.status.name.toUpperCase()),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                '${order.copies} cop${order.copies == 1 ? 'y' : 'ies'} • '
                '${order.printSide} • BW ${order.bwPages} pg / Color ${order.colorPages} pg',
                style: const TextStyle(color: Color(0xFFC8C8C8), fontSize: 11)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹${order.totalPrice.round()}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Text('${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}',
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// HOSTEL pack order card
// ---------------------------------------------------------------------
class _HostelCard extends StatelessWidget {
  final Map<String, dynamic> order;

  const _HostelCard({required this.order});

  /// ⭐ v84: 'out_for_delivery' reads like a sentence, not a key.
  String get _label {
    switch ('${order['status']}') {
      case 'out_for_delivery':
        return 'OUT FOR DELIVERY';
      case 'delivered':
        return 'DELIVERED';
      case 'cancelled':
        return 'CANCELLED';
      case 'accepted':
        return 'ACCEPTED';
      default:
        return 'PLACED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _label;
    final otp = ('${order['delivery_otp'] ?? ''}');
    final otpDone = (order['otp_verified'] ?? false) == true;
    return Container(
      margin: const EdgeInsets.only(top: 11),
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
                    Text('${order['order_no']}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFFD34D))),
                    const SizedBox(height: 4),
                    // ⭐ v60: item summary instead of the old fixed pack
                    Text(
                        (order['items'] as List? ?? []).isNotEmpty
                            ? [
                                for (final it
                                    in (order['items'] as List))
                                  '${(it as Map)['name']} ×${it['qty']}'
                              ].join(', ')
                            : 'Hostel Essentials',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 11)),
                  ],
                ),
              ),
              _chip(status),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                'Recipient: ${order['recipient_name']} • ${order['recipient_mobile']}',
                style: const TextStyle(color: Color(0xFFC8C8C8), fontSize: 11)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('${order['address']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: AppColors.muted, fontSize: 10.5)),
          ),
          // ⭐ v84: the hand-over OTP — it shows from ACCEPTED through
          // OUT FOR DELIVERY, exactly like the printout orders.
          if (otp.isNotEmpty && otp != 'null' && !otpDone) ...[
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
                const Text('Show this OTP when he hands the order over',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFFFFB0B7),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text(otp,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 7)),
              ]),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹${(order['total'] as num? ?? 1799).round()}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Text('${order['created_at']}',
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _chip(String label) {
  Color c;
  switch (label) {
    case 'COMPLETED':
    case 'DELIVERED':
      c = const Color(0xFF7ED98B);
      break;
    case 'CANCELLED':
    case 'REJECTED':
      c = const Color(0xFFF10B1D);
      break;
    case 'ACCEPTED':
    case 'PRINTING':
    case 'READY':
    case 'OUTFORDELIVERY':
      c = const Color(0xFF38BDF8);
      break;
    default:
      c = const Color(0xFFFFD34D);
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: c.withOpacity(.14),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: c.withOpacity(.5)),
    ),
    child: Text(label,
        style: TextStyle(
            color: c, fontSize: 9, fontWeight: FontWeight.w800)),
  );
}

// ---------------------------------------------------------------------
// ⭐ v83: RIDE row — one of the student's rides inside My Orders
// ---------------------------------------------------------------------
class _RideRow extends StatelessWidget {
  final Map<String, dynamic> ride;

  const _RideRow({required this.ride});

  String get _status =>
      (ride['status'] ?? 'requested').toString().toUpperCase();

  String get _when {
    final iso = (ride['created_at'] ?? '').toString();
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final t = d.toLocal();
    return '${t.day}/${t.month} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final from = (ride['pickup_text'] ?? '').toString();
    final to = (ride['drop_text'] ?? '').toString();
    final fare = (ride['total'] as num? ?? 0).round();
    final code = (ride['ride_code'] ?? '').toString();
    final icon = (ride['vehicle_icon'] ?? '🚗').toString();

    return Container(
      margin: const EdgeInsets.only(top: 11),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(code.isEmpty ? 'Ride' : code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF5F5F5))),
            ),
            _chip(_status),
          ]),
          if (from.isNotEmpty || to.isNotEmpty) ...[
            const SizedBox(height: 9),
            _routeLine(Icons.trip_origin_rounded, from),
            const SizedBox(height: 5),
            _routeLine(Icons.place_rounded, to),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Text('₹$fare',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(_when,
                style:
                    const TextStyle(color: AppColors.muted, fontSize: 10.5)),
          ]),
        ],
      ),
    );
  }

  Widget _routeLine(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF7A7A7A)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text.isEmpty ? '—' : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.muted, fontSize: 11)),
          ),
        ],
      );
}

// ---------------------------------------------------------------------
// ⭐ v83: AUTO row — one tap of the AUTO button, from the student's side
// ---------------------------------------------------------------------
class _AutoRow extends StatelessWidget {
  final Map<String, dynamic> call;

  const _AutoRow({required this.call});

  String get _status => (call['status'] ?? 'pending').toString();

  String get _when {
    final iso = (call['created_at_iso'] ?? '').toString();
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final t = d.toLocal();
    return '${t.day}/${t.month} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final rider = (call['rider_name'] ?? '').toString();
    final riderPhone = (call['rider_phone'] ?? '').toString();
    final accepted = _status == 'accepted';
    final note = accepted
        ? (rider.isEmpty
            ? 'An auto partner accepted'
            : '$rider is on the way'
                '${riderPhone.isEmpty ? '' : ' · $riderPhone'}')
        : (_status == 'pending'
            ? 'Waiting for an auto partner'
            : (_status == 'declined' ? 'No partner took it' : 'Call expired'));

    return Container(
      margin: const EdgeInsets.only(top: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x59F10B1D)),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0x2EF10B1D),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('🛺', style: TextStyle(fontSize: 15)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AUTO CALL',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 10.5)),
              const SizedBox(height: 3),
              Text('Pickup: the main gate',
                  style: const TextStyle(
                      color: Color(0xFF7A7A7A), fontSize: 10)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _chip(_status.toUpperCase()),
            const SizedBox(height: 5),
            Text(_when,
                style:
                    const TextStyle(color: AppColors.muted, fontSize: 10)),
          ],
        ),
      ]),
    );
  }
}
