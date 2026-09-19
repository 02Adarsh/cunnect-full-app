import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../services/offline_tiles.dart';
import '../../services/open_url_stub.dart'
    if (dart.library.html) '../../services/open_url_web.dart'
    if (dart.library.io) '../../services/open_url_mobile.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart' show showCunnectToast;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // ⭐ real-time: new requests and ride status land without a Refresh.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _silent());
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
            _line(const Color(0xFF98E6B0), '${r['pickup_text']}'),
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
  Future<void> _syncGps() async {
    final store = context.read<AppStore>();
    final ride = store.rideVendorActive.isNotEmpty
        ? Map<String, dynamic>.from(store.rideVendorActive.first as Map)
        : null;
    final code = ride == null ? '' : '${ride['ride_code']}';
    final status = ride == null ? '' : '${ride['status']}';
    final shouldShare =
        code.isNotEmpty && ['paid', 'arrived', 'ongoing'].contains(status);

    if (!shouldShare) {
      _gps?.cancel();
      _gps = null;
      if (_gpsNote.isNotEmpty && mounted) {
        setState(() => _gpsNote = '');
      }
      return;
    }
    if (_gps != null && _gpsNote == code) return; // already running

    _gps?.cancel();
    _gpsNote = code;
    final ok = await _ensureLocationPermission();
    if (!ok) {
      if (mounted) {
        showCunnectToast(
            context, 'Turn on location so the student can track you');
      }
      return;
    }
    await _sendLocation(code);
    _gps = Timer.periodic(
        const Duration(seconds: 10), (_) => _sendLocation(code));
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
    _poll?.cancel();
    _gps?.cancel();
    _otp.dispose();
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

  Future<void> _startRide(String code) async {
    if (_starting) return;
    final otp = _otp.text.trim();
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
    _otp.clear();
    showCunnectToast(context, 'Ride started — have a safe trip');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return DefaultTabController(
      length: 3,
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
            tabs: [
              Tab(text: 'Requests'),
              Tab(text: 'My Ride'),
              Tab(text: 'Profile'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _requestsTab(store),
            _activeTab(store),
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
                const SizedBox(height: 60),
                const Icon(Icons.hail_rounded,
                    color: Color(0xFF4A4A4A), size: 38),
                const SizedBox(height: 14),
                Text(
                  store.rideProfile?['is_online'] == true
                      ? 'No ride requests right now.\nKeep the app open — new '
                          'requests arrive instantly.'
                      : 'You are offline.\nGo to the Profile tab and switch '
                          'ONLINE to start getting rides.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFF8A8A8A), fontSize: 12.5, height: 1.55),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              itemCount: reqs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) =>
                  _requestCard(Map<String, dynamic>.from(reqs[i] as Map)),
            ),
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
                      color: Color(0xFF98E6B0),
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          _line(const Color(0xFF98E6B0), '${r['pickup_text']}'),
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
                          : const Color(0xFF98E6B0),
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

  Widget _activeTab(AppStore store) {
    final active = store.rideVendorActive;
    final ride = active.isNotEmpty
        ? Map<String, dynamic>.from(active.first as Map)
        : null;
    final past = store.rideVendorPast;
    if (ride == null) {
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
              'it will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFF8A8A8A), fontSize: 12.5, height: 1.55),
            ),
            if (past.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('RECENT RIDES',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      letterSpacing: 2,
                      color: Color(0xFF7A7A7A),
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ...past.take(8).map((r) => _historyRow(Map<String, dynamic>.from(r as Map))),
            ],
          ],
        ),
      );
    }
    final status = '${ride['status']}';
    final when = DateTime.tryParse('${ride['scheduled_at'] ?? ''}');
    return RefreshIndicator(
      color: AppColors.red,
      onRefresh: () => store.loadRideConsole(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 26),
        children: [
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
                _line(const Color(0xFF98E6B0), '${ride['pickup_text']}'),
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
                    _chip(Icons.straighten_rounded,
                        '${ride['distance_km']} km'),
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
                            color: Color(0xFF98E6B0),
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ⭐ v73: contact number — visible only AFTER the payment
          _callRow(ride),
          const SizedBox(height: 14),
          // ⭐ v73: the map + directions unlock after the payment is
          // verified (pickup first, drop only once the OTP is in).
          _mapCard(ride),
          const SizedBox(height: 14),
          if (status == 'accepted') _waitForPayment(),
          if (status == 'paid') _bigButton("I'M ON LOCATION", 'arrived', ride),
          if (status == 'arrived') _otpBox(ride),
          if (status == 'ongoing') ...[
            const SizedBox(height: 4),
            _bigButton('COMPLETE RIDE', 'complete', ride),
          ],
          if (status == 'paid' || status == 'arrived' || status == 'ongoing')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.gps_fixed_rounded,
                      size: 13, color: Color(0xFF98E6B0)),
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
          if (past.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Text('RECENT RIDES',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    letterSpacing: 2,
                    color: Color(0xFF7A7A7A),
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...past
                .take(8)
                .map((r) => _historyRow(Map<String, dynamic>.from(r as Map))),
          ],
        ],
      ),
    );
  }

  /// ⭐ v73: the number to call — shown only after the payment is in.
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
    return GestureDetector(
      onTap: () => openExternalUrl('tel:$phone'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12200F),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0x4D98E6B0)),
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
                Text(phone,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
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
                          color: Color(0xFF98E6B0), size: 22),
                    ),
                  Marker(
                    point: dest,
                    width: 34,
                    height: 34,
                    child: Icon(
                        toPickup
                            ? Icons.trip_origin_rounded
                            : Icons.location_on_rounded,
                        color: toPickup ? const Color(0xFF98E6B0) : AppColors.red,
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

  /// ⭐ v68: the OTP is on the STUDENT's screen — the rider types it in.
  Widget _otpBox(Map<String, dynamic> ride) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFFFD34D).withOpacity(.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('START OTP',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 2,
                  color: Color(0xFFFFD34D),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
              'Ask the student to read out the OTP on his screen and '
              'type it here to start the ride.',
              style:
                  TextStyle(color: Color(0xFF9E9E9E), fontSize: 12, height: 1.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _otp,
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
                  color: Color(0xFF98E6B0),
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
            color: _online ? const Color(0xFF12200F) : const Color(0xFF111111),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
                color: _online
                    ? const Color(0xFF98E6B0).withOpacity(.5)
                    : const Color(0xFF262626)),
          ),
          child: Row(
            children: [
              Icon(Icons.circle,
                  size: 12,
                  color: _online
                      ? const Color(0xFF98E6B0)
                      : const Color(0xFF5A5A5A)),
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
                activeColor: const Color(0xFF98E6B0),
                onChanged: (v) => setState(() => _online = v),
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
        // ⭐ v73: WHEN I AM NOT AVAILABLE
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

  Widget _blocksCard(AppStore store) {
    final blocks = store.rideBlocks;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (blocks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No blocked slots — you are available all day.',
                  style: TextStyle(color: Color(0xFF7A7A7F), fontSize: 11.5)),
            )
          else
            for (final b in blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Icon(
                      b['kind'] == 'daily'
                          ? Icons.repeat_rounded
                          : Icons.event_busy_rounded,
                      size: 15,
                      color: const Color(0xFFFF9CA5)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      b['kind'] == 'daily'
                          ? 'Every ${b['weekday_name']} · ${b['start']} – ${b['end']}'
                          : '${b['date']} · ${b['start']} – ${b['end']}',
                      style: const TextStyle(
                          color: Color(0xFFEDEDF0), fontSize: 12),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await context
                          .read<AppStore>()
                          .deleteRideBlock((b['id'] as num).toInt());
                      if (mounted) showCunnectToast(context, 'Slot removed');
                    },
                    child: const Icon(Icons.close_rounded,
                        size: 17, color: Color(0xFF7A7A7F)),
                  ),
                ]),
              ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addBlock('daily'),
                icon: const Icon(Icons.repeat_rounded, size: 15),
                label: const Text('Every week'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x33FFFFFF)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                  textStyle: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addBlock('date'),
                icon: const Icon(Icons.calendar_month_rounded, size: 15),
                label: const Text('One date'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x33FFFFFF)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                  textStyle: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _addBlock(String kind) async {
    var weekday = DateTime.now().weekday - 1;
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
                        selected: weekday == i,
                        selectedColor: AppColors.red,
                        backgroundColor: const Color(0xFF1E1E1E),
                        labelStyle: TextStyle(
                            color: weekday == i
                                ? Colors.white
                                : const Color(0xFF9A9A9A),
                            fontSize: 11),
                        onSelected: (_) => setLocal(() => weekday = i),
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
      if (kind == 'daily') 'weekday': weekday,
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
