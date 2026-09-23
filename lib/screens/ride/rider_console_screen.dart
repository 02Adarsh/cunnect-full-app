import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/app_portal.dart';
import '../../services/app_store.dart';
import '../../services/offline_tiles.dart';
import '../../services/ride_events.dart';
import '../../services/ring_service.dart';
import '../../services/open_url_stub.dart'
    if (dart.library.html) '../../services/open_url_web.dart'
    if (dart.library.io) '../../services/open_url_mobile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart'
    show showCunnectToast, cunnectInputDecoration;
import '../../widgets/ride_ui.dart';
import 'ride_history_screen.dart';

/// ⭐ v68: RIDE PARTNER console (vendor portal tab).
///
///  * Requests — incoming rides with the TIME, distance and fare
///  * My Ride  — "I'm on location" -> student reads out the OTP ->
///               the RIDER types it here -> ride starts -> complete
///  * Profile  — vehicle, online switch, own pricing, earnings
///
/// While a ride is live the console shares the rider's GPS every
/// 10 seconds so the student sees the vehicle move on the map.
class RiderConsoleScreen extends StatefulWidget {
  const RiderConsoleScreen({super.key});

  @override
  State<RiderConsoleScreen> createState() => _RiderConsoleScreenState();
}

class _RiderConsoleScreenState extends State<RiderConsoleScreen> {
  Timer? _poll;
  Timer? _gps;
  final _otp = TextEditingController();
  // ⭐ v79: with more than one ride on the go each one needs its own OTP
  // field, so the code typed for ride A never leaks into ride B.
  final Map<String, TextEditingController> _otpFor = {};

  TextEditingController _otpOf(String code) =>
      _otpFor.putIfAbsent(code, () => TextEditingController());
  bool _starting = false;

  // profile form
  final _vehicleNo = TextEditingController();
  final _vehicleModel = TextEditingController();
  bool _online = false;
  final Map<String, TextEditingController> _base = {};
  final Map<String, TextEditingController> _perKm = {};
  final Map<String, bool> _active = {};
  bool _loaded = false;
  bool _saving = false;
  String _gpsNote = '';
  // ⭐ v75: the rider's own UPI id — the payment QR is built from it
  final _upi = TextEditingController();
  bool _upiSaving = false;
  // ⭐ v77: garage — every car with its number plate
  final _carName = TextEditingController();
  final _carPlate = TextEditingController();
  String _carType = 'mini';
  bool _carSaving = false;

  StreamSubscription<RideEvent>? _events;

  @override
  void initState() {
    super.initState();
    // ⭐ v75: this is the RIDE PARTNER portal — only rider pushes belong
    // here (student ride popups and the OTP must stay in the student app).
    ActivePortal.set(AppPortal.rider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      // ⭐ v74: an event that arrived while the app was closed (payment,
      // cancellation, SOS) is shown the moment the console opens.
      RideEvents.consumePending(context);
    });
    // ⭐ real-time: new requests and ride status land without a Refresh.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _silent());
    // ⭐ v74: pushes refresh the console instantly and raise a popup.
    _events = RideEvents.stream.listen((ev) {
      if (!mounted) return;
      // ⭐ v77: never paint a STUDENT event inside the partner portal
      // (the payment confirmation prompt and the OTP belong to the
      // student's phone, not to this screen).
      if (!RideEvents.belongsHere(ev)) return;
      context.read<AppStore>().loadRideConsole();
      if (ev.kind != 'new_request' && ev.kind != 'accepted') {
        RideEvents.show(context, ev);
      }
    });
  }

  Future<void> _load() async {
    final store = context.read<AppStore>();
    await store.loadRideConsole();
    if (!mounted) return;
    // ⭐ v73: everything already on screen is "known" — only later
    // arrivals raise the accept/reject popup.
    for (final r in store.rideRequests) {
      _knownRequests.add('${(r as Map)['ride_code']}');
    }
    _firstLoadDone = true;
    // ⭐ v75: without a UPI id the student cannot get a payment QR
    try {
      final upi = await store.fetchVendorUpi();
      if (!mounted) return;
      if (upi.isNotEmpty) _upi.text = upi;
    } catch (_) {}
    final p = store.rideProfile;
    if (p != null) {
      _vehicleNo.text = '${p['vehicle_number'] ?? ''}';
      _vehicleModel.text = '${p['vehicle_model'] ?? ''}';
      _online = p['is_online'] == true;
    }
    for (final v in store.rideVehicles) {
      final m = Map<String, dynamic>.from(v as Map);
      final key = '${m['key']}';
      if (!_base.containsKey(key)) {
        _base[key] = TextEditingController(text: '${m['base']}');
        _perKm[key] = TextEditingController(text: '${m['per_km']}');
      }
      _active[key] = m['active'] == true;
    }
    if (!mounted) return;
    setState(() => _loaded = true);
    _syncGps();
  }

  /// Background refresh (no spinner, no toast).
  /// Ride codes already on screen — only brand-new ones raise the popup.
  final Set<String> _knownRequests = {};
  bool _firstLoadDone = false;
  bool _requestDialogOpen = false;

  Future<void> _silent() async {
    if (!mounted) return;
    final store = context.read<AppStore>();
    await Future.wait([
      store.loadRideRequests(),
      store.loadRideVendorRides(),
    ]);
    if (!mounted) return;
    setState(() {});
    _syncGps();
    _raiseRequestPopup();
  }

  /// ⭐ v73: a NEW ride request pops up on the rider's screen with
  /// Accept / Reject — no need to be looking at the Requests tab.
  void _raiseRequestPopup() {
    if (!_firstLoadDone || _requestDialogOpen || !mounted) return;
    final reqs = context.read<AppStore>().rideRequests;
    if (reqs.isEmpty) return;
    final fresh = reqs
        .where((r) => !_knownRequests.contains('${(r as Map)['ride_code']}'))
        .toList();
    if (fresh.isEmpty) return;
    for (final r in fresh) {
      _knownRequests.add('${(r as Map)['ride_code']}');
    }
    _showRequestDialog(Map<String, dynamic>.from(fresh.first as Map));
    // ⭐ v75: non-stop ring for 20 seconds on a new ride request.
    RingService.ring(key: '${(fresh.first as Map)['ride_code']}');
  }

  void _showRequestDialog(Map<String, dynamic> r) {
    _requestDialogOpen = true;
    final when = DateTime.tryParse('${r['scheduled_at'] ?? ''}');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          Text('${r['vehicle_icon']}', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 9),
          Expanded(
            child: Text('New ${r['vehicle_label']} request',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _line(const Color(0xFFF5F5F5), '${r['pickup_text']}'),
            const SizedBox(height: 7),
            _line(AppColors.red, '${r['drop_text']}'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip(Icons.schedule_rounded,
                  when == null ? 'Leave now' : _fmtWhen(when)),
              _chip(Icons.straighten_rounded, '${r['distance_km']} km'),
              _chip(Icons.currency_rupee_rounded,
                  '${((r['fare'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
            ]),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _requestDialogOpen = false;
              RingService.stop();
              _act('reject', '${r['ride_code']}');
            },
            child: const Text('REJECT',
                style: TextStyle(
                    color: Color(0xFF9E9E9E), fontWeight: FontWeight.w800)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              _requestDialogOpen = false;
              RingService.stop();
              _act('accept', '${r['ride_code']}');
            },
            child: const Text('ACCEPT',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ).then((_) => _requestDialogOpen = false);
  }

  /// ⭐ Share GPS while the ride is live (and stop when it is not).
  /// ⭐ v79: with several rides running at once the partner's position
  /// is pushed to EVERY live ride, not just the first one.
  Future<void> _syncGps() async {
    final store = context.read<AppStore>();
    final codes = store.rideVendorActive
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .where((r) => ['paid', 'arrived', 'ongoing'].contains('${r['status']}'))
        .map((r) => '${r['ride_code']}')
        .where((c) => c.isNotEmpty)
        .toList();

    if (codes.isEmpty) {
      _gps?.cancel();
      _gps = null;
      if (_gpsNote.isNotEmpty && mounted) {
        setState(() => _gpsNote = '');
      }
      return;
    }
    final key = codes.join(',');
    if (_gps != null && _gpsNote == key) return; // already running

    _gps?.cancel();
    _gpsNote = key;
    final ok = await _ensureLocationPermission();
    if (!ok) {
      if (mounted) {
        showCunnectToast(
            context, 'Turn on location so the student can track you');
      }
      return;
    }
    for (final code in codes) {
      await _sendLocation(code);
    }
    _gps = Timer.periodic(const Duration(seconds: 10), (_) {
      for (final code in codes) {
        _sendLocation(code);
      }
    });
  }

  Future<bool> _ensureLocationPermission() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return false;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _sendLocation(String code) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      await context
          .read<AppStore>()
          .rideVendorLocation(code, pos.latitude, pos.longitude);
    } catch (_) {}
  }

  @override
  void dispose() {
    _events?.cancel();
    _poll?.cancel();
    _gps?.cancel();
    _otp.dispose();
    for (final c in _otpFor.values) {
      c.dispose();
    }
    _vehicleNo.dispose();
    _vehicleModel.dispose();
    for (final c in _base.values) {
      c.dispose();
    }
    for (final c in _perKm.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// ⭐ v77: the partner's garage — every car with its number plate.
  Widget _garageCard(AppStore store) {
    final cars = store.rideGarage;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cars.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('No vehicle saved yet — add your first one below.',
                  style:
                      TextStyle(color: Color(0xFF7A7A7A), fontSize: 11.5)),
            ),
          for (final c in cars)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${(c as Map)['vehicle_icon'] ?? '🚗'}',
                      style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${c['name'] ?? ''}'.trim().isEmpty
                              ? '${c['vehicle_label'] ?? ''}'
                              : '${c['name']}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${c['vehicle_label'] ?? ''} · ${c['plate'] ?? ''}',
                          style: const TextStyle(
                              color: Color(0xFF8A8A8A), fontSize: 11)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    final id = c['id'] is int
                        ? c['id'] as int
                        : int.tryParse('${c['id']}');
                    if (id == null) return;
                    final err =
                        await context.read<AppStore>().deleteRideVehicle(id);
                    if (!mounted) return;
                    showCunnectToast(context, err ?? 'Vehicle removed');
                  },
                  child: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: Color(0xFF8A8A8A)),
                ),
              ]),
            ),
          const Divider(color: Color(0xFF232323), height: 18),
          Row(
            children: [
              for (final t in const [
                ('mini', 'Mini', '🚗'),
                ('sedan', 'Sedan', '🚙'),
                ('suv', 'SUV', '🚐'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _carType = t.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: _carType == t.$1
                            ? AppColors.red
                            : Colors.transparent,
                        border: Border.all(
                            color: _carType == t.$1
                                ? AppColors.red
                                : const Color(0xFF2E2E2E)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${t.$3} ${t.$2}',
                          style: TextStyle(
                              color: _carType == t.$1
                                  ? Colors.white
                                  : const Color(0xFF9E9E9E),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _field(_carName, 'Car name (e.g. Swift Dzire)'),
          const SizedBox(height: 8),
          _field(_carPlate, 'Number plate (e.g. UP32AB1234)'),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _carSaving ? null : _addVehicle,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF3A3A3A)),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _carSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('ADD VEHICLE',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  /// ⭐ v77: save a car in the garage.
  Future<void> _addVehicle() async {
    final name = _carName.text.trim();
    final plate = _carPlate.text.trim().toUpperCase();
    if (name.isEmpty || plate.isEmpty) {
      showCunnectToast(context, 'Car name and number plate are both needed');
      return;
    }
    setState(() => _carSaving = true);
    final err = await context
        .read<AppStore>()
        .addRideVehicle(_carType, name, plate);
    if (!mounted) return;
    setState(() => _carSaving = false);
    if (err == null) {
      _carName.clear();
      _carPlate.clear();
    }
    showCunnectToast(context, err ?? 'Vehicle added');
  }

  /// ⭐ v75: save the rider's UPI id (the payment QR is built from it).
  Future<void> _saveUpi() async {
    final v = _upi.text.trim();
    if (v.isEmpty) {
      showCunnectToast(context, 'Enter your UPI id first');
      return;
    }
    setState(() => _upiSaving = true);
    final err = await context.read<AppStore>().saveVendorUpi(v);
    if (!mounted) return;
    setState(() => _upiSaving = false);
    showCunnectToast(context, err ?? 'UPI id saved — ride payments enabled');
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final rates = <String, Map<String, dynamic>>{};
    for (final key in _base.keys) {
      rates[key] = {
        'active': _active[key] ?? false,
        'base': double.tryParse(_base[key]!.text.trim()) ?? 0,
        'per_km': double.tryParse(_perKm[key]!.text.trim()) ?? 0,
      };
    }
    final err = await context.read<AppStore>().saveRideVendorProfile(
          vehicleNumber: _vehicleNo.text,
          vehicleModel: _vehicleModel.text,
          isOnline: _online,
          rates: rates,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    showCunnectToast(
        context, err ?? (_online ? "You're online — ride alerts on" : 'Saved'));
  }

  Future<void> _act(String action, String code) async {
    // ⭐ v75: accepting / rejecting stops the ring at once.
    RingService.stop();
    // ⭐ v77: accepting means choosing the car for this ride first.
    if (action == 'accept') {
      await _pickVehicleThenAccept(code);
      return;
    }
    // ⭐ v78: ending a 50-50 ride parks it until the balance is paid —
    // tell the partner instead of pretending it is done.
    if (action == 'complete') {
      final res =
          await context.read<AppStore>().rideVendorComplete(code);
      if (!mounted) return;
      if (res['ok'] != true) {
        showCunnectToast(context, '${res['error']}');
        return;
      }
      showCunnectToast(
          context,
          res['awaiting'] == true
              ? 'Waiting for the student to pay the balance'
              : 'Ride completed');
      _syncGps();
      return;
    }
    final store = context.read<AppStore>();
    final err = await store.rideVendorAction(action, code);
    if (!mounted) return;
    if (err != null) {
      showCunnectToast(context, err);
      return;
    }
    if (action == 'arrived') {
      showCunnectToast(context, 'Ask the student for the OTP');
    }
    _syncGps();
  }

  /// ⭐ v77: which car is the partner driving for THIS ride? Every saved
  /// vehicle (all categories) plus a one-off that is never saved.
  Future<void> _pickVehicleThenAccept(String code) async {
    final store = context.read<AppStore>();
    await store.loadRideVendorProfile();
    if (!mounted) return;
    final garage = context.read<AppStore>().rideGarage;
    int? picked;
    var other = garage.isEmpty;
    var saving = false;
    final name = TextEditingController();
    final plate = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.86),
            decoration: const BoxDecoration(
              color: Color(0xFF0B0B0B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              border: Border(top: BorderSide(color: Color(0x33FFFFFF))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3A),
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Expanded(
                      child: Text('Which car are you driving?',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                      'Pick one of your vehicles, or add one just for this '
                      'ride — that one is not saved in your garage.',
                      style: TextStyle(
                          color: Color(0xFF8A8A8A),
                          fontSize: 11.5,
                          height: 1.45)),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      for (final v in garage)
                        _vehicleOption(
                          icon: '${(v as Map)['vehicle_icon'] ?? '🚗'}',
                          label: '${v['vehicle_label'] ?? ''}',
                          title: '${v['name'] ?? ''}',
                          plate: '${v['plate'] ?? ''}',
                          on: !other && picked == v['id'],
                          onTap: () => setLocal(() {
                            picked = v['id'] is int
                                ? v['id'] as int
                                : int.tryParse('${v['id']}');
                            other = false;
                          }),
                        ),
                      _vehicleOption(
                        icon: '＋',
                        label: 'One-off',
                        title: 'Use another vehicle',
                        plate: 'only for this ride',
                        on: other,
                        onTap: () => setLocal(() {
                          other = true;
                          picked = null;
                        }),
                      ),
                      if (other) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: cunnectInputDecoration(
                              placeholder: 'Car name (e.g. Swift Dzire)'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: plate,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: cunnectInputDecoration(
                              placeholder: 'Number plate (e.g. UP32AB1234)'),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              if (other &&
                                  name.text.trim().isEmpty &&
                                  plate.text.trim().isEmpty) {
                                showCunnectToast(
                                    context, 'Enter the car and its plate');
                                return;
                              }
                              if (!other && picked == null) {
                                showCunnectToast(
                                    context, 'Choose a vehicle first');
                                return;
                              }
                              setLocal(() => saving = true);
                              final err = await context
                                  .read<AppStore>()
                                  .rideVendorAccept(
                                    code,
                                    vehicleId: other ? null : picked,
                                    vehicleName:
                                        other ? name.text.trim() : null,
                                    vehiclePlate: other
                                        ? plate.text.trim().toUpperCase()
                                        : null,
                                  );
                              if (!mounted) return;
                              setLocal(() => saving = false);
                              Navigator.of(ctx).pop();
                              showCunnectToast(context,
                                  err ?? 'Ride accepted — the student pays now');
                              if (err == null) {
                                context.read<AppStore>().loadRideConsole();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13)),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('ACCEPT RIDE',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _vehicleOption({
    required String icon,
    required String label,
    required String title,
    required String plate,
    required bool on,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: on ? const Color(0x1AF10B1D) : const Color(0xFF141414),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
                color: on ? AppColors.red : const Color(0xFF262626)),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(icon, style: const TextStyle(fontSize: 19)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.isEmpty ? label : title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(plate.isEmpty ? label : '$label · $plate',
                      style: const TextStyle(
                          color: Color(0xFF8A8A8A), fontSize: 11)),
                ],
              ),
            ),
            Icon(
              on
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 19,
              color: on ? AppColors.red : const Color(0xFF6A6A6A),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _startRide(String code) async {
    if (_starting) return;
    final otp = _otpOf(code).text.trim();
    if (otp.isEmpty) {
      showCunnectToast(context, 'Enter the OTP the student reads out');
      return;
    }
    setState(() => _starting = true);
    final err = await context.read<AppStore>().rideVendorStart(code, otp);
    if (!mounted) return;
    setState(() => _starting = false);
    if (err != null) {
      showCunnectToast(context, err);
      return;
    }
    _otpOf(code).clear();
    showCunnectToast(context, 'Ride started — have a safe trip');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.page,
        appBar: AppBar(
          backgroundColor: AppColors.page,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('RIDE PARTNER',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          bottom: const TabBar(
            indicatorColor: AppColors.red,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFF7A7A7A),
            labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Requests'),
              Tab(text: 'My Ride'),
              Tab(text: 'History'),
              Tab(text: 'Profile'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _requestsTab(store),
            _activeTab(store),
            const RiderHistoryScreen(embedded: true),
            _profileTab(store),
          ],
        ),
      ),
    );
  }

  // --------------------------- REQUESTS ---------------------------

  Widget _requestsTab(AppStore store) {
    final reqs = store.rideRequests;
    return RefreshIndicator(
      color: AppColors.red,
      onRefresh: () => store.loadRideConsole(),
      child: reqs.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(26),
              children: [
                _earningsCard(store),
                const SizedBox(height: 16),
                _emptyRequests(store),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
              children: [
                _earningsCard(store),
                const SizedBox(height: 14),
                ...reqs.map((r) =>
                    _requestCard(Map<String, dynamic>.from(r as Map))),
              ],
            ));
  }

  /// ⭐ v74: today's earnings at a glance.
  Widget _earningsCard(AppStore store) {
    final st = store.rideVendorStats;
    double d(String k) => ((st[k] as num?)?.toDouble() ?? 0);
    return RideGlass(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.red.withOpacity(.14),
          const Color(0xFF131313).withOpacity(.92),
        ],
      ),
      border: Border.all(color: AppColors.red.withOpacity(.3)),
      child: Column(
        children: [
          Row(
            children: [
              RideStat(
                  value: '₹${d('today').toStringAsFixed(0)}',
                  label: 'TODAY',
                  color: RideColors.mint),
              Container(width: 1, height: 30, color: RideColors.line),
              RideStat(
                  value: '₹${d('month').toStringAsFixed(0)}',
                  label: 'THIS MONTH'),
              Container(width: 1, height: 30, color: RideColors.line),
              RideStat(
                  value: '₹${d('earnings').toStringAsFixed(0)}',
                  label: 'TOTAL'),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                RideChip(
                    icon: Icons.directions_car_rounded,
                    label: '${st['rides'] ?? 0} rides'),
                const SizedBox(width: 7),
                RideChip(
                    icon: Icons.straighten_rounded,
                    label: '${d('km').toStringAsFixed(0)} km'),
                const Spacer(),
                if (d('pending') > 0)
                  RideChip(
                      icon: Icons.currency_rupee_rounded,
                      label: '₹${d('pending').toStringAsFixed(0)} due',
                      color: RideColors.amber),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyRequests(AppStore store) {
    final online = store.rideProfile?['is_online'] == true;
    return Column(
      children: [
        const SizedBox(height: 26),
        const Icon(Icons.hail_rounded, color: Color(0xFF4A4A4A), size: 38),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            online
                ? 'No ride requests right now.\nKeep the app open — new '
                    'requests arrive instantly.'
                : 'You are offline.\nGo to the Profile tab and switch '
                    'ONLINE to start getting rides.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF8A8A8A), fontSize: 12.5, height: 1.55),
          ),
        ),
        const SizedBox(height: 18),
        RideButton(
          label: online ? 'REFRESH' : 'GO TO PROFILE',
          filled: false,
          height: 44,
          expand: false,
          icon: online ? Icons.refresh_rounded : Icons.person_rounded,
          onTap: () async {
            if (online) {
              await store.loadRideConsole();
            } else {
              DefaultTabController.of(context).animateTo(3);
            }
          },
        ),
      ],
    );
  }


  Widget _requestCard(Map<String, dynamic> r) {
    final hidden = r['phone_hidden'] == true;
    final when = DateTime.tryParse('${r['scheduled_at'] ?? ''}');
    final km = (r['distance_km'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${r['vehicle_icon']}',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Text('${r['vehicle_label']}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('₹${((r['fare'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          _line(const Color(0xFFF5F5F5), '${r['pickup_text']}'),
          const SizedBox(height: 7),
          _line(AppColors.red, '${r['drop_text']}'),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // ⭐ v68: the booked TIME is visible here
              _chip(Icons.schedule_rounded,
                  when == null ? 'Leave now' : _fmtWhen(when)),
              _chip(Icons.straighten_rounded, '${r['distance_km']} km'),
              if ('${r['notes'] ?? ''}'.isNotEmpty)
                _chip(Icons.notes_rounded, '${r['notes']}'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _chip(Icons.person_rounded,
                  '${r['student_name']}'.isEmpty ? 'Student' : '${r['student_name']}'),
              const Spacer(),
              Text(
                  hidden
                      ? 'Number hidden until you accept'
                      : '${r['student_phone']}',
                  style: TextStyle(
                      fontSize: 11,
                      color: hidden
                          ? const Color(0xFF6A6A6A)
                          : const Color(0xFFF5F5F5),
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => _act('reject', '${r['ride_code']}'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3A3A3A)),
                      foregroundColor: const Color(0xFF9E9E9E),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                    ),
                    child: const Text('REJECT',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => _act('accept', '${r['ride_code']}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                    ),
                    child: const Text('ACCEPT',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtWhen(DateTime d) {
    final now = DateTime.now();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today $hh:$mm';
    }
    if (d.year == now.year && d.month == now.month && d.day == now.day + 1) {
      return 'Tomorrow $hh:$mm';
    }
    return '${d.day}/${d.month} $hh:$mm';
  }

  Widget _line(Color color, String text) => Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      );

  Widget _chip(IconData icon, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12.5, color: const Color(0xFF9E9E9E)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(t,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFFB7B7BC), fontSize: 11)),
            ),
          ],
        ),
      );

  // --------------------------- ACTIVE -----------------------------

  /// ⭐ v79: a ride partner can ACCEPT, RUN and CLOSE several rides at
  /// the same time. Every active ride gets its own card here — its own
  /// map, its own payment panel and its own buttons.
  Widget _activeTab(AppStore store) {
    final active = store.rideVendorActive
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    if (active.isEmpty) {
      return RefreshIndicator(
        color: AppColors.red,
        onRefresh: () => store.loadRideConsole(),
        child: ListView(
          padding: const EdgeInsets.all(26),
          children: [
            const SizedBox(height: 50),
            const Icon(Icons.directions_car_rounded,
                color: Color(0xFF4A4A4A), size: 38),
            const SizedBox(height: 14),
            const Text(
              'No active ride.\nAccept a request from the Requests tab and '
              'it will show up here.\n\nFinished rides are in the History '
              'tab.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF8A8A8A), fontSize: 12.5, height: 1.55),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.red,
      onRefresh: () => store.loadRideConsole(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 26),
        children: [
          if (active.length > 1)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.red.withOpacity(.42)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers_rounded,
                      size: 15, color: AppColors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${active.length} rides running together — accept '
                      'and close as many as you can handle.',
                      style: const TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontSize: 11.5,
                          height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          for (var i = 0; i < active.length; i++) ...[
            _activeRideCard(active[i], i + 1),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  /// One live ride — everything it needs is inside its own card, so two
  /// or three of them can sit on top of each other without confusion.
  Widget _activeRideCard(Map<String, dynamic> ride, int index) {
    final status = '${ride['status']}';
    final when = DateTime.tryParse('${ride['scheduled_at'] ?? ''}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(.12),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppColors.red.withOpacity(.38)),
              ),
              child: Text('RIDE $index · ${ride['ride_code']}',
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9.5,
                      letterSpacing: 1.1,
                      color: AppColors.red,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.red.withOpacity(.42)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_statusLine(status),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _line(const Color(0xFFF5F5F5), '${ride['pickup_text']}'),
              const SizedBox(height: 7),
              _line(AppColors.red, '${ride['drop_text']}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(Icons.schedule_rounded,
                      when == null ? 'Leave now' : _fmtWhen(when)),
                  _chip(Icons.directions_car_rounded,
                      '${ride['vehicle_label']}'),
                  _chip(Icons.straighten_rounded, '${ride['distance_km']} km'),
                  if ('${ride['notes'] ?? ''}'.isNotEmpty)
                    _chip(Icons.notes_rounded, '${ride['notes']}'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        '${ride['student_name']} · ${ride['student_phone']}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5)),
                  ),
                  Text(
                      '₹${((ride['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ⭐ v74: exactly what the student paid — full or the first
        // half — with the transaction id and whatever is still due.
        _paymentPanel(ride),
        const SizedBox(height: 14),
        // ⭐ v73: contact number — visible only AFTER the payment
        _callRow(ride),
        const SizedBox(height: 14),
        // ⭐ v73: the map + directions unlock after the payment is
        // verified (pickup first, drop only once the OTP is in).
        _mapCard(ride),
        const SizedBox(height: 14),
        if (status == 'accepted') _waitForPayment(),
        // ⭐ v75: nothing is automatic — the rider confirms he received
        // the money before the trip can move on.
        if (ride['can_confirm'] == true) _confirmCard(ride),
        if (status == 'paid' && ride['can_confirm'] != true)
          _bigButton("I'M ON LOCATION", 'arrived', ride),
        if (status == 'arrived') _otpBox(ride),
        if (status == 'ongoing' && ride['awaiting_balance'] != true) ...[
          const SizedBox(height: 4),
          _bigButton('COMPLETE RIDE', 'complete', ride),
        ],
        if (ride['awaiting_balance'] == true) ...[
          const SizedBox(height: 4),
          _waitingBalance(ride),
        ],
        if (status == 'paid' || status == 'arrived' || status == 'ongoing')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.gps_fixed_rounded,
                    size: 13, color: Color(0xFFF5F5F5)),
                const SizedBox(width: 7),
                Text(
                    _gps != null
                        ? 'Sharing your live location with the student'
                        : 'Location not shared',
                    style: const TextStyle(
                        color: Color(0xFF7A7A7A), fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }

  /// ⭐ v78: a 50-50 ride cannot be closed while the second half is
  /// unpaid — the ride partner sees exactly where it stands.
  Widget _waitingBalance(Map<String, dynamic> ride) {
    final due = ((ride['balance_due'] as num?)?.toDouble() ?? 0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.red.withOpacity(.42)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
                color: AppColors.red, strokeWidth: 2),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Waiting for the student to pay ₹${due.toStringAsFixed(0)}. '
              'The ride closes on its own the moment it lands.',
              style: const TextStyle(
                  color: Color(0xFFF5F5F5), fontSize: 11.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  /// ⭐ v74: the money, exactly like the food vendor portal shows it.
  Widget _paymentPanel(Map<String, dynamic> ride) {
    final mode = '${ride['payment_mode']}';
    final paid = ((ride['amount_paid'] as num?)?.toDouble() ?? 0);
    final due = ((ride['balance_due'] as num?)?.toDouble() ?? 0);
    final done = ride['payment_done'] == true;
    final txn = '${ride['txn_first'] ?? ''}';
    final txn2 = '${ride['txn_second'] ?? ''}';
    final split = mode == 'split';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: done
                ? RideColors.mint.withOpacity(.4)
                : const Color(0xFF262626)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('PAYMENT',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      letterSpacing: 2,
                      color: Color(0xFF7A7A7A),
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              RideChip(
                label: mode.isEmpty
                    ? 'not paid yet'
                    : (split ? '50-50 SPLIT' : 'FULL PAYMENT'),
                color: mode.isEmpty
                    ? const Color(0xFF8A8A8A)
                    : (split ? RideColors.amber : RideColors.mint),
              ),
            ],
          ),
          if (ride['awaiting_balance'] == true) ...[
            const SizedBox(height: 10),
            const Text(
              'Balance pending — the ride closes as soon as the student '
              'pays, and their transaction ID shows up below.',
              style: TextStyle(
                  color: Color(0xFF9E9E9E), fontSize: 10.5, height: 1.45),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Received',
                        style: TextStyle(
                            color: Color(0xFF7A7A7A), fontSize: 10.5)),
                    const SizedBox(height: 3),
                    Text('₹${paid.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: RideColors.mint,
                            fontSize: 19,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (due > 0) ...[
                Container(width: 1, height: 32, color: const Color(0xFF262626)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Still due',
                          style: TextStyle(
                              color: Color(0xFF7A7A7A), fontSize: 10.5)),
                      const SizedBox(height: 3),
                      Text('₹${due.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: RideColors.amber,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (txn.isNotEmpty || txn2.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF262626)),
              ),
              child: Column(
                children: [
                  if (txn.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded,
                            size: 13, color: Color(0xFF7A7A7A)),
                        const SizedBox(width: 8),
                        const Text('Txn 1 · ',
                            style: TextStyle(
                                color: Color(0xFF7A7A7A), fontSize: 11)),
                        Expanded(
                          child: Text(txn,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11.5)),
                        ),
                      ],
                    ),
                  if (txn2.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded,
                            size: 13, color: Color(0xFF7A7A7A)),
                        const SizedBox(width: 8),
                        const Text('Balance txn · ',
                            style: TextStyle(
                                color: Color(0xFF7A7A7A), fontSize: 11)),
                        Expanded(
                          child: Text(txn2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11.5)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (due > 0) ...[
            const SizedBox(height: 13),
            RideButton(
              label: 'COLLECT ₹${due.toStringAsFixed(0)} FROM THE STUDENT',
              height: 46,
              icon: Icons.currency_rupee_rounded,
              busy: _collecting,
              onTap: _collecting ? null : () => _collectBalance(ride),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only tap this after the student has actually paid you the '
              'balance.',
              style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 10.5,
                  height: 1.45),
            ),
          ] else if (done) ...[
            const SizedBox(height: 11),
            Row(
              children: const [
                Icon(Icons.check_circle_rounded,
                    size: 14, color: RideColors.mint),
                SizedBox(width: 7),
                Text('Fully paid — nothing left to collect',
                    style: TextStyle(
                        color: RideColors.mint, fontSize: 11.5)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _collecting = false;

  Future<void> _collectBalance(Map<String, dynamic> ride) async {
    final code = '${ride['ride_code']}';
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF121212),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            title: const Text('Balance received?',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: const Text(
              'Only confirm this once the student has paid you the '
              'remaining amount in cash.',
              style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('NOT YET',
                      style: TextStyle(color: Color(0xFF8A8A8A)))),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('RECEIVED',
                      style: TextStyle(color: RideColors.mint))),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    if (!mounted) return;
    setState(() => _collecting = true);
    final err =
        await context.read<AppStore>().rideCollectBalance(code);
    if (!mounted) return;
    setState(() => _collecting = false);
    showCunnectToast(context, err ?? 'Balance marked as received',
        error: err != null);
  }

  /// ⭐ v73: the number to call — shown only after the payment is in.
  /// ⭐ v77: 9876543210 -> 98XXXXX210 (never paint the real digits)
  String _maskOf(String p) {
    final t = p.trim();
    if (t.length < 6) return t;
    return '${t.substring(0, 2)}${'X' * (t.length - 5)}'
        '${t.substring(t.length - 3)}';
  }

  Widget _callRow(Map<String, dynamic> ride) {
    final hidden = ride['phone_hidden'] == true;
    final phone = '${ride['contact_phone'] ?? ride['student_phone'] ?? ''}';
    if (hidden || phone.trim().isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: const Row(children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF6A6A6A)),
          SizedBox(width: 11),
          Expanded(
            child: Text('Number appears once the payment is verified',
                style: TextStyle(color: Color(0xFF7A7A7F), fontSize: 12)),
          ),
        ]),
      );
    }
    final other = ride['booking_for_other'] == true;
    // ⭐ v77: the rider may CALL the student, but the number itself is
    // never painted — only a masked version is shown.
    final masked = '${ride['student_phone_masked'] ?? ''}';
    final shown = masked.isNotEmpty ? masked : _maskOf(phone);
    return GestureDetector(
      onTap: () => openExternalUrl('tel:$phone'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.call_rounded,
                size: 17, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(other ? 'Call the passenger' : 'Call the student',
                    style: const TextStyle(
                        color: Color(0xFF9E9E9E), fontSize: 10.5)),
                const SizedBox(height: 2),
                Text(shown,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                const SizedBox(height: 2),
                const Text('tap to call — the number is never shown',
                    style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 9.5)),
                if (other && '${ride['other_name'] ?? ''}'.isNotEmpty)
                  Text('${ride['other_name']}',
                      style: const TextStyle(
                          color: Color(0xFF8A8A8A), fontSize: 10.5)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF8A8A8A)),
        ]),
      ),
    );
  }

  /// ⭐ v73: MAP + DIRECTIONS — to the pickup after the payment, to the
  /// drop only after the student's OTP has been entered.
  Widget _mapCard(Map<String, dynamic> ride) {
    final status = '${ride['status']}';
    final toPickup = status == 'paid' || status == 'arrived';
    final unlocked = toPickup || status == 'ongoing';
    if (!unlocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: const Row(children: [
          Icon(Icons.map_outlined, size: 17, color: Color(0xFF6A6A6A)),
          SizedBox(width: 11),
          Expanded(
            child: Text(
                'Map and directions unlock as soon as the payment is '
                'verified.',
                style: TextStyle(color: Color(0xFF7A7A7F), fontSize: 12)),
          ),
        ]),
      );
    }

    final destLat =
        ((toPickup ? ride['pickup_lat'] : ride['drop_lat']) as num?)
            ?.toDouble();
    final destLng =
        ((toPickup ? ride['pickup_lng'] : ride['drop_lng']) as num?)
            ?.toDouble();
    final rLat = (ride['rider_lat'] as num?)?.toDouble();
    final rLng = (ride['rider_lng'] as num?)?.toDouble();
    if (destLat == null || destLng == null) return const SizedBox.shrink();

    final dest = LatLng(destLat, destLng);
    final from = (rLat != null && rLng != null) ? LatLng(rLat, rLng) : null;
    final centre = from ?? dest;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 190,
            child: FlutterMap(
              options: MapOptions(initialCenter: centre, initialZoom: 14.5),
              children: [
                TileLayer(
                  // ⭐ v73: cached on the phone → works offline too
                  tileProvider: CachedTileProvider(),
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.cunnect.cunnect_food',
                  maxZoom: 19,
                ),
                if (from != null)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: [from, dest],
                      color: AppColors.red.withOpacity(.9),
                      strokeWidth: 4,
                    ),
                  ]),
                MarkerLayer(markers: [
                  if (from != null)
                    Marker(
                      point: from,
                      width: 32,
                      height: 32,
                      child: const Icon(Icons.gps_fixed_rounded,
                          color: Color(0xFFF5F5F5), size: 22),
                    ),
                  Marker(
                    point: dest,
                    width: 34,
                    height: 34,
                    child: Icon(
                        toPickup
                            ? Icons.trip_origin_rounded
                            : Icons.location_on_rounded,
                        color: toPickup ? const Color(0xFFF5F5F5) : AppColors.red,
                        size: 28),
                  ),
                ]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(toPickup ? 'Head to the pickup' : 'Head to the drop',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(toPickup ? '${ride['pickup_text']}' : '${ride['drop_text']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF8A8A8A), fontSize: 11.5)),
                const SizedBox(height: 11),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final url = from == null
                          ? 'https://www.google.com/maps/dir/?api=1'
                              '&destination=$destLat,$destLng&travelmode=driving'
                          : 'https://www.google.com/maps/dir/?api=1'
                              '&origin=${from.latitude},${from.longitude}'
                              '&destination=$destLat,$destLng&travelmode=driving';
                      final err = await openExternalUrl(url);
                      if (err != null && mounted) {
                        showCunnectToast(context, err, error: true);
                      }
                    },
                    icon: const Icon(Icons.directions_rounded, size: 18),
                    label: Text(
                        toPickup ? 'DIRECTIONS TO PICKUP' : 'DIRECTIONS TO DROP',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.red),
                      foregroundColor: AppColors.red,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLine(String status) => switch (status) {
        'accepted' => 'Waiting for the payment',
        'paid' => 'Paid — head to the pickup',
        'arrived' => 'Enter the student\'s OTP',
        'ongoing' => 'Ride in progress',
        _ => 'Ride $status',
      };

  Widget _waitForPayment() => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: const Row(
          children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    color: AppColors.red, strokeWidth: 2)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'The student is paying. You will get an alert the moment '
                'the payment is confirmed — then tap "I\'m on location".',
                style: TextStyle(
                    color: Color(0xFFB7B7BC), fontSize: 12.5, height: 1.5)),
            ),
          ],
        ),
      );

  /// ⭐ v75: the rider confirms the payment HIMSELF.
  ///
  /// Nothing moves on automatically once the student has paid — the ride
  /// only continues after this button is tapped.
  Widget _confirmCard(Map<String, dynamic> ride) {
    final paid = ((ride['amount_paid'] as num?)?.toDouble() ?? 0);
    final txn = '${ride['txn_first'] ?? ''}';
    final code = '${ride['ride_code']}';
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: RideColors.mint.withOpacity(.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded,
                  size: 18, color: RideColors.mint),
              const SizedBox(width: 9),
              const Expanded(
                child: Text('PAYMENT RECEIVED',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 2,
                        color: RideColors.mint,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('₹${paid.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800)),
          if (txn.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Txn $txn',
                style: const TextStyle(
                    color: Color(0xFF7A7A7A), fontSize: 11.5)),
          ],
          const SizedBox(height: 10),
          const Text(
            'Check the money in your UPI app, then confirm below. The '
            'ride stays on hold until you do — nothing is automatic.',
            style: TextStyle(
                color: Color(0xFFB7B7BC), fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () async {
                RingService.stop();
                final err = await context
                    .read<AppStore>()
                    .rideVendorConfirm(code);
                if (!mounted) return;
                showCunnectToast(
                    context, err ?? 'Payment confirmed — you can carry on');
                if (err == null) context.read<AppStore>().loadRideConsole();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: RideColors.mint,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
              child: const Text('CONFIRM PAYMENT',
                  style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }

  /// ⭐ v68: the OTP is on the STUDENT's screen — the rider types it in.
  Widget _otpBox(Map<String, dynamic> ride) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(15),
        // ⭐ v79: red again — the ride section is red, black and white.
        border: Border.all(color: AppColors.red.withOpacity(.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('START OTP',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 2,
                  color: AppColors.red,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
              'Ask the student to read out the OTP on his screen and '
              'type it here to start the ride.',
              style:
                  TextStyle(color: Color(0xFF9E9E9E), fontSize: 12, height: 1.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _otpOf('${ride['ride_code']}'),
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, letterSpacing: 10),
            decoration: InputDecoration(
              counterText: '',
              hintText: '----',
              hintStyle: const TextStyle(color: Color(0xFF4A4A4A)),
              filled: true,
              fillColor: const Color(0xFF0D0D0D),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: Color(0xFF303030)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: AppColors.red),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _starting ? null : () => _startRide('${ride['ride_code']}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _starting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('START RIDE',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigButton(String label, String action, Map<String, dynamic> ride) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: () => _act(action, '${ride['ride_code']}'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.red,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
      ),
    );
  }

  Future<void> _navigate(Map<String, dynamic> ride) async {
    final lat = ride['drop_lat'];
    final lng = ride['drop_lng'];
    final url = (lat is num && lng is num)
        ? 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
        : 'https://www.google.com/maps/dir/?api=1&destination='
            '${Uri.encodeComponent('${ride['drop_text']}')}';
    final msg = await openExternalUrl(url);
    if (mounted && msg != null) showCunnectToast(context, msg);
  }

  Widget _historyRow(Map<String, dynamic> r) {
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
                    style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(
                    '${r['distance_km']} km · ${r['status']} · '
                    '${r['student_name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF7A7A7A), fontSize: 10.5)),
              ],
            ),
          ),
          Text('₹${((r['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Color(0xFFF5F5F5),
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // --------------------------- PROFILE ----------------------------

  Widget _profileTab(AppStore store) {
    if (!_loaded) {
      return const Center(
          child:
              CircularProgressIndicator(color: AppColors.red, strokeWidth: 2));
    }
    final p = store.rideProfile ?? const {};
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 30),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
          decoration: BoxDecoration(
            color: _online ? const Color(0xFF1E0A0C) : const Color(0xFF111111),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
                color: _online
                    ? AppColors.red.withOpacity(.5)
                    : const Color(0xFF262626)),
          ),
          child: Row(
            children: [
              Icon(Icons.circle,
                  size: 12,
                  color: _online ? AppColors.red : const Color(0xFF5A5A5A)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_online ? "You're online" : "You're offline",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        _online
                            ? 'New ride requests will ring instantly.'
                            : 'Go online to start receiving ride requests.',
                        style: const TextStyle(
                            color: Color(0xFF9E9E9E), fontSize: 11.5)),
                  ],
                ),
              ),
              Switch(
                value: _online,
                activeColor: const Color(0xFFF5F5F5),
                onChanged: (v) => setState(() => _online = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ⭐ v81: auto driving is a SEPARATE account now. The car
        // console is for cars only — an auto partner logs in with his own
        // AUTO account and gets the AUTO portal.
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(.12),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.red.withOpacity(.18)),
                ),
                child: const Text('🛺',
                    style: TextStyle(fontSize: 19)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Drive an auto instead?',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text(
                        'Auto partners have their own CUnnect account and '
                        'their own AUTO portal. Ask the admin to create one '
                        'for this number.',
                        style: TextStyle(
                            color: Color(0xFF9E9E9E),
                            fontSize: 11,
                            height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionLabel('VEHICLE'),
        const SizedBox(height: 10),
        _field(_vehicleNo, 'Vehicle number (e.g. HR26AB1234)'),
        const SizedBox(height: 10),
        _field(_vehicleModel, 'Vehicle model (e.g. Maruti Swift)'),
        const SizedBox(height: 18),
        _sectionLabel('YOUR PRICING (PER KM)'),
        const SizedBox(height: 6),
        const Text(
          'Set what you charge for each ride type. The student sees the '
          'best available fare; when you accept, the ride locks to YOUR '
          'rate below.',
          style:
              TextStyle(color: Color(0xFF8A8A8A), fontSize: 11.5, height: 1.5),
        ),
        const SizedBox(height: 12),
        for (final v in store.rideVehicles)
          _rateCard(Map<String, dynamic>.from(v as Map)),
        const SizedBox(height: 18),
        Row(
          children: [
            _stat('RIDES', '${p['total_rides'] ?? 0}'),
            const SizedBox(width: 10),
            _stat('EARNINGS',
                '₹${((p['total_earnings'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('SAVE RIDE PROFILE',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1)),
          ),
        ),
        // ⭐ v77: MY VEHICLES — every car with its own number plate
        const SizedBox(height: 24),
        _sectionLabel('MY VEHICLES'),
        const SizedBox(height: 6),
        const Text(
          'Add every car you drive. While accepting a request you pick the '
          'one you are taking — the student sees the model first and the '
          'number plate only after you verify the payment.',
          style:
              TextStyle(color: Color(0xFF8A8A8A), fontSize: 11.5, height: 1.5),
        ),
        const SizedBox(height: 12),
        _garageCard(store),
        // ⭐ v75: PAYMENT UPI — the ride QR is generated from this id
        const SizedBox(height: 24),
        _sectionLabel('PAYMENT UPI'),
        const SizedBox(height: 6),
        const Text(
          'The student\'s payment QR is built from this UPI id with the '
          'exact fare locked in. Leave it empty and ride payments cannot '
          'be made.',
          style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 11.5, height: 1.5),
        ),
        const SizedBox(height: 10),
        _field(_upi, 'Your UPI id (e.g. yourname@okhdfcbank)'),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: OutlinedButton(
            onPressed: _upiSaving ? null : _saveUpi,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: RideColors.mint),
              foregroundColor: RideColors.mint,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _upiSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: RideColors.mint, strokeWidth: 2))
                : const Text('SAVE UPI ID',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
        ),
        // ⭐ v74: WHEN I AM NOT AVAILABLE — as many slots as needed
        const SizedBox(height: 24),
        _sectionLabel('WHEN I AM NOT AVAILABLE'),
        const SizedBox(height: 6),
        const Text(
          'Rides requested inside these windows are answered with "rider '
          'unavailable, please book for another time" automatically.',
          style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 11.5, height: 1.5),
        ),
        const SizedBox(height: 12),
        _blocksCard(context.watch<AppStore>()),
        // ⭐ v74: ride history + earnings, one tap away
        const SizedBox(height: 26),
        _sectionLabel('MY BUSINESS'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: Column(
            children: [
              RideTile(
                icon: Icons.history_rounded,
                title: 'Ride history',
                subtitle: 'Every ride you have driven, with receipts',
                trailing: const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Color(0xFF8A8A8A)),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const RiderHistoryScreen())),
              ),
              RideTile(
                icon: Icons.currency_rupee_rounded,
                tint: RideColors.mint,
                title: 'Earnings',
                subtitle:
                    'Today ₹${((store.rideVendorStats['today'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'
                    ' · this month ₹${((store.rideVendorStats['month'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                trailing: Text(
                    '${store.rideVendorStats['rides'] ?? 0} rides',
                    style: const TextStyle(
                        color: Color(0xFF8A8A8A), fontSize: 11.5)),
                onTap: () => DefaultTabController.of(context).animateTo(0),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        // ⭐ v73: LOG OUT of the ride partner account
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, size: 17),
            label: const Text('LOG OUT',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF9CA5),
              side: const BorderSide(color: Color(0x61FF0000)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF262626)),
          ),
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
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );

  Widget _rateCard(Map<String, dynamic> v) {
    final key = '${v['key']}';
    final on = _active[key] ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
            color: on ? AppColors.red.withOpacity(.5) : const Color(0xFF262626)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('${v['icon']}', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 11),
              Text('${v['label']}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              Switch(
                value: on,
                activeColor: AppColors.red,
                onChanged: (val) => setState(() => _active[key] = val),
              ),
            ],
          ),
          if (on) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _numField(_base[key]!, 'Base fare ₹')),
                const SizedBox(width: 10),
                Expanded(child: _numField(_perKm[key]!, 'Per km ₹')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF7A7A7A), fontSize: 11),
          filled: true,
          fillColor: const Color(0xFF0D0D0D),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF303030)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.red),
          ),
        ),
      );

  Widget _field(TextEditingController c, String hint) => TextField(
        controller: c,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF6E6E6E), fontSize: 12.5),
          filled: true,
          fillColor: const Color(0xFF0D0D0D),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFF303030)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: AppColors.red),
          ),
        ),
      );

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          letterSpacing: 2,
          color: Color(0xFF7A7A7A),
          fontWeight: FontWeight.w700));

  // ------------------------- logout (v73) -------------------------

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF161616),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Log out?',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: const Text(
                'You will stop receiving ride requests until you sign in '
                'again.',
                style: TextStyle(color: Color(0xFFB5B5B5), fontSize: 12.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel',
                    style: TextStyle(color: Color(0xFF9A9A9A))),
              ),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                onPressed: () => Navigator.of(context).pop(true),
                child:
                    const Text('Log out', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    _gps?.cancel();
    _gps = null;
    _poll?.cancel();
    await context.read<AppStore>().vendorLogout();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ------------------- unavailability slots (v73) -------------------

  /// ⭐ v74: EVERY slot this partner is busy — as many as he needs
  /// (4–5 pm for a class AND 6–7 pm for duty, on the same day).
  /// Rides inside any of these windows never reach him.
  Widget _blocksCard(AppStore store) {
    final blocks = store.rideBlocks;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dates = blocks
        .where((b) => '${b['kind']}' != 'daily')
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add every hour you are busy — class, duty, anything. '
            'You can add as many slots as you need on the same day.',
            style: TextStyle(
                color: Color(0xFF7A7A7F), fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < 7; i++)
            _dayRow(
              days[i],
              blocks
                  .where((b) =>
                      '${b['kind']}' == 'daily' &&
                      ((b['weekday'] as num?)?.toInt() ?? -1) == i)
                  .toList(),
              i,
            ),
          const SizedBox(height: 6),
          Container(height: 1, color: const Color(0xFF202020)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.event_busy_rounded,
                  size: 14, color: Color(0xFFFF9CA5)),
              const SizedBox(width: 8),
              const Text('Specific dates',
                  style: TextStyle(
                      color: Color(0xFFEDEDF0),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => _addBlock('date'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.red.withOpacity(.4)),
                  ),
                  child: const Text('Add a date',
                      style: TextStyle(
                          color: AppColors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          if (dates.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No one-off dates blocked.',
                  style:
                      TextStyle(color: Color(0xFF5A5A5A), fontSize: 11)),
            )
          else
            for (final b in dates)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Row(children: [
                  const Icon(Icons.calendar_month_rounded,
                      size: 14, color: Color(0xFF8A8A8A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '${b['date']} · ${b['start']} – ${b['end']}',
                        style: const TextStyle(
                            color: Color(0xFFEDEDF0), fontSize: 11.5)),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await context
                          .read<AppStore>()
                          .deleteRideBlock((b['id'] as num).toInt());
                      if (mounted) {
                        showCunnectToast(context, 'Slot removed');
                      }
                    },
                    child: const Icon(Icons.close_rounded,
                        size: 16, color: Color(0xFF7A7A7F)),
                  ),
                ]),
              ),
        ],
      ),
    );
  }

  Widget _dayRow(String label, List blocks, int weekday) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(label,
                  style: const TextStyle(
                      color: Color(0xFF9E9E9E),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in blocks)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.red.withOpacity(.12),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: AppColors.red.withOpacity(.38)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${b['start']} – ${b['end']}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () async {
                            await context
                                .read<AppStore>()
                                .deleteRideBlock((b['id'] as num).toInt());
                            if (mounted) {
                              showCunnectToast(context, 'Slot removed');
                            }
                          },
                          child: const Icon(Icons.close_rounded,
                              size: 13, color: Color(0xFFFF9CA5)),
                        ),
                      ],
                    ),
                  ),
                GestureDetector(
                  onTap: () => _addBlock('daily', weekday: weekday),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161616),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0xFF303030)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded,
                            size: 13, color: Color(0xFF9E9E9E)),
                        SizedBox(width: 3),
                        Text('slot',
                            style: TextStyle(
                                color: Color(0xFF9E9E9E), fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addBlock(String kind, {int? weekday}) async {
    var wd = weekday ?? DateTime.now().weekday - 1;
    var from = const TimeOfDay(hour: 14, minute: 0);
    var to = const TimeOfDay(hour: 16, minute: 0);
    DateTime? day = kind == 'date' ? DateTime.now() : null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setLocal) {
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        Future<void> pick(bool isFrom) async {
          final t = await showTimePicker(
            context: ctx,
            initialTime: isFrom ? from : to,
            builder: (c, child) => Theme(
              data: Theme.of(c).copyWith(
                colorScheme: const ColorScheme.dark(
                    primary: AppColors.red, surface: Color(0xFF111111)),
              ),
              child: child!,
            ),
          );
          if (t == null) return;
          setLocal(() {
            if (isFrom) {
              from = t;
            } else {
              to = t;
            }
          });
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF161616),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(kind == 'daily' ? 'Block a weekly slot' : 'Block a date',
              style: const TextStyle(color: Colors.white, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kind == 'daily')
                Wrap(
                  spacing: 6,
                  children: [
                    for (int i = 0; i < 7; i++)
                      ChoiceChip(
                        label: Text(days[i]),
                        selected: wd == i,
                        selectedColor: AppColors.red,
                        backgroundColor: const Color(0xFF1E1E1E),
                        labelStyle: TextStyle(
                            color: wd == i
                                ? Colors.white
                                : const Color(0xFF9A9A9A),
                            fontSize: 11),
                        onSelected: (_) => setLocal(() => wd = i),
                      ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: day ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        builder: (c, child) => Theme(
                          data: Theme.of(c).copyWith(
                            colorScheme: const ColorScheme.dark(
                                primary: AppColors.red,
                                surface: Color(0xFF111111)),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) setLocal(() => day = picked);
                    },
                    icon: const Icon(Icons.calendar_month_rounded, size: 16),
                    label: Text(
                        '${(day ?? DateTime.now()).day.toString().padLeft(2, '0')}-'
                        '${(day ?? DateTime.now()).month.toString().padLeft(2, '0')}-'
                        '${(day ?? DateTime.now()).year}',
                        style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0x33FFFFFF)),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => pick(true),
                    icon: const Icon(Icons.schedule_rounded, size: 15),
                    label: Text(from.format(ctx),
                        style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                ),
                const Text('–', style: TextStyle(color: Color(0xFF7A7A7F))),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => pick(false),
                    icon: const Icon(Icons.schedule_rounded, size: 15),
                    label:
                        Text(to.format(ctx), style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                ),
              ]),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child:
                  const Text('Cancel', style: TextStyle(color: Color(0xFF9A9A9A))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child:
                  const Text('Block it', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
    if (saved != true || !mounted) return;

    final body = <String, dynamic>{
      'kind': kind,
      'start': '${from.hour.toString().padLeft(2, '0')}:'
          '${from.minute.toString().padLeft(2, '0')}',
      'end': '${to.hour.toString().padLeft(2, '0')}:'
          '${to.minute.toString().padLeft(2, '0')}',
      if (kind == 'daily') 'weekday': wd,
      if (kind == 'date')
        'date': '${(day ?? DateTime.now()).year.toString().padLeft(4, '0')}-'
            '${(day ?? DateTime.now()).month.toString().padLeft(2, '0')}-'
            '${(day ?? DateTime.now()).day.toString().padLeft(2, '0')}',
    };
    final err = await context.read<AppStore>().addRideBlock(body);
    if (!mounted) return;
    showCunnectToast(context,
        err ?? 'Slot saved — you will get no ride requests then',
        error: err != null);
  }

}
