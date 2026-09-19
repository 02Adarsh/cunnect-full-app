import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../services/local_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart' show showCunnectToast;
import 'ride_live_map_screen.dart';
import 'ride_map_picker_screen.dart';
import 'ride_tracking_screen.dart';

/// ⭐ v68: CUnnect Ride — book a ride across the campus.
///
/// Pickup / drop (tap the map or search), time, vehicle — then
/// BOOK RIDE slides up an Uber-style sheet with the route, the fare
/// breakdown, your number and the note, and confirms from there.
class RideHomeScreen extends StatefulWidget {
  const RideHomeScreen({super.key});

  @override
  State<RideHomeScreen> createState() => _RideHomeScreenState();
}

class _RideHomeScreenState extends State<RideHomeScreen> {
  String _pickup = '';
  double? _pickupLat, _pickupLng;
  String _drop = '';
  double? _dropLat, _dropLng;
  String _vehicle = 'mini';
  bool _busy = false;
  bool _estimating = false;
  DateTime? _when;
  String? _error;

  final _phone = TextEditingController();
  final _notes = TextEditingController();
  // ⭐ v73: "booking for someone else" — their number is what the rider dials
  final _otherPhone = TextEditingController();
  final _otherName = TextEditingController();
  bool _forOther = false;
  List<Map<String, dynamic>> _recent = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<AppStore>();
      _phone.text = store.customerPhone;
      _loadRecent();
      // ⭐ instant: paint the cached ride/list, refresh in background.
      if (store.activeRide == null) store.cachedRide();
      await store.loadRides();
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _notes.dispose();
    _otherPhone.dispose();
    _otherName.dispose();
    super.dispose();
  }

  void _loadRecent() {
    try {
      final raw = LocalStore.get('ride_recent');
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is List) {
        _recent = [
          for (final e in list.take(6)) Map<String, dynamic>.from(e as Map)
        ];
      }
    } catch (_) {}
  }

  Future<void> _saveRecent(String text, double lat, double lng) async {
    _recent = [
      {'text': text, 'lat': lat, 'lng': lng},
      ..._recent.where((e) => '${e['text']}' != text).take(5),
    ];
    setState(() {});
    try {
      LocalStore.set('ride_recent', jsonEncode(_recent));
    } catch (_) {}
  }

  Future<void> _pick(bool isPickup) async {
    final res = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => RideMapPickerScreen(
          title: isPickup ? 'Pickup location' : 'Drop location',
          hint: isPickup
              ? 'Tap where the rider should pick you up.'
              : 'Tap where you want to be dropped.',
          initial: isPickup
              ? (_pickupLat == null
                  ? null
                  : LatLng(_pickupLat!, _pickupLng!))
              : (_dropLat == null ? null : LatLng(_dropLat!, _dropLng!)),
        ),
      ),
    );
    if (res == null || !mounted) return;
    setState(() {
      if (isPickup) {
        _pickup = '${res['text']}';
        _pickupLat = (res['lat'] as num).toDouble();
        _pickupLng = (res['lng'] as num).toDouble();
      } else {
        _drop = '${res['text']}';
        _dropLat = (res['lat'] as num).toDouble();
        _dropLng = (res['lng'] as num).toDouble();
      }
      _error = null;
    });
    _saveRecent('${res['text']}', (res['lat'] as num).toDouble(),
        (res['lng'] as num).toDouble());
    await _estimate();
  }

  Future<void> _estimate() async {
    if (_pickupLat == null || _dropLat == null) return;
    setState(() => _estimating = true);
    final err = await context.read<AppStore>().rideEstimate(
          pickupLat: _pickupLat!,
          pickupLng: _pickupLng!,
          dropLat: _dropLat!,
          dropLng: _dropLng!,
        );
    if (!mounted) return;
    setState(() {
      _estimating = false;
      _error = err;
    });
  }

  String _fmtSlot(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${days[t.weekday - 1]} $h:$m';
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppColors.red, surface: Color(0xFF111111)),
        ),
        child: child!,
      ),
    );
    if (t == null || !mounted) return;
    setState(() =>
        _when = DateTime(now.year, now.month, now.day, t.hour, t.minute));
  }

  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final options = store.rideOptions;
    final distance = store.rideDistanceKm;
    final active = store.activeRide;
    final past = store.pastRides;

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        backgroundColor: AppColors.page,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('CUNNECT RIDE',
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            _heroCard(active),
            const SizedBox(height: 12),
            if (active != null) ...[
              _activeBanner(context, active),
              const SizedBox(height: 12),
            ],
            _routeCard(),
            const SizedBox(height: 12),
            if (_recent.isNotEmpty) ...[
              _recentRow(),
              const SizedBox(height: 12),
            ],
            if (_pickupLat != null && _dropLat != null && distance > 0)
              _tripMeta(distance),
            const SizedBox(height: 16),
            _sectionLabel('CHOOSE YOUR RIDE'),
            const SizedBox(height: 10),
            if (_estimating)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.red, strokeWidth: 2)),
              )
            else if (options.isEmpty)
              _emptyHint()
            else
              ...options.map((o) => _vehicleCard(context, o as Map)),
            const SizedBox(height: 18),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFFF8791), fontSize: 12.5)),
              ),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _busy
                    ? null
                    : () {
                        // ⭐ v73: no time slot, no booking.
                        if (_when == null) {
                          showCunnectToast(context,
                              'Choose the time slot for this ride first.');
                          _pickTime();
                          return;
                        }
                        _openBookingSheet();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('BOOK RIDE',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.3)),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You pay only after a rider accepts. Full payment, or '
              '50-50 with a small 5% split fee.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFF6A6A6A), fontSize: 11.5, height: 1.5),
            ),
            if (past.isNotEmpty) ...[
              const SizedBox(height: 26),
              Row(
                children: [
                  _sectionLabel('YOUR RIDES'),
                  const Spacer(),
                  Text(
                      '${past.length} rides · ₹${_totalSpent(past).toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: Color(0xFF6A6A6A), fontSize: 11)),
                ],
              ),
              const SizedBox(height: 10),
              ...past
                  .take(8)
                  .map((r) => _historyRow(Map<String, dynamic>.from(r as Map))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _activeBanner(BuildContext context, Map<String, dynamic> ride) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              RideTrackingScreen(rideCode: '${ride['ride_code']}'))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.red.withOpacity(.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_taxi_rounded,
                color: AppColors.red, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('You have a ride in progress',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${ride['vehicle_label']} · ${ride['status']}',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF8A8A8A)),
          ],
        ),
      ),
    );
  }

  // ⭐ v72: "Use my location" / swap / stats helpers ------------------

  Future<void> _useMyLocation() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) {
        if (mounted) {
          showCunnectToast(context, 'Turn on location services first.',
              error: true);
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          showCunnectToast(context, 'Location permission is needed.',
              error: true);
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final lat = pos.latitude;
      final lng = pos.longitude;
      final name = await reverseGeocodeName(lat, lng);
      if (!mounted) return;
      setState(() {
        _pickupLat = lat;
        _pickupLng = lng;
        _pickup = name.isNotEmpty
            ? name
            : 'My location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
        _error = null;
      });
      await _estimate();
    } catch (_) {
      if (mounted) {
        showCunnectToast(context, 'Could not read your location.', error: true);
      }
    }
  }

  void _swapPoints() {
    setState(() {
      final t = _pickup;
      _pickup = _drop;
      _drop = t;
      final la = _pickupLat;
      _pickupLat = _dropLat;
      _dropLat = la;
      final lo = _pickupLng;
      _pickupLng = _dropLng;
      _dropLng = lo;
    });
    _estimate();
  }

  String _bestValueKey() {
    final options = context.read<AppStore>().rideOptions;
    if (options.isEmpty) return '';
    var best = '';
    num? low;
    for (final o in options) {
      final f = (o['fare'] as num?) ?? 0;
      if (low == null || f < low) {
        low = f;
        best = '${o['key']}';
      }
    }
    return best;
  }

  double _totalSpent(List<dynamic> past) {
    var sum = 0.0;
    for (final r in past) {
      final m = r as Map? ?? {};
      sum += ((m['fare'] as num?)?.toDouble() ?? 0);
    }
    return sum;
  }

  Widget _miniAction(IconData icon, String label, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: const Color(0xFF9E9E9E)),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF9E9E9E),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  // ⭐ v72: the Ride hero — live tracking when a ride is running, a map
  // preview of the chosen route, or the "why ride with us" card.
  Widget _heroCard(Map<String, dynamic>? active) {
    if (active != null) {
      final status = '${active['status']}';
      final liveStatus = status == 'paid' ||
          status == 'arrived' ||
          status == 'ongoing';
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [
            Color(0xFF2A1016),
            Color(0xFF141414),
          ]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x4DF10B1D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x26F10B1D),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.gps_fixed_rounded,
                    color: AppColors.red, size: 18),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your ride is running',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        liveStatus
                            ? 'The rider is sharing live location'
                            : 'Waiting for the rider to accept',
                        style: const TextStyle(
                            color: Color(0xFF9E9E9E), fontSize: 11.5)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 13),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => RideTrackingScreen(
                              rideCode: '${active['ride_code']}'))),
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: const Text('TRIP DETAILS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0x33FFFFFF)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => RideLiveMapScreen(
                              rideCode: '${active['ride_code']}'))),
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: const Text('LIVE MAP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ]),
          ],
        ),
      );
    }

    if (_pickupLat != null && _dropLat != null) {
      return Container(
        height: 132,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(
                  (_pickupLat! + _dropLat!) / 2, (_pickupLng! + _dropLng!) / 2),
              initialZoom: 13.5,
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
                  points: [
                    LatLng(_pickupLat!, _pickupLng!),
                    LatLng(_dropLat!, _dropLng!),
                  ],
                  color: AppColors.red.withOpacity(.85),
                  strokeWidth: 4,
                ),
              ]),
              MarkerLayer(markers: [
                Marker(
                  point: LatLng(_pickupLat!, _pickupLng!),
                  width: 30,
                  height: 30,
                  child: const Icon(Icons.trip_origin_rounded,
                      color: Color(0xFF98E6B0), size: 22),
                ),
                Marker(
                  point: LatLng(_dropLat!, _dropLng!),
                  width: 30,
                  height: 30,
                  child: const Icon(Icons.location_on_rounded,
                      color: AppColors.red, size: 26),
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
              ),
              child: const Text('Route preview',
                  style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [
          Color(0xFF1C1013),
          Color(0xFF121212),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x26F10B1D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ride across campus, the easy way',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
              'Pick your points, choose a vehicle and pay only after a '
              'rider accepts.',
              style: TextStyle(
                  color: Color(0xFF9E9E9E), fontSize: 11.5, height: 1.5)),
          const SizedBox(height: 12),
          Row(children: const [
            _HeroChip(Icons.gps_fixed_rounded, 'Live tracking'),
            SizedBox(width: 8),
            _HeroChip(Icons.verified_user_rounded, 'Verified partners'),
          ]),
        ],
      ),
    );
  }

  Widget _routeCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        children: [
          _row('PICKUP', _pickup.isEmpty ? 'Choose pickup point' : _pickup,
              Icons.my_location_rounded, const Color(0xFF98E6B0), true),
          // ⭐ v72: swap + "use my location" right where you need them
          Row(children: [
            const SizedBox(width: 42),
            _miniAction(Icons.swap_vert_rounded, 'Swap', _swapPoints),
            const SizedBox(width: 8),
            _miniAction(Icons.gps_fixed_rounded, 'Use my location',
                _useMyLocation),
          ]),
          const Divider(color: Color(0xFF202020), height: 1),
          _row('DROP', _drop.isEmpty ? 'Choose drop point' : _drop,
              Icons.location_on_rounded, AppColors.red, false),
          const Divider(color: Color(0xFF202020), height: 1),
          _timeRow(),
        ],
      ),
    );
  }

  Widget _recentRow() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _recent.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final r = _recent[i];
          return InkWell(
            onTap: () {
              setState(() {
                if (_pickup.isEmpty) {
                  _pickup = '${r['text']}';
                  _pickupLat = (r['lat'] as num).toDouble();
                  _pickupLng = (r['lng'] as num).toDouble();
                } else {
                  _drop = '${r['text']}';
                  _dropLat = (r['lat'] as num).toDouble();
                  _dropLng = (r['lng'] as num).toDouble();
                }
              });
              _estimate();
            },
            borderRadius: BorderRadius.circular(9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFF262626)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history_rounded,
                      size: 13, color: Color(0xFF8A8A8A)),
                  const SizedBox(width: 6),
                  Text('${r['text']}',
                      style: const TextStyle(
                          color: Color(0xFFB7B7BC), fontSize: 11.5)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tripMeta(double km) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Row(
        children: [
          const Icon(Icons.straighten_rounded,
              size: 15, color: Color(0xFF9E9E9E)),
          const SizedBox(width: 8),
          Text('${km.toStringAsFixed(2)} km',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 14),
          const Spacer(),
          const Icon(Icons.route_outlined,
              size: 15, color: Color(0xFF98E6B0)),
        ],
      ),
    );
  }

  Widget _row(String label, String value, IconData icon, Color color,
      bool isPickup) {
    return InkWell(
      onTap: () => _pick(isPickup),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(.13),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          letterSpacing: 1.6,
                          color: Color(0xFF7A7A7A),
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: value.contains('Choose')
                              ? const Color(0xFF6E6E6E)
                              : Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.map_rounded,
                size: 18, color: Color(0xFF8A8A8A)),
          ],
        ),
      ),
    );
  }

  Widget _timeRow() {
    return InkWell(
      onTap: _pickTime,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFD34D).withOpacity(.13),
              ),
              child: const Icon(Icons.schedule_rounded,
                  color: Color(0xFFFFD34D), size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TIME',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          letterSpacing: 1.6,
                          color: Color(0xFF7A7A7A),
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    _when == null
                        ? 'Choose the time slot (required)'
                        : 'Today at ${_when!.hour.toString().padLeft(2, '0')}:${_when!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        color: _when == null
                            ? const Color(0xFFFFD34D)
                            : Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: Color(0xFF8A8A8A)),
          ],
        ),
      ),
    );
  }

  Widget _vehicleCard(BuildContext context, Map o) {
    final key = '${o['key']}';
    final selected = _vehicle == key;
    final fare = (o['fare'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => setState(() => _vehicle = key),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(colors: [
                    Color(0xFF24121A),
                    Color(0xFF141414),
                  ])
                : null,
            color: selected ? null : const Color(0xFF111111),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? AppColors.red : const Color(0xFF242424),
                width: selected ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${o['icon']}',
                    style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${o['label']}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF242424),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('${o['seats']} seats',
                              style: const TextStyle(
                                  color: Color(0xFF9E9E9E), fontSize: 9.5)),
                        ),
                        // ⭐ v72: cheapest ride gets a value badge
                        if (_bestValueKey() == key) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0x26F10B1D),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                  color: const Color(0x4DF10B1D)),
                            ),
                            child: const Text('BEST VALUE',
                                style: TextStyle(
                                    color: Color(0xFFFF9CA5),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                        o['available'] == false
                            ? 'Currently unavailable — book for another time'
                            : 'AC',
                        style: TextStyle(
                            color: o['available'] == false
                                ? const Color(0xFFFFD34D)
                                : const Color(0xFF8A8A8A),
                            fontSize: 11.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${fare.toStringAsFixed(0)}',
                      style: TextStyle(
                          color: o['available'] == false
                              ? const Color(0xFF6A6A6A)
                              : Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const Text('approx',
                      style:
                          TextStyle(color: Color(0xFF6A6A6A), fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyHint() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: const Column(
        children: [
          Icon(Icons.route_rounded, color: Color(0xFF4A4A4A), size: 30),
          SizedBox(height: 12),
          Text(
            'Pick your pickup and drop points —\nfares for every ride appear '
            'here.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Color(0xFF8A8A8A), fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _historyRow(Map<String, dynamic> r) {
    final done = '${r['status']}' == 'completed';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF202020)),
      ),
      child: Row(
        children: [
          Text('${r['vehicle_icon']}', style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['pickup_text']} → ${r['drop_text']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(
                    '${r['distance_km']} km · ${done ? 'completed' : '${r['status']}'}',
                    style: const TextStyle(
                        color: Color(0xFF7A7A7A), fontSize: 10.5)),
              ],
            ),
          ),
          Text('₹${((r['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
              style: TextStyle(
                  color: done
                      ? const Color(0xFF98E6B0)
                      : const Color(0xFF9E9E9E),
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          letterSpacing: 2,
          color: Color(0xFF7A7A7A),
          fontWeight: FontWeight.w700));

  // --------------------- Uber-style booking sheet ---------------------

  void _openBookingSheet() {
    if (_pickupLat == null || _dropLat == null) {
      setState(() => _error = 'Pick the pickup and drop points on the map.');
      return;
    }
    final store = context.read<AppStore>();
    final km = store.rideDistanceKm;
    final opts = store.rideOptions;
    Map? chosen;
    for (final o in opts) {
      if ('${(o as Map)['key']}' == _vehicle) chosen = o;
    }
    final fare = ((chosen?['fare'] as num?)?.toDouble() ?? 0);
    if (_phone.text.trim().isEmpty) _phone.text = store.customerPhone;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: EdgeInsets.fromLTRB(
              18, 14, 18, 18 + MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3A),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('CONFIRM YOUR RIDE',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                        letterSpacing: 2,
                        color: Color(0xFF7A7A7A),
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                // route
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const Icon(Icons.my_location_rounded,
                            size: 16, color: Color(0xFF98E6B0)),
                        Container(
                          width: 1,
                          height: 22,
                          color: const Color(0xFF303030),
                        ),
                        const Icon(Icons.location_on_rounded,
                            size: 16, color: AppColors.red),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_pickup,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13.5)),
                          const SizedBox(height: 14),
                          Text(_drop,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13.5)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // vehicle + fare
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFF262626)),
                  ),
                  child: Row(
                    children: [
                      Text('${chosen?['icon'] ?? '🚗'}',
                          style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${chosen?['label'] ?? 'Ride'}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(
                                '${km.toStringAsFixed(2)} km · '
                                '${_when == null ? 'Pick a time slot' : _fmtSlot(_when!)}',
                                style: const TextStyle(
                                    color: Color(0xFF9E9E9E), fontSize: 11)),
                          ],
                        ),
                      ),
                      Text('₹${fare.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // ⭐ v73: your number comes from your CUnnect profile —
                // it cannot be typed or changed here.
                _sheetLabel('YOUR NUMBER (THE RIDER WILL CALL THIS)'),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0xFF262626)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.verified_user_rounded,
                        size: 15, color: Color(0xFF98E6B0)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          _phone.text.trim().isEmpty
                              ? 'Not on your profile'
                              : _phone.text.trim(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ),
                    const Text('from profile',
                        style:
                            TextStyle(color: Color(0xFF6A6A6A), fontSize: 10.5)),
                  ]),
                ),
                const SizedBox(height: 14),
                // ⭐ v73: booking for someone else?
                Row(
                  children: [
                    const Icon(Icons.person_add_alt_rounded,
                        size: 15, color: Color(0xFF9E9E9E)),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text('Booking for someone else?',
                          style: TextStyle(
                              color: Color(0xFFEDEDF0),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ),
                    Switch(
                      value: _forOther,
                      activeColor: AppColors.red,
                      onChanged: (v) => setSheet(() {
                        _forOther = v;
                        setState(() => _forOther = v);
                      }),
                    ),
                  ],
                ),
                if (_forOther) ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: _otherName,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: _sheetDec('Their name (optional)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _otherPhone,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: _sheetDec('Their contact number'),
                  ),
                ],
                const SizedBox(height: 14),
                _sheetLabel('NOTE FOR THE RIDER (OPTIONAL)'),
                const SizedBox(height: 6),
                TextField(
                  controller: _notes,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: _sheetDec('e.g. I am at the main gate'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_busy) return;
                      // ⭐ v73: the time slot is COMPULSORY — even "right
                      // now" has to be chosen by hand.
                      if (_when == null) {
                        showCunnectToast(context,
                            'Choose the time slot for this ride first.');
                        return;
                      }
                      if (_forOther &&
                          _otherPhone.text.trim().replaceAll(RegExp(r'\D'), '').length <
                              8) {
                        showCunnectToast(
                            context, 'Enter the contact number to call.');
                        return;
                      }
                      final phone = _phone.text.trim();
                      Navigator.pop(sheetCtx);
                      setState(() => _busy = true);
                      final res = await store.rideBook(
                        vehicleType: _vehicle,
                        pickupText: _pickup,
                        pickupLat: _pickupLat!,
                        pickupLng: _pickupLng!,
                        dropText: _drop,
                        dropLat: _dropLat!,
                        dropLng: _dropLng!,
                        phone: phone,
                        scheduledAt: _when!.toIso8601String(),
                        notes: _notes.text.trim(),
                        forOther: _forOther,
                        otherName: _otherName.text.trim(),
                        otherPhone: _otherPhone.text.trim(),
                      );
                      if (!mounted) return;
                      setState(() => _busy = false);
                      if (res['ok'] != true) {
                        setState(() => _error = '${res['error']}');
                        return;
                      }
                      final ride =
                          Map<String, dynamic>.from(res['ride'] as Map? ?? {});
                      Navigator.of(context).pushReplacement(MaterialPageRoute(
                          builder: (_) => RideTrackingScreen(
                              rideCode: '${ride['ride_code']}')));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('CONFIRM BOOKING',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text('No payment now — pay after a rider accepts',
                      style: TextStyle(
                          color: Color(0xFF6A6A6A), fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _sheetDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6E6E6E), fontSize: 12.5),
        filled: true,
        fillColor: const Color(0xFF0D0D0D),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xFF303030)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.red),
        ),
      );

  Widget _sheetLabel(String t) => Text(t,
      style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 9,
          letterSpacing: 1.6,
          color: Color(0xFF7A7A7A),
          fontWeight: FontWeight.w700));


}

/// Small pill used inside the Ride hero card.
class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFFFF9CA5)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Color(0xFFD8D8DC), fontSize: 11)),
        ],
      ),
    );
  }
}
