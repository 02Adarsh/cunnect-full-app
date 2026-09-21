import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../data/up_places.dart';
import '../../services/app_store.dart';
import '../../services/local_store.dart';
import '../../services/offline_tiles.dart';
import '../../services/open_url_stub.dart'
    if (dart.library.html) '../../services/open_url_web.dart'
    if (dart.library.io) '../../services/open_url_mobile.dart';
import '../../services/ride_events.dart';
import '../../services/app_portal.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart' show showCunnectToast;
import '../../widgets/ride_ui.dart';
import 'ride_history_screen.dart';
import 'ride_live_map_screen.dart';
import 'ride_map_picker_screen.dart';
import 'ride_tracking_screen.dart';

/// ⭐ v74: CUnnect RIDE — a complete, premium ride booking experience.
///
///  * a live map that shows the route you are building
///  * a sliding "Choose your ride" sheet (Uber-style) with every vehicle,
///    the compulsory time slot, split-the-fare with friends, notes and
///    the read-only profile number
///  * one-tap saved & recent places, safety tools and ride statistics
///
/// Maps are OpenStreetMap — no Google key, no billing, works offline.
class RideHomeScreen extends StatefulWidget {
  const RideHomeScreen({super.key});

  @override
  State<RideHomeScreen> createState() => _RideHomeScreenState();
}

class _RideHomeScreenState extends State<RideHomeScreen>
    with WidgetsBindingObserver {
  final _mapController = MapController();
  final _notes = TextEditingController();
  final _otherName = TextEditingController();
  final _otherPhone = TextEditingController();

  String _pickup = '';
  double? _pickupLat, _pickupLng;
  String _drop = '';
  double? _dropLat, _dropLng;

  DateTime? _when;
  String _vehicle = 'mini';
  bool _forOther = false;
  bool _splitWithFriends = false;

  bool _busy = false;
  bool _locating = false;
  bool _estimating = false;
  String? _error;

  List<Map<String, dynamic>> _saved = [];
  List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _pax = [];
  List<Map<String, dynamic>> _contacts = [];

  static const _kSaved = 'ride_saved_places';
  static const _kRecent = 'ride_recent_places';
  static const _kContacts = 'ride_sos_contacts';

  @override
  void initState() {
    super.initState();
    // ⭐ v75: the student Ride screen — only student ride events belong
    // here (the rider gets his own in the ride partner portal).
    ActivePortal.set(AppPortal.student);
    WidgetsBinding.instance.addObserver(this);
    _loadLocal();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<AppStore>();
      await Future.wait([
        store.loadRides(),
        store.loadRideStats(),
      ]);
      if (!mounted) return;
      await RideEvents.consumePending(context);
      _followActive();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notes.dispose();
    _otherName.dispose();
    _otherPhone.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppStore>().loadRides();
      RideEvents.consumePending(context);
    }
  }

  // ------------------------------------------------------------ local

  void _loadLocal() {
    _saved = _readList(_kSaved);
    if (_saved.isEmpty) {
      // seed the three places students use the most
      _saved = [
        {'name': 'Chandigarh University UP', 'lat': kCampusLat, 'lng': kCampusLng},
        {'name': 'Nawabganj', 'lat': 26.613966, 'lng': 80.658155},
        {'name': 'Unnao Junction', 'lat': 26.5492382, 'lng': 80.4874371},
      ];
      _writeList(_kSaved, _saved);
    }
    _recent = _readList(_kRecent);
    _contacts = _readList(_kContacts);
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> _readList(String key) {
    try {
      final raw = LocalStore.get(key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  void _writeList(String key, List<Map<String, dynamic>> list) {
    LocalStore.set(key, jsonEncode(list));
  }

  Future<void> _rememberRecent(String name, double lat, double lng) async {
    _recent.removeWhere((p) => '${p['name']}' == name);
    _recent.insert(0, {'name': name, 'lat': lat, 'lng': lng});
    if (_recent.length > 5) _recent = _recent.take(5).toList();
    _writeList(_kRecent, _recent);
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final active = store.activeRide;
    return Scaffold(
      backgroundColor: RideColors.bg,
      body: Stack(
        children: [
          _mapHero(store),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _topBar(store),
          ),
          DraggableScrollableSheet(
            initialChildSize: active != null ? 0.40 : 0.52,
            minChildSize: 0.22,
            maxChildSize: 0.95,
            snap: true,
            snapSizes: const [0.30, 0.52, 0.90],
            builder: (context, controller) => Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0C0C0C),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black87,
                      blurRadius: 30,
                      offset: Offset(0, -8)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
                  children: [
                    Center(child: RideGrab()),
                    const SizedBox(height: 14),
                    if (active != null) ...[
                      _activeCard(store, active),
                      const SizedBox(height: 14),
                    ],
                    _routeCard(),
                    const SizedBox(height: 14),
                    _placesRow(),
                    const SizedBox(height: 16),
                    if (_pickupLat != null && _dropLat != null) ...[
                      _chooseRide(store),
                    ] else ...[
                      _statsStrip(store),
                      const SizedBox(height: 14),
                      _safetyCard(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- top bar

  Widget _topBar(AppStore store) {
    final active = store.activeRide;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(.85),
            Colors.black.withOpacity(.35),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 26),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
                color: Colors.white,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 2),
              const Text('Ride',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: 'Ride history',
                icon: const Icon(Icons.history_rounded, size: 21),
                color: Colors.white,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const RideHistoryScreen())),
              ),
              if (active != null)
                IconButton(
                  tooltip: 'Live map',
                  icon: const Icon(Icons.map_rounded, size: 21),
                  color: RideColors.mint,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RideLiveMapScreen(
                          rideCode: '${active['ride_code']}'))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ map

  Widget _mapHero(AppStore store) {
    final active = store.activeRide;
    final aLat = (active?['pickup_lat'] as num?)?.toDouble();
    final aLng = (active?['pickup_lng'] as num?)?.toDouble();
    final hasRoute = _pickupLat != null && _dropLat != null;
    final p = (aLat != null && aLng != null)
        ? LatLng(aLat, aLng)
        : (hasRoute
            ? LatLng((_pickupLat! + _dropLat!) / 2, (_pickupLng! + _dropLng!) / 2)
            : (_pickupLat != null
                ? LatLng(_pickupLat!, _pickupLng!)
                : LatLng(kCampusLat, kCampusLng)));
    return Positioned.fill(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: p,
          initialZoom: hasRoute ? 13.4 : 15.2,
          onTap: (_, __) => _openPicker(isPickup: _pickupLat == null),
        ),
        children: [
          TileLayer(
            tileProvider: CachedTileProvider(),
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.cunnect.cunnect_food',
            maxZoom: 19,
          ),
          if (hasRoute)
            PolylineLayer(polylines: [
              Polyline(
                points: [
                  LatLng(_pickupLat!, _pickupLng!),
                  LatLng(_dropLat!, _dropLng!),
                ],
                color: AppColors.red.withOpacity(.92),
                strokeWidth: 4.5,
              ),
            ]),
          MarkerLayer(markers: [
            Marker(
              point: LatLng(kCampusLat, kCampusLng),
              width: 118,
              height: 30,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xE6141414),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.red),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.school_rounded,
                        size: 12, color: Color(0xFFFF9CA5)),
                    SizedBox(width: 5),
                    Flexible(
                      child: Text('Chandigarh University UP',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
            if (_pickupLat != null)
              Marker(
                point: LatLng(_pickupLat!, _pickupLng!),
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                    border: Border.all(color: RideColors.mint, width: 2.5),
                  ),
                  child: const Icon(Icons.my_location_rounded,
                      size: 19, color: RideColors.mint),
                ),
              ),
            if (_dropLat != null)
              Marker(
                point: LatLng(_dropLat!, _dropLng!),
                width: 40,
                height: 40,
                child: const Icon(Icons.location_pin,
                    color: AppColors.red, size: 40),
              ),
          ]),
        ],
      ),
    );
  }

  // ---------------------------------------------------- active ride

  Widget _activeCard(AppStore store, Map<String, dynamic> ride) {
    final status = '${ride['status']}';
    return RideGlass(
      radius: 20,
      padding: const EdgeInsets.all(15),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.red.withOpacity(.16),
          const Color(0xFF131313).withOpacity(.9),
        ],
      ),
      border: Border.all(color: AppColors.red.withOpacity(.42)),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RideTrackingScreen(rideCode: '${ride['ride_code']}'))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: RideColors.mint, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text('RIDE IN PROGRESS',
                  style: TextStyle(
                      color: RideColors.mint,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Color(0xFF8A8A8A)),
            ],
          ),
          const SizedBox(height: 10),
          Text(_statusLine(status),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('${ride['pickup_text']} → ${ride['drop_text']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFB0B0B5), fontSize: 12)),
          const SizedBox(height: 12),
          RideButton(
            label: 'OPEN MY RIDE',
            height: 44,
            icon: Icons.directions_car_rounded,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    RideTrackingScreen(rideCode: '${ride['ride_code']}'))),
          ),
        ],
      ),
    );
  }

  String _statusLine(String s) => switch (s) {
        'requested' => 'Finding your rider',
        'accepted' => 'Accepted — pay to confirm',
        'paid' => 'Rider on the way',
        'arrived' => 'Rider has arrived',
        'ongoing' => 'Ride in progress',
        'completed' => 'Ride completed',
        _ => 'Ride $s',
      };

  // ------------------------------------------------------- route card

  Widget _routeCard() {
    return RideGlass(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        children: [
          _pointRow(
            icon: Icons.trip_origin_rounded,
            color: RideColors.mint,
            hint: 'Pickup location',
            text: _pickup,
            onTap: () => _openPicker(isPickup: true),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _locating ? null : () => _useMyLocation(forPickup: true),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: RideColors.mint.withOpacity(.12),
                      borderRadius: BorderRadius.circular(9),
                      border:
                          Border.all(color: RideColors.mint.withOpacity(.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _locating
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                    color: RideColors.mint))
                            : const Icon(Icons.gps_fixed_rounded,
                                size: 13, color: RideColors.mint),
                        const SizedBox(width: 6),
                        const Text('Current',
                            style: TextStyle(
                                color: RideColors.mint,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 21),
            child: Row(
              children: List.generate(
                  9,
                  (i) => Expanded(
                        child: Container(
                          height: 1.5,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          color: i.isEven
                              ? const Color(0xFF3A3A3A)
                              : Colors.transparent,
                        ),
                      )),
            ),
          ),
          _pointRow(
            icon: Icons.location_on_rounded,
            color: AppColors.red,
            hint: 'Where to?',
            text: _drop,
            onTap: () => _openPicker(isPickup: false),
            trailing: _drop.isNotEmpty
                ? GestureDetector(
                    onTap: _saveCurrentDrop,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: RideColors.line),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bookmark_add_rounded,
                              size: 13, color: Color(0xFF9E9E9E)),
                          SizedBox(width: 5),
                          Text('Save',
                              style: TextStyle(
                                  color: Color(0xFF9E9E9E),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _pointRow({
    required IconData icon,
    required Color color,
    required String hint,
    required String text,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text.isEmpty ? hint : text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: text.isEmpty ? const Color(0xFF6A6A6A) : Colors.white,
                    fontSize: 13.5,
                    fontWeight:
                        text.isEmpty ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------ saved places

  Widget _placesRow() {
    final chips = <Widget>[];
    for (final p in _saved.take(6)) {
      chips.add(_placeChip('${p['name']}', Icons.bookmark_rounded,
          RideColors.mint, () => _setPoint(p, isPickup: false)));
    }
    for (final p in _recent.take(4)) {
      chips.add(_placeChip('${p['name']}', Icons.schedule_rounded,
          const Color(0xFF9E9E9E), () => _setPoint(p, isPickup: false)));
    }
    chips.add(_placeChip('Add', Icons.add_rounded, AppColors.red, _addPlace));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: chips),
    );
  }

  Widget _placeChip(String label, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF131313),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: RideColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------ choose ride

  Widget _chooseRide(AppStore store) {
    final km = store.rideDistanceKm;
    final opts = store.rideOptions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RideLabel('CHOOSE YOUR RIDE'),
            const Spacer(),
            if (km > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: RideColors.line),
                ),
                child: Text('${km.toStringAsFixed(2)} km',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // ---- time slot (compulsory) ----
        _timeRow(),
        const SizedBox(height: 14),
        if (opts.isEmpty && _estimating)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(color: AppColors.red),
          ))
        else
          ...opts.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _vehicleCard(context, Map<dynamic, dynamic>.from(o as Map)),
              )),
        const SizedBox(height: 6),
        _extras(store),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!,
                style: const TextStyle(
                    color: Color(0xFFFF8791), fontSize: 12.5)),
          ),
        RideButton(
          label: _busy ? 'BOOKING…' : 'CONFIRM RIDE',
          busy: _busy,
          icon: Icons.check_rounded,
          onTap: _busy ? null : _book,
        ),
        const SizedBox(height: 9),
        const Center(
          child: Text('No payment now — pay after a rider accepts',
              style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 11)),
        ),
      ],
    );
  }

  Widget _timeRow() {
    final missing = _when == null;
    return GestureDetector(
      onTap: _pickSlot,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: missing ? RideColors.amber.withOpacity(.7) : RideColors.line,
              width: missing ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded,
                size: 18, color: missing ? RideColors.amber : Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_when == null ? 'Choose the time slot' : _fmtSlot(_when!),
                      style: TextStyle(
                          color: missing ? RideColors.amber : Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  if (missing)
                    const Text('Required — even "leave now" must be picked',
                        style:
                            TextStyle(color: Color(0xFF8A8A8A), fontSize: 10.5)),
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

  Widget _vehicleCard(BuildContext context, Map<dynamic, dynamic> o) {
    final key = '${o['key']}';
    final selected = _vehicle == key;
    final fare = (o['fare'] as num?)?.toDouble() ?? 0;
    final offline = o['available'] == false;
    final tint = rideVehicleTint(key);
    return GestureDetector(
      onTap: () => setState(() => _vehicle = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: selected ? tint.withOpacity(.10) : const Color(0xFF101010),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? tint.withOpacity(.65) : RideColors.line,
              width: selected ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withOpacity(.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tint.withOpacity(.25)),
              ),
              child: Text('${o['icon'] ?? '🚗'}',
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
                      if ('${o['seats'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(width: 7),
                        const Icon(Icons.person_rounded,
                            size: 12, color: Color(0xFF8A8A8A)),
                        Text('${o['seats']}',
                            style: const TextStyle(
                                color: Color(0xFF8A8A8A), fontSize: 11.5)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                      offline
                          ? 'Currently unavailable — book for another time'
                          : 'AC · ${o['label']}',
                      style: TextStyle(
                          color: offline
                              ? RideColors.amber
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
                        color: offline ? const Color(0xFF6A6A6A) : Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                if (selected)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('SELECTED',
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- extras

  Widget _extras(AppStore store) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RideLabel('TRIP DETAILS'),
        const SizedBox(height: 10),
        // read-only number
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: RideColors.line),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  size: 15, color: RideColors.mint),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your number',
                        style: TextStyle(
                            color: Color(0xFF7A7A7A), fontSize: 10.5)),
                    const SizedBox(height: 2),
                    Text(
                        store.customerPhone.isEmpty
                            ? 'Not on your profile'
                            : store.customerPhone,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const Text('from profile',
                  style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 10.5)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // booking for someone else
        GestureDetector(
          onTap: () => setState(() => _forOther = !_forOther),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: RideColors.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_add_alt_rounded,
                    size: 16, color: Color(0xFF9E9E9E)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Booking for someone else?',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: _forOther,
                  activeColor: AppColors.red,
                  onChanged: (v) => setState(() => _forOther = v),
                ),
              ],
            ),
          ),
        ),
        if (_forOther) ...[
          const SizedBox(height: 9),
          TextField(
            controller: _otherName,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _sheetDec('Their name (optional)'),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: _otherPhone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _sheetDec('Their contact number'),
          ),
        ],
        const SizedBox(height: 10),
        // split the fare with friends
        GestureDetector(
          onTap: () => setState(() => _splitWithFriends = !_splitWithFriends),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: RideColors.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.groups_rounded,
                    size: 16, color: RideColors.violet),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Split the fare with friends',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: _splitWithFriends,
                  activeColor: RideColors.violet,
                  onChanged: (v) => setState(() => _splitWithFriends = v),
                ),
              ],
            ),
          ),
        ),
        if (_splitWithFriends) ...[
          const SizedBox(height: 9),
          ..._pax.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: RideColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${p['name']}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5)),
                  ),
                  Text('₹${(p['amount'] as num).toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: RideColors.violet,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _pax.removeAt(i)),
                    child: const Icon(Icons.close_rounded,
                        size: 16, color: Color(0xFF8A8A8A)),
                  ),
                ],
              ),
            );
          }),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _addPax,
              icon: const Icon(Icons.person_add_rounded, size: 16),
              label: const Text('ADD A FRIEND',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(
                foregroundColor: RideColors.violet,
                side: BorderSide(color: RideColors.violet.withOpacity(.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _notes,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: _sheetDec('Note for the rider (optional)'),
        ),
      ],
    );
  }

  // --------------------------------------------------------- stats

  Widget _statsStrip(AppStore store) {
    final s = store.rideStudentStats;
    final rides = '${s['rides'] ?? 0}';
    final km = ((s['km'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
    final spent = ((s['spent'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RideLabel('YOUR RIDING'),
        const SizedBox(height: 10),
        RideGlass(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            children: [
              RideStat(value: rides, label: 'RIDES'),
              Container(width: 1, height: 32, color: RideColors.line),
              RideStat(value: km, label: 'KILOMETRES'),
              Container(width: 1, height: 32, color: RideColors.line),
              RideStat(value: '₹$spent', label: 'SPENT', color: RideColors.mint),
            ],
          ),
        ),
        const SizedBox(height: 12),
        RideGlass(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const RideHistoryScreen())),
          child: RideTile(
            icon: Icons.history_rounded,
            tint: Colors.white,
            title: 'Ride history',
            subtitle: 'Every ride, with its receipt',
            trailing: const Icon(Icons.chevron_right_rounded,
                size: 18, color: Color(0xFF8A8A8A)),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- safety

  Widget _safetyCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RideLabel('SAFETY'),
        const SizedBox(height: 10),
        RideGlass(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            children: [
              RideTile(
                icon: Icons.shield_rounded,
                tint: RideColors.mint,
                title: 'Emergency contacts',
                subtitle: _contacts.isEmpty
                    ? 'Add the people to call in an emergency'
                    : _contacts.map((c) => '${c['name']}').join(', '),
                trailing: const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Color(0xFF8A8A8A)),
                onTap: _manageContacts,
              ),
              RideTile(
                icon: Icons.share_location_rounded,
                tint: RideColors.sky,
                title: 'Share my trip',
                subtitle: 'Send your live route to a friend or to family',
                trailing: const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Color(0xFF8A8A8A)),
                onTap: _shareTrip,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- actions

  Future<void> _openPicker({required bool isPickup}) async {
    final res = await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RideMapPickerScreen(
              title: isPickup ? 'Pickup location' : 'Drop location',
              hint: isPickup ? 'Where should the rider come?' : 'Where to?',
              initial: isPickup
                  ? (_pickupLat != null
                      ? LatLng(_pickupLat!, _pickupLng!)
                      : null)
                  : (_dropLat != null ? LatLng(_dropLat!, _dropLng!) : null),
            )));
    if (res is Map && mounted) {
      final lat = (res['lat'] as num).toDouble();
      final lng = (res['lng'] as num).toDouble();
      setState(() {
        _error = null;
        if (isPickup) {
          _pickup = '${res['text']}';
          _pickupLat = lat;
          _pickupLng = lng;
        } else {
          _drop = '${res['text']}';
          _dropLat = lat;
          _dropLng = lng;
        }
      });
      await _rememberRecent('${res['text']}', lat, lng);
      _estimate();
    }
  }

  void _setPoint(Map<String, dynamic> p, {required bool isPickup}) {
    final lat = (p['lat'] as num).toDouble();
    final lng = (p['lng'] as num).toDouble();
    setState(() {
      if (isPickup) {
        _pickup = '${p['name']}';
        _pickupLat = lat;
        _pickupLng = lng;
      } else {
        _drop = '${p['name']}';
        _dropLat = lat;
        _dropLng = lng;
      }
      _error = null;
    });
    _mapController.move(LatLng(lat, lng), 15);
    _estimate();
  }

  Future<void> _addPlace() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Save a place',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. Hostel, Main Gate, Library',
            hintStyle: TextStyle(color: Color(0xFF6A6A6A)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF8A8A8A)))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pick on map',
                  style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RideMapPickerScreen(
              title: 'Save ${nameCtrl.text.trim()}',
              hint: 'Pin the exact spot',
            )));
    if (res is Map && mounted) {
      _saved.add({
        'name': nameCtrl.text.trim().isEmpty
            ? '${res['text']}'
            : nameCtrl.text.trim(),
        'lat': (res['lat'] as num).toDouble(),
        'lng': (res['lng'] as num).toDouble(),
      });
      _writeList(_kSaved, _saved);
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveCurrentDrop() async {
    if (_dropLat == null) return;
    _saved.add({'name': _drop, 'lat': _dropLat, 'lng': _dropLng});
    _writeList(_kSaved, _saved);
    if (mounted) {
      setState(() {});
      showCunnectToast(context, '$_drop saved');
    }
  }

  Future<void> _useMyLocation({required bool forPickup}) async {
    if (!mounted) return;
    setState(() => _locating = true);
    try {
      final on = await Geolocator.isLocationServiceEnabled();
      if (!on) {
        _toast('Turn on location services.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Location permission is needed.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation);
      final name = await reverseGeocodeName(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        final text = name.isNotEmpty
            ? name
            : 'My location (${pos.latitude.toStringAsFixed(5)}, '
                '${pos.longitude.toStringAsFixed(5)})';
        if (forPickup) {
          _pickup = text;
          _pickupLat = pos.latitude;
          _pickupLng = pos.longitude;
        } else {
          _drop = text;
          _dropLat = pos.latitude;
          _dropLng = pos.longitude;
        }
        _error = null;
      });
      _mapController.move(LatLng(pos.latitude, pos.longitude), 17);
      _estimate();
    } catch (_) {
      _toast('Could not read your location.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickSlot() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: _when ?? now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.red),
        ),
        child: child!,
      ),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when ?? now),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.red),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _when = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      _error = null;
    });
    _estimate();
  }

  Future<void> _estimate() async {
    if (_pickupLat == null || _dropLat == null) return;
    if (!mounted) return;
    setState(() {
      _estimating = true;
      _error = null;
    });
    final store = context.read<AppStore>();
    final err = await store.rideEstimate(
      pickupLat: _pickupLat!,
      pickupLng: _pickupLng!,
      dropLat: _dropLat!,
      dropLng: _dropLng!,
      scheduledAt: _when?.toIso8601String() ?? '',
    );
    if (!mounted) return;
    setState(() {
      _estimating = false;
      if (err != null) _error = err;
    });
  }

  Future<void> _addPax() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Add a friend',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    hintText: 'Name',
                    hintStyle: TextStyle(color: Color(0xFF6A6A6A)))),
            TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    hintText: 'Their share (₹)',
                    hintStyle: TextStyle(color: Color(0xFF6A6A6A)))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF8A8A8A)))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add',
                  style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amount.text.trim()) ?? 0;
    if (name.text.trim().isEmpty || amt <= 0) {
      _toast('Enter a name and their share.');
      return;
    }
    setState(() => _pax.add({'name': name.text.trim(), 'amount': amt}));
  }

  Future<void> _book() async {
    if (_busy) return;
    if (_when == null) {
      setState(() => _error = 'Choose the time slot for this ride first.');
      await _pickSlot();
      return;
    }
    if (_forOther &&
        _otherPhone.text.trim().replaceAll(RegExp(r'\D'), '').length < 8) {
      setState(() => _error = 'Enter the contact number to call.');
      return;
    }
    final store = context.read<AppStore>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await store.rideBook(
      vehicleType: _vehicle,
      pickupText: _pickup,
      pickupLat: _pickupLat!,
      pickupLng: _pickupLng!,
      dropText: _drop,
      dropLat: _dropLat!,
      dropLng: _dropLng!,
      phone: store.customerPhone,
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
    final ride = Map<String, dynamic>.from(res['ride'] as Map? ?? {});
    final code = '${ride['ride_code']}';
    // ⭐ the fare split is stored on the ride once it exists
    for (final p in _pax) {
      await store.ridePaxAdd(code,
          name: '${p['name']}',
          phone: '',
          amount: (p['amount'] as num).toDouble());
    }
    if (!mounted) return;
    if ('${res['message'] ?? ''}'.isNotEmpty) {
      _toast('${res['message']}');
    }
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => RideTrackingScreen(rideCode: code)));
    return;
  }

  void _followActive() {
    final ride = context.read<AppStore>().activeRide;
    if (ride == null) return;
    final lat = (ride['pickup_lat'] as num?)?.toDouble();
    final lng = (ride['pickup_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      _mapController.move(LatLng(lat, lng), 15);
    }
  }

  Future<void> _shareTrip() async {
    final ride = context.read<AppStore>().activeRide;
    final when = _when == null ? '' : ' at ${_fmtSlot(_when!)}';
    final where = _pickup.isNotEmpty && _drop.isNotEmpty
        ? '$_pickup → $_drop'
        : (ride != null
            ? '${ride['pickup_text']} → ${ride['drop_text']}'
            : 'my CUnnect ride');
    final link = _pickupLat != null
        ? 'https://maps.google.com/?q=$_pickupLat,$_pickupLng'
        : 'https://cunnect.online';
    final text = 'I am taking a CUnnect ride$when — $where. Live: $link';
    await openExternalUrl(
        'https://wa.me/?text=${Uri.encodeComponent(text)}');
  }

  Future<void> _manageContacts() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: RideSheetShell(
          initial: 0.5,
          minHeight: 0.3,
          child: StatefulBuilder(builder: (ctx, setS) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text('Emergency contacts',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text('These stay on your phone only',
                      style: TextStyle(
                          color: Color(0xFF7A7A7A), fontSize: 11.5)),
                ),
                const SizedBox(height: 16),
                ..._contacts.asMap().entries.map((e) => RideTile(
                      icon: Icons.person_rounded,
                      tint: RideColors.mint,
                      title: '${e.value['name']}',
                      subtitle: '${e.value['phone']}',
                      trailing: GestureDetector(
                        onTap: () async {
                          _contacts.removeAt(e.key);
                          _writeList(_kContacts, _contacts);
                          setS(() {});
                          if (mounted) setState(() {});
                        },
                        child: const Icon(Icons.delete_outline_rounded,
                            size: 17, color: Color(0xFF8A8A8A)),
                      ),
                      onTap: () => openExternalUrl(
                          'tel:${e.value['phone']}'),
                    )),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _sheetDec('Name'),
                ),
                const SizedBox(height: 9),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _sheetDec('Phone number'),
                ),
                const SizedBox(height: 14),
                RideButton(
                  label: 'ADD CONTACT',
                  icon: Icons.add_rounded,
                  onTap: () async {
                    if (name.text.trim().isEmpty ||
                        phone.text.trim().length < 8) {
                      _toast('Enter a name and a phone number.');
                      return;
                    }
                    _contacts.add({
                      'name': name.text.trim(),
                      'phone': phone.text.trim(),
                    });
                    _writeList(_kContacts, _contacts);
                    name.clear();
                    phone.clear();
                    setS(() {});
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 10),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- helpers

  String _fmtSlot(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${days[t.weekday - 1]} $h:$m';
  }

  InputDecoration _sheetDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6A6A6A), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF0F0F0F),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RideColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.red),
        ),
      );

  void _toast(String msg) {
    if (!mounted) return;
    showCunnectToast(context, msg);
  }
}
