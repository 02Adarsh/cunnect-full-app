import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ride_ui.dart';
import 'ride_home_screen.dart';

/// ⭐ v74: the student's RIDE HISTORY.
///
/// A clean chronological list — tap any ride for the full receipt
/// (route, fare, payment mode, transaction id, balance, co-passengers).
class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

/// ⭐ v74: the same page for the ride partner.
///
/// [embedded] renders it without its own Scaffold so it can sit inside
/// the rider console's tab bar.
class RiderHistoryScreen extends StatefulWidget {
  const RiderHistoryScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<RiderHistoryScreen> createState() => _RiderHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  String _filter = 'all';
  bool _busy = false;

  List<Map<String, dynamic>> _rides(AppStore store) =>
      store.pastRides.map((r) => Map<String, dynamic>.from(r as Map)).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _busy = true);
    await context.read<AppStore>().loadRides();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) =>
      _HistoryBody(rider: false, filter: _filter, busy: _busy,
          onFilter: (f) => setState(() => _filter = f),
          rides: _rides(context.watch<AppStore>()),
          onRefresh: _load);
}

class _RiderHistoryScreenState extends State<RiderHistoryScreen> {
  String _filter = 'all';
  bool _busy = false;

  bool get _embedded => widget.embedded;

  List<Map<String, dynamic>> _rides(AppStore store) => store.rideVendorPast
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _busy = true);
    await context.read<AppStore>().loadRideConsole();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final body = _HistoryBody(
      rider: true,
      filter: _filter,
      busy: _busy,
      onFilter: (f) => setState(() => _filter = f),
      rides: _rides(context.watch<AppStore>()),
      onRefresh: _load,
      embedded: _embedded,
    );
    // _HistoryBody builds its own Scaffold when it is not embedded.
    return body;
  }
}

// ---------------------------------------------------------------- body

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.rider,
    required this.filter,
    required this.busy,
    required this.onFilter,
    required this.rides,
    required this.onRefresh,
    this.embedded = false,
  });

  final bool rider;
  final bool embedded;
  final String filter;
  final bool busy;
  final ValueChanged<String> onFilter;
  final List<Map<String, dynamic>> rides;
  final Future<void> Function() onRefresh;

  static const _filters = <(String, String)>[
    ('all', 'All'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
    ('rejected', 'No rider'),
  ];

  @override
  Widget build(BuildContext context) {
    final shown = rides.where((r) {
      if (filter == 'all') return true;
      return '${r['status']}' == filter;
    }).toList()
      ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));

    if (embedded) {
      return RefreshIndicator(
        color: AppColors.red,
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          children: [
            _filterRow(),
            const SizedBox(height: 14),
            ..._cards(shown, busy),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: RideColors.bg,
      appBar: AppBar(
        backgroundColor: RideColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          onPressed: () => Navigator.pop(context),
        ),
        title: RideLabel(rider ? 'MY RIDES · PARTNER' : 'MY RIDES'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: AppColors.red,
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
          children: [
            _filterRow(),
            const SizedBox(height: 14),
            ..._cards(shown, busy),
          ],
        ),
      ),
    );
  }

  Widget _filterRow() => SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _filters.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final f = _filters[i];
            final on = filter == f.$1;
            return GestureDetector(
              onTap: () => onFilter(f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? AppColors.red : const Color(0xFF131313),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: on ? AppColors.red : RideColors.line),
                ),
                child: Text(f.$2,
                    style: TextStyle(
                        color: on ? Colors.white : const Color(0xFF9E9E9E),
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            );
          },
        ),
      );

  List<Widget> _cards(List<Map<String, dynamic>> shown, bool busy) {
    if (busy && shown.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(
              child: CircularProgressIndicator(color: AppColors.red)),
        )
      ];
    }
    if (shown.isEmpty) {
      return [
        RideEmpty(
          icon: Icons.history_toggle_off_rounded,
          title: 'No rides here yet',
          subtitle: rider
              ? 'Rides you accept and finish will show up here.'
              : 'Your finished and cancelled rides will show up here.',
        )
      ];
    }
    return shown
        .map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _HistoryCard(ride: r, rider: rider),
            ))
        .toList();
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.ride, required this.rider});

  final Map<String, dynamic> ride;
  final bool rider;

  Color _statusColor(String s) => switch (s) {
        'completed' => RideColors.mint,
        'cancelled' => const Color(0xFF8A8A8A),
        'rejected' => RideColors.amber,
        _ => AppColors.red,
      };

  String _statusText(String s) => switch (s) {
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        'rejected' => 'No rider',
        'requested' => 'Searching',
        'accepted' => 'Accepted',
        'paid' => 'Paid',
        'arrived' => 'Arrived',
        'ongoing' => 'On going',
        _ => s,
      };

  String _when() {
    final raw = '${ride['scheduled_at'] ?? ride['created_at'] ?? ''}';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} · '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final status = '${ride['status']}';
    final fare = ((ride['total'] as num?)?.toDouble() ?? 0);
    final km = ((ride['distance_km'] as num?)?.toDouble() ?? 0);
    return RideGlass(
      radius: 18,
      onTap: () => _openDetails(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RideTimeline(),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${ride['pickup_text']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 9),
                Text('${ride['drop_text']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    RideChip(
                        label: _statusText(status),
                        color: _statusColor(status)),
                    RideChip(
                        icon: Icons.straighten_rounded,
                        label: '${km.toStringAsFixed(1)} km'),
                    if ('${ride['vehicle_label']}'.isNotEmpty)
                      RideChip(label: '${ride['vehicle_label']}',
                          color: rideVehicleTint('${ride['vehicle_type']}')),
                    if (_when().isNotEmpty)
                      RideChip(icon: Icons.schedule_rounded, label: _when()),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${fare.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              if (!rider && '${ride['rider_name']}'.isNotEmpty)
                SizedBox(
                  width: 96,
                  child: Text('${ride['rider_name']}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF8A8A8A), fontSize: 11)),
                ),
              if (rider && '${ride['student_name']}'.isNotEmpty)
                SizedBox(
                  width: 96,
                  child: Text('${ride['student_name']}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF8A8A8A), fontSize: 11)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RideSheetShell(
        initial: 0.55,
        minHeight: 0.32,
        child: _HistoryDetails(ride: ride, rider: rider),
      ),
    );
  }
}

class _HistoryDetails extends StatelessWidget {
  const _HistoryDetails({required this.ride, required this.rider});

  final Map<String, dynamic> ride;
  final bool rider;

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text(k,
                  style: const TextStyle(
                      color: Color(0xFF7A7A7A), fontSize: 12)),
            ),
            Expanded(
              child: Text(v,
                  style: TextStyle(
                      color: color ?? Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final fare = ((ride['total'] as num?)?.toDouble() ?? 0);
    final paid = ((ride['amount_paid'] as num?)?.toDouble() ?? 0);
    final due = ((ride['balance_due'] as num?)?.toDouble() ?? 0);
    final mode = '${ride['payment_mode']}';
    final txn = '${ride['txn_first'] ?? ''}';
    final txn2 = '${ride['txn_second'] ?? ''}';
    final pax = (ride['pax'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.red.withOpacity(.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.red.withOpacity(.35)),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: AppColors.red, size: 25),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text('₹${fare.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('${ride['vehicle_label']} · '
              '${((ride['distance_km'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} km',
              style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 12)),
        ),
        const SizedBox(height: 18),
        Container(height: 1, color: RideColors.line),
        _row('Ride code', '${ride['ride_code']}'),
        _row('From', '${ride['pickup_text']}'),
        _row('To', '${ride['drop_text']}'),
        _row('Booked for',
            '${ride['scheduled_at'] ?? ride['created_at'] ?? ''}'.replaceFirst('T', ' · ').split('.').first),
        _row('Status', '${ride['status']}'),
        if (!rider && '${ride['rider_name']}'.isNotEmpty)
          _row('Your rider', '${ride['rider_name']}'),
        if (rider && '${ride['student_name']}'.isNotEmpty)
          _row('Passenger', '${ride['student_name']}'),
        _row('Payment',
            mode == 'split' ? '50-50 split' : (mode.isEmpty ? '—' : 'Full'),
            color: mode == 'split' ? RideColors.amber : RideColors.mint),
        _row('Paid', '₹${paid.toStringAsFixed(2)}',
            color: RideColors.mint),
        if (due > 0)
          _row('Was due', '₹${due.toStringAsFixed(2)}',
              color: RideColors.amber),
        if (txn.isNotEmpty) _row('Txn id', txn),
        if (txn2.isNotEmpty) _row('Second txn', txn2),
        if (pax.isNotEmpty)
          _row('Split with',
              pax.map((p) => '${(p as Map)['name']} ₹${(p['amount'] as num).toStringAsFixed(0)}').join(', ')),
        if ('${ride['notes']}'.isNotEmpty) _row('Note', '${ride['notes']}'),
        const SizedBox(height: 16),
        if (!rider)
          RideButton(
            label: 'BOOK THIS AGAIN',
            icon: Icons.repeat_rounded,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const RideHomeScreen()));
            },
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}
