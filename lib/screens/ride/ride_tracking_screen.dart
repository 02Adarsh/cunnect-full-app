import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../services/open_url_stub.dart'
    if (dart.library.html) '../../services/open_url_web.dart'
    if (dart.library.io) '../../services/open_url_mobile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'ride_home_screen.dart';
import 'ride_live_map_screen.dart';

/// ⭐ v68: live ride screen.
///
///  requested -> finding a rider (cancel allowed)
///  accepted  -> PAYMENT (full or 50-50 with +5%)
///  paid      -> rider coming — LIVE MAP shows him moving
///  arrived   -> the OTP is on THIS screen; read it out to the rider,
///               he types it in his console and the ride starts
///  ongoing   -> ride running (route + rider on the map)
///  completed -> pay the remaining half if you rode 50-50
class RideTrackingScreen extends StatefulWidget {
  final String rideCode;

  const RideTrackingScreen({super.key, required this.rideCode});

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  Timer? _timer;
  Timer? _gps;
  bool _share = false;
  Map<String, dynamic>? _ride;
  bool _loading = true;
  String? _error;

  // payment
  String _mode = 'full';
  final _txn = TextEditingController();
  bool _paying = false;
  Map<String, dynamic>? _qr;
  bool _qrLoading = false;

  @override
  void initState() {
    super.initState();
    // ⭐ INSTANT: paint the last known copy first, then refresh.
    final cached = context.read<AppStore>().cachedRide();
    if (cached != null && '${cached['ride_code']}' == widget.rideCode) {
      _ride = cached;
      _loading = false;
    }
    _refresh();
    // ⭐ real-time: 5s while the ride is live, slower once finished.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _gps?.cancel();
    _txn.dispose();
    super.dispose();
  }

  // ⭐ v72: share the student's own live position with the rider.
  Future<void> _pushLocation() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await context.read<AppStore>().rideStudentLocation(widget.rideCode,
          lat: pos.latitude, lng: pos.longitude, share: true);
    } catch (_) {}
  }

  Future<void> _toggleShare(bool value) async {
    final store = context.read<AppStore>();
    setState(() => _share = value);
    if (value) {
      await store.rideStudentLocation(widget.rideCode, share: true);
      _gps?.cancel();
      await _pushLocation();
      _gps = Timer.periodic(
          const Duration(seconds: 10), (_) => _pushLocation());
      if (mounted) {
        showCunnectToast(context, 'Sharing your live location with the rider');
      }
    } else {
      _gps?.cancel();
      _gps = null;
      await store.rideStudentLocation(widget.rideCode, share: false);
      if (mounted) {
        showCunnectToast(context, 'Live location sharing turned off');
      }
    }
  }

  Future<void> _refresh() async {
    final store = context.read<AppStore>();
    await store.refreshActiveRide(widget.rideCode);
    if (!mounted) return;
    final fresh = store.activeRide;
    setState(() {
      if (fresh != null) {
        _ride = fresh;
        _share = (fresh['share_location'] ?? false) == true;
      }
      _loading = false;
    });
  }

  Future<void> _loadQr(num amount) async {
    if (amount <= 0) return;
    final ride = _ride;
    if (ride == null) return;
    final vendorId = ride['vendor_id'];
    if (vendorId == null) return;
    setState(() => _qrLoading = true);
    final qr = await context.read<AppStore>().fetchUpiQr(
        vendorId is int ? vendorId : int.tryParse('$vendorId') ?? 0, amount);
    if (!mounted) return;
    setState(() {
      _qr = qr;
      _qrLoading = false;
    });
  }

  Future<void> _pay() async {
    if (_paying) return;
    final txn = _txn.text.trim();
    if (txn.isEmpty) {
      setState(() => _error = 'Paste the transaction ID after paying.');
      return;
    }
    setState(() {
      _paying = true;
      _error = null;
    });
    final res = await context
        .read<AppStore>()
        .ridePay(widget.rideCode, _mode, txn);
    if (!mounted) return;
    setState(() => _paying = false);
    if (res['ok'] != true) {
      setState(() => _error = '${res['error']}');
      return;
    }
    _txn.clear();
    setState(() => _qr = null);
    await _refresh();
  }

  Future<void> _payBalance() async {
    if (_paying) return;
    final txn = _txn.text.trim();
    if (txn.isEmpty) {
      setState(() => _error = 'Paste the transaction ID after paying.');
      return;
    }
    setState(() {
      _paying = true;
      _error = null;
    });
    final res =
        await context.read<AppStore>().ridePayBalance(widget.rideCode, txn);
    if (!mounted) return;
    setState(() => _paying = false);
    if (res['ok'] != true) {
      setState(() => _error = '${res['error']}');
      return;
    }
    _txn.clear();
    setState(() => _qr = null);
    await _refresh();
  }

  Future<void> _cancel() async {
    final okCancel = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF111111),
            title: const Text('Cancel this ride?',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: const Text(
                'The request will be removed from the riders\' list.',
                style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('KEEP',
                      style: TextStyle(color: Color(0xFF9E9E9E)))),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('CANCEL RIDE',
                      style: TextStyle(color: AppColors.red))),
            ],
          ),
        ) ??
        false;
    if (!okCancel) return;
    final err = await context.read<AppStore>().rideCancel(widget.rideCode);
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop();
  }

  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    final status = ride == null ? '' : '${ride['status']}';

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        backgroundColor: AppColors.page,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('MY RIDE',
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.red, strokeWidth: 2))
          : ride == null
              ? const Center(
                  child: Text('Ride not found.',
                      style: TextStyle(color: Color(0xFF9E9E9E))))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                  children: [
                    _statusHeader(ride, status),
                    const SizedBox(height: 14),
                    // ⭐ v68: live map (pickup -> rider -> destination)
                    if (status == 'paid' ||
                        status == 'arrived' ||
                        status == 'ongoing') ...[
                      _liveMap(ride, status),
                      const SizedBox(height: 14),
                    ],
                    _tripCard(ride),
                    const SizedBox(height: 14),
                    if (status == 'requested') _searchingCard(ride),
                    if (status == 'accepted') _paymentCard(ride),
                    if (status == 'paid' ||
                        status == 'arrived' ||
                        status == 'ongoing') ...[
                      _riderCard(ride, status),
                      const SizedBox(height: 12),
                      _shareTile(),
                    ],
                    if (status == 'arrived') ...[
                      const SizedBox(height: 14),
                      _otpCard(ride),
                    ],
                    if (status == 'completed') _completedCard(ride),
                    if (status == 'rejected' || status == 'cancelled') ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context)
                              .pushReplacement(MaterialPageRoute(
                                  builder: (_) => const RideHomeScreen())),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.red),
                            foregroundColor: AppColors.red,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)),
                          ),
                          child: const Text('BOOK FOR ANOTHER TIME',
                              style: TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Color(0xFFFF8791), fontSize: 12.5)),
                      ),
                  ],
                ),
    );
  }

  // ------------------------------ map -------------------------------

  Widget _liveMap(Map<String, dynamic> ride, String status) {
    final pLat = (ride['pickup_lat'] as num?)?.toDouble();
    final pLng = (ride['pickup_lng'] as num?)?.toDouble();
    final dLat = (ride['drop_lat'] as num?)?.toDouble();
    final dLng = (ride['drop_lng'] as num?)?.toDouble();
    final rLat = (ride['rider_lat'] as num?)?.toDouble();
    final rLng = (ride['rider_lng'] as num?)?.toDouble();
    if (pLat == null || pLng == null || dLat == null || dLng == null) {
      return const SizedBox.shrink();
    }
    final pickup = LatLng(pLat, pLng);
    final drop = LatLng(dLat, dLng);
    final rider = (rLat != null && rLng != null) ? LatLng(rLat, rLng) : null;

    final points = <LatLng>[
      if (status != 'ongoing' && rider != null) rider,
      pickup,
      drop,
    ];
    final centre = status == 'ongoing' && rider != null ? rider : pickup;

    // ETA: rider -> pickup while coming, pickup -> drop once started.
    final km = rider != null && status != 'ongoing'
        ? _km(rider.latitude, rider.longitude, pLat, pLng)
        : _km(pLat, pLng, dLat, dLng);
    final mins = (km / 22 * 60).round();

    return Container(
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: centre,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.cunnect.cunnect_food',
                maxZoom: 19,
              ),
              PolylineLayer(polylines: [
                Polyline(
                  points: points,
                  color: AppColors.red.withOpacity(.85),
                  strokeWidth: 4,
                ),
              ]),
              MarkerLayer(markers: [
                Marker(
                  point: pickup,
                  width: 34,
                  height: 34,
                  child: const Icon(Icons.my_location_rounded,
                      color: Color(0xFF98E6B0), size: 26),
                ),
                Marker(
                  point: drop,
                  width: 34,
                  height: 34,
                  child: const Icon(Icons.location_on_rounded,
                      color: AppColors.red, size: 30),
                ),
                if (rider != null)
                  Marker(
                    point: rider,
                    width: 38,
                    height: 38,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Center(
                        child: Text('${ride['vehicle_icon']}',
                            style: const TextStyle(fontSize: 17)),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xE6141414),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0x26FFFFFF)),
              ),
              child: Text(
                rider != null
                    ? (status == 'ongoing'
                        ? 'Destination in ~$mins min'
                        : 'Rider ~$mins min away')
                    : 'Waiting for the rider\'s location…',
                style: const TextStyle(color: Colors.white, fontSize: 11.5),
              ),
            ),
          ),
          // ⭐ v72: open the FULL SCREEN live map
          Positioned(
            right: 10,
            top: 52,
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      RideLiveMapScreen(rideCode: widget.rideCode))),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xE6141414),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0x26FFFFFF)),
                ),
                child: const Icon(Icons.fullscreen_rounded,
                    size: 17, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: GestureDetector(
              onTap: _refresh,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xE6141414),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x26FFFFFF)),
                ),
                child: const Icon(Icons.refresh_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ⭐ v72: let the rider see exactly where the student is standing.
  Widget _shareTile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Row(children: [
        Icon(
            _share
                ? Icons.my_location_rounded
                : Icons.location_disabled_rounded,
            size: 17,
            color: _share ? AppColors.red : const Color(0xFF7A7A7F)),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share my live location',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('The rider sees your exact pickup spot',
                  style: TextStyle(color: Color(0xFF7A7A7F), fontSize: 10.5)),
            ],
          ),
        ),
        Switch(
            value: _share,
            activeColor: AppColors.red,
            onChanged: _toggleShare),
      ]),
    );
  }

  /// Straight-line km (x1.25 road factor, same as the server).
  double _km(double la1, double lo1, double la2, double lo2) {
    const r = 6371.0;
    final dLat = math.pi * (la2 - la1) / 180;
    final dLng = math.pi * (lo2 - lo1) / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(math.pi * la1 / 180) *
            math.cos(math.pi * la2 / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c * 1.25;
  }

  // ---------------------------- status ------------------------------

  Widget _statusHeader(Map<String, dynamic> ride, String status) {
    final map = {
      'requested': ('Finding your rider', 'Ride requests are going out now'),
      'accepted': ('Rider accepted 🎉', 'Complete the payment to confirm'),
      'paid': ('Rider on the way', 'Your rider is heading to the pickup'),
      'arrived': ('Rider has arrived', 'Read out the OTP below to start'),
      'ongoing': ('Ride in progress', 'Have a safe trip'),
      'completed': ('Ride completed', 'Thanks for riding with CUnnect'),
      'cancelled': ('Ride cancelled', 'You can book a new ride anytime'),
      'rejected': ('Rider unavailable right now',
          'Every ride partner is busy at that time. '
              'Please book the ride for another time slot.'),
    };
    final m = map[status] ?? ('Ride $status', '');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: status == 'cancelled'
                ? const Color(0xFF3A3A3A)
                : AppColors.red.withOpacity(.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(m.$1,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(m.$2,
              style: const TextStyle(
                  color: AppColors.muted, fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }

  Widget _tripCard(Map<String, dynamic> ride) {
    final fare = (ride['fare'] as num?)?.toDouble() ?? 0;
    final total = (ride['total'] as num?)?.toDouble() ?? 0;
    final base = (ride['base_fare'] as num?)?.toDouble() ?? 0;
    final perKm = (ride['per_km'] as num?)?.toDouble() ?? 0;
    final km = (ride['distance_km'] as num?)?.toDouble() ?? 0;
    final when = '${ride['scheduled_at'] ?? ''}';
    final whenDt = DateTime.tryParse(when);

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${ride['vehicle_icon']}',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Text('${ride['vehicle_label']}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              if ('${ride['rider_vehicle'] ?? ''}'.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1013),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.red.withOpacity(.45)),
                  ),
                  child: Text('${ride['rider_vehicle']}',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _dot(const Color(0xFF98E6B0), '${ride['pickup_text']}'),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: SizedBox(
              height: 18,
              child: VerticalDivider(
                  color: Color(0xFF303030), thickness: 1, width: 20),
            ),
          ),
          _dot(AppColors.red, '${ride['drop_text']}'),
          const SizedBox(height: 12),
          // ⭐ v68: scheduled time + notes
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (whenDt != null)
                _chip(Icons.schedule_rounded,
                    '${_day(whenDt)} ${whenDt.hour.toString().padLeft(2, '0')}:${whenDt.minute.toString().padLeft(2, '0')}'),
              _chip(Icons.straighten_rounded, '${ride['distance_km']} km'),
              _chip(Icons.timer_outlined,
                  '~${(km / 22 * 60).round()} min'),
              if ('${ride['notes'] ?? ''}'.isNotEmpty)
                _chip(Icons.notes_rounded, '${ride['notes']}'),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF202020), height: 1),
          const SizedBox(height: 12),
          // ⭐ v68: fare breakdown like Uber
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fareLine('Base fare', '₹${base.toStringAsFixed(0)}'),
                    const SizedBox(height: 4),
                    _fareLine('${km.toStringAsFixed(2)} km × ₹${perKm.toStringAsFixed(0)}',
                        '₹${(perKm * km).toStringAsFixed(0)}'),
                    if ((ride['split_fee'] as num? ?? 0) > 0) ...[
                      const SizedBox(height: 4),
                      _fareLine('Split fee (5%)',
                          '₹${((ride['split_fee'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  Text('total (base ₹${fare.toStringAsFixed(0)})',
                      style: const TextStyle(
                          color: Color(0xFF6A6A6A), fontSize: 10)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fareLine(String k, String v) => Row(
        children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(
                      color: Color(0xFF8A8A8A), fontSize: 11.5))),
          Text(v,
              style: const TextStyle(color: Color(0xFFB7B7BC), fontSize: 11.5)),
        ],
      );

  String _day(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    if (d.year == now.year &&
        d.month == now.month &&
        d.day == now.day + 1) {
      return 'Tomorrow';
    }
    return '${d.day}/${d.month}';
  }

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF9E9E9E)),
            const SizedBox(width: 6),
            Text(text,
                style: const TextStyle(
                    color: Color(0xFFB7B7BC), fontSize: 11.5)),
          ],
        ),
      );

  Widget _dot(Color color, String text) => Row(
        children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 11),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      );

  Widget _searchingCard(Map<String, dynamic> ride) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: AppColors.red, strokeWidth: 2),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                    'Notifying nearby ride partners. You will get a '
                    'notification the moment someone accepts.',
                    style: TextStyle(
                        color: Color(0xFFB7B7BC), fontSize: 12.5, height: 1.5)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: _cancel,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF3A3A3A)),
              foregroundColor: const Color(0xFFFF8791),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('CANCEL RIDE',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  // ---------------------------- PAYMENT -----------------------------

  Widget _paymentCard(Map<String, dynamic> ride) {
    final fare = (ride['fare'] as num?)?.toDouble() ?? 0;
    final fullTotal = fare;
    final splitTotal = fare * 1.05;
    final splitNow = splitTotal / 2;
    final splitLater = splitTotal - splitNow;
    final amount = _mode == 'full' ? fullTotal : splitNow;

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withOpacity(.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PAYMENT',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 2,
                  color: Color(0xFF7A7A7A),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _modeTile(
            'full',
            'Pay in full',
            '₹${fullTotal.toStringAsFixed(2)} now · no extra charge',
          ),
          const SizedBox(height: 8),
          _modeTile(
            'split',
            'Pay 50-50',
            '₹${splitNow.toStringAsFixed(2)} now + ₹${splitLater.toStringAsFixed(2)} after the ride · +5% (₹${(splitTotal - fare).toStringAsFixed(2)})',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Pay now',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12.5)),
              const Spacer(),
              Text('₹${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: _qr == null
                ? SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _qrLoading ? null : () => _loadQr(amount),
                      icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                      label: Text(
                          _qrLoading ? 'GENERATING…' : 'SHOW PAYMENT QR',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w800)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.red),
                        foregroundColor: AppColors.red,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  )
                : _qrBlock(_qr!),
          ),
          const SizedBox(height: 14),
          const PaymentSteps(actionLabel: 'Confirm Payment'),
          const SizedBox(height: 8),
          TextField(
            controller: _txn,
            keyboardType: TextInputType.text,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: cunnectInputDecoration(
                placeholder: 'Transaction ID after payment'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _paying ? null : _pay,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _paying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('CONFIRM PAYMENT',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTile(String key, String title, String sub) {
    final selected = _mode == key;
    return InkWell(
      onTap: () {
        setState(() {
          _mode = key;
          _qr = null;
        });
      },
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color:
              selected ? const Color(0xFF1C1013) : const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: selected ? AppColors.red : const Color(0xFF262626)),
        ),
        child: Row(
          children: [
            Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.red : const Color(0xFF6A6A6A),
                size: 18),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: const TextStyle(
                          color: Color(0xFF9E9E9E),
                          fontSize: 11,
                          height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qrBlock(Map<String, dynamic> qr) {
    final b64 = '${qr['qr_b64'] ?? ''}';
    final upi = '${qr['upi_id'] ?? ''}';
    return Column(
      children: [
        if (b64.isNotEmpty)
          GestureDetector(
            onTap: () => _showQrFull(b64),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.memory(base64Decode(b64), width: 168, height: 168),
            ),
          ),
        const SizedBox(height: 10),
        if (upi.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(upi,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: upi));
                  if (mounted) showCunnectToast(context, 'UPI ID copied');
                },
                child: const Icon(Icons.copy_rounded,
                    size: 16, color: Color(0xFF9E9E9E)),
              ),
            ],
          ),
        const SizedBox(height: 4),
        const Text('tap the QR to enlarge',
            style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 10.5)),
      ],
    );
  }

  void _showQrFull(String b64) {
    showDialog(
      context: context,
      barrierColor: const Color(0xF2000000),
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Image.memory(base64Decode(b64),
                width: MediaQuery.of(context).size.width * 0.78),
          ),
        ),
      ),
    );
  }

  // ----------------------------- RIDER ------------------------------

  Widget _riderCard(Map<String, dynamic> ride, String status) {
    final name = '${ride['rider_name'] ?? ''}';
    final phone = '${ride['rider_phone'] ?? ''}';
    final vehicle = '${ride['rider_vehicle'] ?? ''}';
    final model = '${ride['rider_model'] ?? ''}';
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red.withOpacity(.13),
                  border: Border.all(color: AppColors.red.withOpacity(.4)),
                ),
                child: Text('${ride['vehicle_icon']}',
                    style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? 'Your rider' : name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                        [model, '${ride['vehicle_label']}']
                            .where((e) => e.trim().isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(
                            color: Color(0xFF9E9E9E), fontSize: 11.5)),
                    if (vehicle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(vehicle,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              color: Color(0xFFB7B7BC),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: () => openExternalUrl('tel:$phone'),
                      icon: const Icon(Icons.call_rounded, size: 17),
                      label: Text(phone,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF3A3A3A)),
                        foregroundColor: const Color(0xFF98E6B0),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// ⭐ v68: the OTP lives HERE — the student reads it out, the rider
  /// types it into his console.
  Widget _otpCard(Map<String, dynamic> ride) {
    final otp = '${ride['otp'] ?? ''}';
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 18, 15, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD34D).withOpacity(.5)),
      ),
      child: Column(
        children: [
          const Text('START OTP',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 2.2,
                  color: Color(0xFFFFD34D),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            otp.isEmpty ? '••••' : otp,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                letterSpacing: 12,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your rider is at the pickup point. Read this OTP out to '
            'him — he enters it and your ride starts.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Color(0xFF9E9E9E), fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _completedCard(Map<String, dynamic> ride) {
    final balance = (ride['balance_due'] as num?)?.toDouble() ?? 0;
    if (balance > 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: const Color(0xFFFFD34D).withOpacity(.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('BALANCE DUE',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    letterSpacing: 2,
                    color: Color(0xFFFFD34D),
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
                'Clear the second half of your 50-50 ride: ₹${balance.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.5)),
            const SizedBox(height: 12),
            Center(
              child: _qr == null
                  ? SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _qrLoading ? null : () => _loadQr(balance),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                        label: const Text('SHOW PAYMENT QR',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.red),
                          foregroundColor: AppColors.red,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    )
                  : _qrBlock(_qr!),
            ),
            const SizedBox(height: 10),
            const PaymentSteps(actionLabel: 'Pay Balance'),
            const SizedBox(height: 8),
            TextField(
              controller: _txn,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              decoration: cunnectInputDecoration(
                  placeholder: 'Transaction ID after payment'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _paying ? null : _payBalance,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('PAY BALANCE',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF98E6B0), size: 34),
          const SizedBox(height: 10),
          const Text('Your ride has been completed successfully',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              'Total paid ₹${((ride['amount_paid'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
        ],
      ),
    );
  }
}
