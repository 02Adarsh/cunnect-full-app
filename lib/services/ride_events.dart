import 'dart:async';

import 'package:flutter/material.dart';

import 'app_portal.dart';
import '../widgets/ride_event_popup.dart';

/// One notification about a ride (student or ride-partner side).
class RideEvent {
  const RideEvent({
    required this.kind,
    required this.code,
    this.title = '',
    this.body = '',
    this.otp = '',
    this.amount = '',
    this.balance = '',
    this.txn = '',
    this.lat,
    this.lng,
    this.riderSide = false,
    this.portal = 'student',
  });

  /// Machine name: new_request / accepted / rejected / paid / arrived /
  /// started / completed / cancelled / sos / no_rider / location_shared.
  final String kind;
  final String code;
  final String title;
  final String body;
  final String otp;
  final String amount;
  final String balance;
  final String txn;
  final double? lat;
  final double? lng;

  /// True when this event belongs to the ride PARTNER's app.
  final bool riderSide;

  /// Which portal this push was meant for: 'student' or 'rider'.
  /// ⭐ v75: a rider push can never raise a popup inside the student Ride
  /// screen and the other way round (the OTP used to leak into the rider
  /// portal because the same phone carries both accounts).
  final String portal;

  static const _riderOnly = {
    'new_request',
    'payment_received',
    'paid',
    'balance_paid',
    'balance_done',
    'balance_cleared',
    'location_shared',
  };

  factory RideEvent.fromData(
    Map<String, dynamic> d, {
    String title = '',
    String body = '',
    bool riderSide = false,
  }) {
    String s(String k) => '${d[k] ?? ''}';
    final kind = s('event');
    final portalRaw = s('portal').toLowerCase();
    final portal = portalRaw == 'rider' ? 'rider' : 'student';
    double? lat;
    double? lng;
    if (s('lat').isNotEmpty) lat = double.tryParse(s('lat'));
    if (s('lng').isNotEmpty) lng = double.tryParse(s('lng'));
    return RideEvent(
      kind: kind,
      code: s('ride_code'),
      title: title,
      body: body,
      otp: s('otp'),
      amount: s('amount'),
      balance: s('balance'),
      txn: s('txn'),
      lat: lat,
      lng: lng,
      riderSide: riderSide || _riderOnly.contains(kind) || portal == 'rider',
      portal: portal,
    );
  }

  /// Money should only be shown when it carries information.
  String get cleanAmount {
    if (amount.isEmpty) return '';
    final v = double.tryParse(amount);
    if (v == null) return amount;
    if (v <= 0) return '';
    return v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2);
  }

  String get cleanBalance {
    final v = double.tryParse(balance);
    if (v == null || v <= 0) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }
}

/// ⭐ v74: every ride notification lands here first.
///
/// FCM calls [RideEvents.handle] — the event is broadcast on [stream]
/// (so open screens refresh themselves) and a POPUP is raised on top of
/// whatever the user is looking at. Tapping a notification that arrived
/// while the app was closed stashes the event in [pending], and the ride
/// screen shows it as soon as it opens.
class RideEvents {
  RideEvents._();

  static final StreamController<RideEvent> _bus =
      StreamController<RideEvent>.broadcast();

  /// Listen to this to refresh a screen the moment a ride changes.
  static Stream<RideEvent> get stream => _bus.stream;

  static RideEvent? _last;

  /// The most recent ride event (useful right after a cold start).
  static RideEvent? get last => _last;

  static RideEvent? _pending;

  /// An event the user has not seen yet (arrived by tapping a push).
  static RideEvent? get pending => _pending;

  static void clearPending() => _pending = null;

  /// Handle one push payload. [fromTap] is true when the user tapped the
  /// notification instead of receiving it live.
  static Future<void> handle(
    Map<String, dynamic> data, {
    String title = '',
    String body = '',
    BuildContext? context,
    bool fromTap = false,
    bool riderSide = false,
  }) async {
    final kind = '${data['event'] ?? ''}';
    if (kind.isEmpty && '${data['ride_code'] ?? ''}'.isEmpty) return;
    final ev = RideEvent.fromData(data,
        title: title, body: body, riderSide: riderSide);
    _last = ev;
    if (!_bus.isClosed) _bus.add(ev);
    // ⭐ v75: a rider event only pops up inside the RIDE PARTNER portal and
    // a student event only inside the student side. The tray notification
    // is unaffected — that one must work with the screen off.
    if (!ActivePortal.accepts(ev.riderSide ? 'rider' : 'student')) return;
    if (fromTap) {
      _pending = ev; // the ride screen will show it once it is open
      final ctx = context;
      if (ctx != null) {
        // safety net: if no screen claims it, show it from the root
        Future<void>.delayed(const Duration(milliseconds: 1200), () {
          if (!identical(_pending, ev)) return;
          _pending = null;
          show(ctx, ev);
        });
      }
      return;
    }
    // ⭐ a new ride request already raises the partner's own
    // accept/reject popup from the console poller — do not double it.
    if (ev.kind == 'new_request') return;
    final ctx = context;
    if (ctx != null) await show(ctx, ev);
  }

  /// The ride screen calls this — shows the stashed event (once).
  static Future<void> consumePending(BuildContext context) async {
    final ev = _pending;
    if (ev == null) return;
    _pending = null;
    await show(context, ev);
  }

  /// Raise the popup for an event.
  static Future<void> show(BuildContext context, RideEvent ev) async {
    if (!context.mounted) return;
    await RideEventPopup.show(
      context,
      event: ev.kind,
      title: ev.title.isEmpty ? _fallbackTitle(ev.kind) : ev.title,
      message: ev.body.isEmpty ? _fallbackBody(ev.kind) : ev.body,
      code: ev.code,
      otp: ev.otp,
      amount: ev.cleanAmount,
      balance: ev.cleanBalance,
      txn: ev.txn,
      action: _action(ev),
      riderSide: ev.riderSide,
      dismissible: ev.kind != 'new_request',
      lat: ev.lat,
      lng: ev.lng,
    );
  }

  static RideEventAction _action(RideEvent ev) => switch (ev.kind) {
        'new_request' => RideEventAction.accept,
        'payment_received' => RideEventAction.none,
        'confirmed' => RideEventAction.track,
        'accepted' => RideEventAction.pay,
        'rejected' || 'no_rider' || 'cancelled' => RideEventAction.rebook,
        'sos' => RideEventAction.map,
        _ => RideEventAction.track,
      };

  static String _fallbackTitle(String kind) => switch (kind) {
        'new_request' => 'New ride request 🚗',
        'accepted' => 'Rider accepted your ride',
        'rejected' => 'Rider unavailable',
        'no_rider' => 'No rider available right now',
        'paid' => 'Payment received',
        'payment_received' => 'Payment received — confirm it 💸',
        'confirmed' => 'Rider confirmed your payment ✅',
        'payment_done' => 'Payment recorded',
        'arrived' => 'Your rider has arrived',
        'started' => 'Your ride has started',
        'completed' => 'Ride completed',
        'cancelled' => 'Ride cancelled',
        'sos' => 'SOS from a passenger',
        _ => 'CUnnect Ride',
      };

  static String _fallbackBody(String kind) => switch (kind) {
        'new_request' => 'A student needs a ride. Accept before someone else does.',
        'accepted' => 'Complete the payment to confirm your ride.',
        'rejected' || 'no_rider' =>
          'The ride partner is busy at that time. Please book for another slot.',
        'paid' => 'The student has paid for the ride.',
        'payment_received' =>
          'Open My Rides and tap CONFIRM PAYMENT to continue.',
        'confirmed' => 'Your rider verified the payment. Get ready!',
        'arrived' => 'Your rider is at the pickup point.',
        'started' => 'Have a safe trip!',
        'completed' => 'Thanks for riding with CUnnect.',
        'cancelled' => 'This ride has been cancelled.',
        _ => 'Tap to open the ride.',
      };
}
