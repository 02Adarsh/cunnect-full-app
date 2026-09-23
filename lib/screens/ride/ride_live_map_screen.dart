import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../services/open_url_stub.dart'
    if (dart.library.html) '../../services/open_url_web.dart'
    if (dart.library.io) '../../services/open_url_mobile.dart';
import '../../data/up_places.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// ⭐ v72: FULL-SCREEN live map.
///
/// Everything the old 210 px map showed, but the whole screen:
///   • pickup + destination pins
///   • the rider's vehicle moving in real time (5 s refresh)
///   • the student's own dot when they share their location
///   • live route line + ETA
///   • follow-the-rider camera, zoom buttons, one-tap recentre
///   • call the rider, read out the OTP, pay — without leaving the map
class RideLiveMapScreen extends StatefulWidget {
  final String rideCode;

  const RideLiveMapScreen({super.key, required this.rideCode});

  @override
  State<RideLiveMapScreen> createState() => _RideLiveMapScreenState();
}

class _RideLiveMapScreenState extends State<RideLiveMapScreen> {
  final MapController _map = MapController();
  Timer? _poll;
  Timer? _gps;
  bool _follow = true;
  bool _share = false;
  double _zoom = 15;
  Map<String, dynamic>? _ride;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // ⭐ paint instantly from the cache, then refresh in the background
    _ride = context.read<AppStore>().cachedRide();
    if ((_ride?['ride_code'] ?? '') != widget.rideCode) _ride = null;
    _loading = _ride == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh(silent: true);
      _startSharingIfNeeded();
    });
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _gps?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    final store = context.read<AppStore>();
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final ride = await store.rideDetail(widget.rideCode);
      if (!mounted || ride == null) return;
      setState(() {
        _ride = ride;
        _loading = false;
        _error = null;
        _share = (ride['share_location'] ?? false) == true;
      });
      if (_follow) _centreOn(ride);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not refresh the live map.';
      });
    }
  }

  void _centreOn(Map<String, dynamic> ride) {
    final status = (ride['status'] ?? '').toString();
    final rLat = (ride['rider_lat'] as num?)?.toDouble();
    final rLng = (ride['rider_lng'] as num?)?.toDouble();
    final pLat = (ride['pickup_lat'] as num?)?.toDouble();
    final pLng = (ride['pickup_lng'] as num?)?.toDouble();
    double? la;
    double? lo;
    if (status == 'ongoing' && rLat != null && rLng != null) {
      la = rLat;
      lo = rLng;
    } else if (pLat != null && pLng != null) {
      la = pLat;
      lo = pLng;
    }
    if (la == null || lo == null) return;
    try {
      _map.move(LatLng(la, lo), _zoom);
    } catch (_) {}
  }

  // ------------------------- live sharing ---------------------------

  void _startSharingIfNeeded() {
    if ((_ride?['share_location'] ?? false) == true) _startSharing();
  }

  Future<void> _startSharing() async {
    _gps?.cancel();
    await _pushLocation();
    _gps = Timer.periodic(
        const Duration(seconds: 10), (_) => _pushLocation());
  }

  Future<void> _pushLocation() async {
    final store = context.read<AppStore>();
    try {
      var ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await store.rideStudentLocation(widget.rideCode,
          lat: pos.latitude, lng: pos.longitude, share: true);
    } catch (_) {}
  }

  Future<void> _toggleShare(bool value) async {
    final store = context.read<AppStore>();
    setState(() => _share = value);
    if (value) {
      await store.rideStudentLocation(widget.rideCode, share: true);
      await _startSharing();
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

  // ----------------------------- build ------------------------------

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (ride != null)
          Positioned.fill(child: _mapView(ride))
        else
          const Center(
              child: CircularProgressIndicator(color: AppColors.red)),
        // ---- top bar -------------------------------------------------
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                _roundButton(Icons.arrow_back_rounded,
                    () => Navigator.of(context).pop()),
                const SizedBox(width: 10),
                if (ride != null) Expanded(child: _statusPill(ride)),
              ]),
            ),
          ),
        ),
        // ---- map controls --------------------------------------------
        if (ride != null)
          Positioned(
            right: 12,
            bottom: 200,
            child: Column(children: [
              _roundButton(Icons.add_rounded, () {
                setState(() => _zoom = (_zoom + 1).clamp(3.0, 19.0).toDouble());
                _centreOn(ride);
              }),
              const SizedBox(height: 9),
              _roundButton(Icons.remove_rounded, () {
                setState(() => _zoom = (_zoom - 1).clamp(3.0, 19.0).toDouble());
                _centreOn(ride);
              }),
              const SizedBox(height: 9),
              _roundButton(
                _follow
                    ? Icons.gps_fixed_rounded
                    : Icons.gps_not_fixed_rounded,
                () {
                  setState(() => _follow = !_follow);
                  if (_follow) _centreOn(ride);
                },
                active: _follow,
              ),
              const SizedBox(height: 9),
              _roundButton(Icons.refresh_rounded, () => _refresh()),
            ]),
          ),
        // ---- bottom sheet ---------------------------------------------
        if (ride != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottomCard(ride),
          ),
        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
                color: AppColors.red, backgroundColor: Colors.transparent),
          ),
      ]),
    );
  }

  // ------------------------------ map -------------------------------

  Widget _mapView(Map<String, dynamic> ride) {
    final pLat = (ride['pickup_lat'] as num?)?.toDouble();
    final pLng = (ride['pickup_lng'] as num?)?.toDouble();
    final dLat = (ride['drop_lat'] as num?)?.toDouble();
    final dLng = (ride['drop_lng'] as num?)?.toDouble();
    final rLat = (ride['rider_lat'] as num?)?.toDouble();
    final rLng = (ride['rider_lng'] as num?)?.toDouble();
    final sLat = (ride['student_lat'] as num?)?.toDouble();
    final sLng = (ride['student_lng'] as num?)?.toDouble();
    final status = (ride['status'] ?? '').toString();
    final icon = (ride['vehicle_icon'] ?? '🚗').toString();

    final markers = <Marker>[
      if (pLat != null && pLng != null)
        Marker(
          point: LatLng(pLat, pLng),
          width: 40,
          height: 40,
          child: _pin(const Color(0xFFF5F5F5), Icons.trip_origin_rounded),
        ),
      if (dLat != null && dLng != null)
        Marker(
          point: LatLng(dLat, dLng),
          width: 42,
          height: 42,
          child: _pin(AppColors.red, Icons.location_on_rounded),
        ),
      if (rLat != null && rLng != null)
        Marker(
          point: LatLng(rLat, rLng),
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(.5), blurRadius: 8)
              ],
            ),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 19)),
          ),
        ),
      if (sLat != null && sLng != null)
        Marker(
          point: LatLng(sLat, sLng),
          width: 26,
          height: 26,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
    ];

    final polylines = <Polyline>[
      if (pLat != null && dLat != null)
        Polyline(
          points: [LatLng(pLat, pLng!), LatLng(dLat, dLng!)],
          color: Colors.white.withOpacity(.35),
          strokeWidth: 3,
        ),
      if (rLat != null && pLat != null && status != 'ongoing')
        Polyline(
          points: [LatLng(rLat, rLng!), LatLng(pLat, pLng!)],
          color: AppColors.red.withOpacity(.9),
          strokeWidth: 4,
        ),
      if (rLat != null && dLat != null && status == 'ongoing')
        Polyline(
          points: [LatLng(rLat, rLng!), LatLng(dLat, dLng!)],
          color: AppColors.red.withOpacity(.9),
          strokeWidth: 4,
        ),
    ];

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: LatLng(pLat ?? kCampusLat, pLng ?? kCampusLng),
        initialZoom: _zoom,
        minZoom: 3,
        maxZoom: 19,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.cunnect.cunnect_food',
          maxZoom: 19,
        ),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _pin(Color color, IconData icon) => Container(
        decoration: BoxDecoration(
          color: const Color(0xE6141414),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 20),
      );

  Widget _roundButton(IconData icon, VoidCallback onTap, {bool active = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.red : const Color(0xE6141414),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x33FFFFFF)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(.45), blurRadius: 10)
            ],
          ),
          child: Icon(icon, size: 19, color: Colors.white),
        ),
      );

  Widget _statusPill(Map<String, dynamic> ride) {
    final status = (ride['status'] ?? '').toString();
    final label = {
      'requested': 'Finding your rider',
      'accepted': 'Rider accepted — pay to confirm',
      'paid': 'Rider on the way',
      'arrived': 'Rider has arrived',
      'ongoing': 'Ride in progress',
      'completed': 'Ride completed',
      'cancelled': 'Ride cancelled',
      'rejected': 'No rider available',
    }[status] ??
        'Live map';
    final km = _etaKm(ride);
    final mins = (km / 22 * 60).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xE6141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            status == 'ongoing'
                ? 'Destination in ~$mins min · ${km.toStringAsFixed(1)} km'
                : (ride['rider_lat'] != null
                    ? 'Rider ~$mins min away · ${km.toStringAsFixed(1)} km'
                    : '${km.toStringAsFixed(1)} km · ${ride['vehicle_label'] ?? ''}'),
            style: const TextStyle(color: Color(0xFFB9B9BE), fontSize: 11),
          ),
        ],
      ),
    );
  }

  double _etaKm(Map<String, dynamic> ride) {
    final pLat = (ride['pickup_lat'] as num?)?.toDouble();
    final pLng = (ride['pickup_lng'] as num?)?.toDouble();
    final dLat = (ride['drop_lat'] as num?)?.toDouble();
    final dLng = (ride['drop_lng'] as num?)?.toDouble();
    final rLat = (ride['rider_lat'] as num?)?.toDouble();
    final rLng = (ride['rider_lng'] as num?)?.toDouble();
    final status = (ride['status'] ?? '').toString();
    if (rLat != null && rLng != null && pLat != null && pLng != null &&
        status != 'ongoing') {
      return _km(rLat, rLng, pLat, pLng);
    }
    if (pLat != null && pLng != null && dLat != null && dLng != null) {
      return _km(pLat, pLng, dLat, dLng);
    }
    return 0;
  }

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

  // --------------------------- bottom card ---------------------------

  Widget _bottomCard(Map<String, dynamic> ride) {
    final status = (ride['status'] ?? '').toString();
    final riderName = (ride['rider_name'] ?? '').toString();
    final riderPhone = (ride['rider_phone'] ?? '').toString();
    final vehicle = (ride['rider_vehicle'] ?? '').toString();
    final model = (ride['rider_model'] ?? '').toString();
    final otp = (ride['otp'] ?? '').toString();
    final live = status == 'paid' ||
        status == 'arrived' ||
        status == 'ongoing';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF2141414),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: const Border(top: BorderSide(color: Color(0x26FFFFFF))),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.6), blurRadius: 26)
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0x33FFFFFF),
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 12),
          // route
          _routeRow(ride),
          const SizedBox(height: 12),
          if (riderName.isNotEmpty) ...[
            Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x1FFFFFFF)),
                ),
                child: Text((ride['vehicle_icon'] ?? '🚗').toString(),
                    style: const TextStyle(fontSize: 19)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(riderName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        [
                          if (model.isNotEmpty) model,
                          if (vehicle.isNotEmpty) vehicle,
                        ].join(' · '),
                        style: const TextStyle(
                            color: Color(0xFF9C9CA1), fontSize: 11.5)),
                  ],
                ),
              ),
              if (riderPhone.isNotEmpty)
                GestureDetector(
                  onTap: () => openExternalUrl('tel:$riderPhone'),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.call_rounded,
                        color: Colors.white, size: 19),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
          ],
          if (status == 'arrived' && otp.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0x1AF10B1D),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0x59F10B1D)),
              ),
              child: Row(children: [
                const Icon(Icons.shield_rounded,
                    color: AppColors.red, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Read this OTP out to start the ride',
                      style: TextStyle(
                          color: Color(0xFFFFC9CE), fontSize: 12)),
                ),
                Text(otp,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3)),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          // ⭐ live location sharing
          if (live)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1B1B),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              child: Row(children: [
                Icon(
                    _share
                        ? Icons.my_location_rounded
                        : Icons.location_disabled_rounded,
                    size: 17,
                    color: _share ? AppColors.red : const Color(0xFF7A7A7F)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Share my live location with the rider',
                      style:
                          TextStyle(color: Color(0xFFD6D6DA), fontSize: 12)),
                ),
                Switch(
                  value: _share,
                  activeColor: AppColors.red,
                  onChanged: _toggleShare,
                ),
              ]),
            ),
          if (status == 'accepted') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('PAY NOW',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFFF8791), fontSize: 11.5)),
            ),
        ],
      ),
    );
  }

  Widget _routeRow(Map<String, dynamic> ride) => Row(children: [
        const Icon(Icons.trip_origin_rounded,
            color: Color(0xFFF5F5F5), size: 16),
        const SizedBox(width: 9),
        Expanded(
          child: Text((ride['pickup_text'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFEDEDF0), fontSize: 12.5)),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.arrow_forward_rounded,
            size: 14, color: Color(0xFF6E6E73)),
        const SizedBox(width: 8),
        const Icon(Icons.location_on_rounded, color: AppColors.red, size: 16),
        const SizedBox(width: 9),
        Expanded(
          child: Text((ride['drop_text'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFEDEDF0), fontSize: 12.5)),
        ),
      ]);
}
