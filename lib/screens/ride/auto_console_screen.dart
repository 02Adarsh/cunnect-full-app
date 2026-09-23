import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_portal.dart';
import '../../services/app_store.dart';
import '../../services/ride_events.dart';
import '../../services/ring_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart' show showCunnectToast;

/// ⭐ v81: the AUTO partner's own portal.
///
/// A completely separate account (`vendor_type = "auto"`). He never sees
/// car bookings, fares or OTPs — a student taps AUTO on the Ride screen
/// and every auto partner on duty is alerted here at the same moment.
///
///  * the call rings for 20 seconds, non-stop
///  * ACCEPT / DECLINE — nothing is asked beyond that
///  * nothing about the student is ever shown, before or after accepting
///  * an on-duty switch so he can stop the calls without logging out
class AutoConsoleScreen extends StatefulWidget {
  const AutoConsoleScreen({super.key});

  @override
  State<AutoConsoleScreen> createState() => _AutoConsoleScreenState();
}

class _AutoConsoleScreenState extends State<AutoConsoleScreen> {
  Timer? _poll;
  StreamSubscription<RideEvent>? _sub;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    // ⭐ the ring only sounds while THIS portal is on screen
    ActivePortal.set(AppPortal.auto);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _sub = RideEvents.stream.listen(_onEvent);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    await context.read<AppStore>().loadAutoIncoming();
  }

  void _onEvent(RideEvent ev) {
    if (ev.kind != 'auto_call') return;
    // ⭐ every tap rings again — there is no ride code to de-duplicate on
    RingService.ring(seconds: 20, key: null);
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sub?.cancel();
    RingService.stop();
    super.dispose();
  }

  Future<void> _answer(Map<String, dynamic> call, bool accept) async {
    final id = (call['id'] as num?)?.toInt();
    if (id == null) return;
    setState(() => _busy.add(id));
    RingService.stop();
    final res = await context.read<AppStore>().respondAutoCall(id, accept);
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (res['ok'] != true) {
      showCunnectToast(context, '${res['error']}', error: true);
      return;
    }
    showCunnectToast(context,
        accept ? 'Accepted — head to the main gate' : 'Call declined');
  }

  Future<void> _toggleDuty(bool value) async {
    final ok = await context.read<AppStore>().setAutoOnline(value);
    if (!mounted) return;
    showCunnectToast(context,
        !ok ? 'Could not save that — try again'
            : value
                ? "You're on duty — auto calls will ring"
                : 'Off duty — you will not be called');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final calls = store.autoCalls;
    final recent = store.autoRecent;
    final onDuty = store.autoOnline;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ---------------- header ----------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0x2EF10B1D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x59F10B1D)),
                ),
                child: const Center(
                    child: Text('🛺', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AUTO PORTAL',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .6)),
                    const SizedBox(height: 2),
                    Text(store.vendor.businessName.isEmpty
                        ? 'Auto partner'
                        : store.vendor.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 10.5)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Log out',
                icon: const Icon(Icons.logout_rounded,
                    size: 19, color: Color(0xFF9E9E9E)),
                onPressed: () async {
                  await context.read<AppStore>().vendorLogout();
                },
              ),
            ]),
          ),
          // ---------------- duty switch ----------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                    color: onDuty
                        ? const Color(0x59F10B1D)
                        : const Color(0xFF292929)),
              ),
              child: Row(children: [
                Icon(Icons.circle,
                    size: 9,
                    color: onDuty
                        ? const Color(0xFFF10B1D)
                        : const Color(0xFF5A5A5A)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(onDuty ? 'ON DUTY' : 'OFF DUTY',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5,
                          color: onDuty
                              ? const Color(0xFFF5F5F5)
                              : const Color(0xFF8A8A8A))),
                ),
                Switch(
                  value: onDuty,
                  activeColor: AppColors.red,
                  onChanged: _toggleDuty,
                ),
              ]),
            ),
          ),
          // ---------------- body ----------------
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (calls.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(children: [
                      const Text('🛺', style: TextStyle(fontSize: 30)),
                      const SizedBox(height: 10),
                      Text(
                          onDuty
                              ? 'Waiting for a call.\n\nWhen a student taps AUTO '
                                  'on the Ride screen, this portal rings.'
                              : 'You are off duty.\n\nSwitch ON DUTY to start '
                                  'receiving auto calls.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                              height: 1.5)),
                    ]),
                  ),
                for (final c in calls) _callCard(c),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(children: [
                    const Text('RECENT',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Color(0xFF8A8A8A))),
                    const Spacer(),
                    Text('${store.autoAcceptedToday} accepted today',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 10)),
                  ]),
                  const SizedBox(height: 8),
                  for (final c in recent) _historyRow(c),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// The live call — the only thing that matters while it is ringing.
  Widget _callCard(Map<String, dynamic> c) {
    final id = (c['id'] as num?)?.toInt() ?? 0;
    final busy = _busy.contains(id);
    final when = _timeAgo(c['created_at_iso']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A0E12), Color(0xFF151517)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x80F10B1D), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 0),
            child: Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x29F10B1D),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: const Color(0x80F10B1D)),
                ),
                child: const Text('AUTO CALL',
                    style: TextStyle(
                        color: Color(0xFFFFABB2),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8)),
              ),
              const Spacer(),
              Text(when,
                  style: const TextStyle(
                      color: Color(0xFF8A8A8A), fontSize: 10)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 0),
            child: Row(children: [
              const Text('🛺', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('A student needs an auto\nat the campus main gate',
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        height: 1.35)),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
            child: Row(children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _answer(c, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDDDDDD),
                      side: const BorderSide(color: Color(0xFF3A3A3A)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                    ),
                    child: const Text('DECLINE',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: busy ? null : () => _answer(c, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('ACCEPT',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// ⭐ nothing about the student is ever shown — just what happened.
  Widget _historyRow(Map<String, dynamic> c) {
    final status = '${c['status'] ?? ''}';
    final (label, color) = switch (status) {
      'accepted' => ('ACCEPTED', const Color(0xFFC9C9C9)),
      'declined' => ('DECLINED', const Color(0xFF7A7A7A)),
      'expired' => ('MISSED', const Color(0xFF7A7A7A)),
      _ => ('PENDING', const Color(0xFFF10B1D)),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(children: [
        const Text('🛺', style: TextStyle(fontSize: 15)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Campus main gate',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(_timeAgo(c['created_at_iso']),
                  style: const TextStyle(
                      color: Color(0xFF747474), fontSize: 10)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(.14),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  String _timeAgo(Object? iso) {
    final dt = DateTime.tryParse('$iso');
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${dt.day}/${dt.month} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
