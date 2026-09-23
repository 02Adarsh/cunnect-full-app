import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../screens/ride/ride_home_screen.dart';
import '../screens/ride/auto_console_screen.dart';
import '../screens/ride/ride_tracking_screen.dart';
import '../screens/ride/rider_console_screen.dart';
import '../services/app_store.dart';
import '../services/open_url_stub.dart'
    if (dart.library.html) '../services/open_url_web.dart'
    if (dart.library.io) '../services/open_url_mobile.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart' show showCunnectToast;
import 'ride_ui.dart';

/// What the popup's main button should do.
enum RideEventAction { none, pay, track, rebook, accept, reject, map }

/// ⭐ v74: the in-app POPUP that rides on top of whatever the user is
/// doing — a ride request for the partner, "your rider accepted, pay
/// now" for the student, the OTP when the rider arrives, and so on.
///
/// It appears whether the screen is ON or OFF: with the screen off FCM
/// raises the system notification, and the moment the app is opened
/// (or if it was already open) this popup is shown on top.
class RideEventPopup extends StatelessWidget {
  const RideEventPopup({
    super.key,
    required this.event,
    required this.title,
    required this.message,
    this.code = '',
    this.otp = '',
    this.amount = '',
    this.balance = '',
    this.txn = '',
    this.action = RideEventAction.none,
    this.riderSide = false,
    this.dismissible = true,
    this.lat,
    this.lng,
  });

  /// Machine name of the event (accepted / paid / arrived / ...).
  final String event;
  final String title;
  final String message;
  final String code;
  final String otp;
  final String amount;
  final String balance;
  final String txn;
  final RideEventAction action;
  final bool riderSide;
  final bool dismissible;
  final double? lat;
  final double? lng;

  /// Show the popup for one push payload.
  static Future<void> show(
    BuildContext context, {
    required String event,
    required String title,
    required String message,
    String code = '',
    String otp = '',
    String amount = '',
    String balance = '',
    String txn = '',
    RideEventAction action = RideEventAction.none,
    bool riderSide = false,
    bool dismissible = true,
    double? lat,
    double? lng,
    bool allowStacked = false,
  }) async {
    if (!allowStacked && _open) return; // never stack popups
    _open = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: dismissible,
        builder: (_) => RideEventPopup(
          event: event,
          title: title,
          message: message,
          code: code,
          otp: otp,
          amount: amount,
          balance: balance,
          txn: txn,
          action: action,
          riderSide: riderSide,
          dismissible: dismissible,
          lat: lat,
          lng: lng,
        ),
      );
    } finally {
      _open = false;
    }
  }

  static bool _open = false;

  // ⭐ v77: red / black / white only — no green or neon anywhere.
  Color get _tint => switch (event) {
        'accepted' || 'payment_done' || 'balance_done' || 'started' ||
        'balance_paid' || 'balance_cleared' || 'paid' =>
          RideColors.white,
        'arrived' || 'completed' => RideColors.soft,
        'rejected' || 'no_rider' || 'cancelled' => AppColors.muted,
        'sos' || 'new_request' => AppColors.red,
        _ => AppColors.red,
      };

  IconData get _icon => switch (event) {
        'accepted' => Icons.how_to_reg_rounded,
        'rejected' || 'no_rider' => Icons.do_not_disturb_on_rounded,
        'paid' || 'payment_done' || 'balance_paid' || 'balance_done' ||
        'balance_cleared' =>
          Icons.currency_rupee_rounded,
        'arrived' => Icons.pin_drop_rounded,
        'started' => Icons.play_circle_rounded,
        'completed' => Icons.flag_rounded,
        'cancelled' => Icons.cancel_rounded,
        'new_request' => Icons.directions_car_rounded,
        'sos' => Icons.sos_rounded,
        _ => Icons.notifications_active_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: dismissible,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF101010),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _tint.withOpacity(.35)),
            boxShadow: [
              BoxShadow(
                  color: _tint.withOpacity(.16),
                  blurRadius: 34,
                  spreadRadius: -6),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    _tint.withOpacity(.9),
                    _tint.withOpacity(.15),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _tint.withOpacity(.13),
                        shape: BoxShape.circle,
                        border: Border.all(color: _tint.withOpacity(.35)),
                      ),
                      child: Icon(_icon, size: 27, color: _tint),
                    ),
                    const SizedBox(height: 14),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17.5,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFFB0B0B5),
                            fontSize: 12.8,
                            height: 1.5)),
                    if (otp.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _otpBlock(context),
                    ],
                    if (amount.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _moneyRow(),
                    ],
                    if (txn.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.receipt_long_rounded,
                              size: 13, color: Color(0xFF7A7A7A)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('Txn $txn',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Color(0xFF8A8A8A), fontSize: 11.5)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    _buttons(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moneyRow() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C0C),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: RideColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RideLabel(event == 'paid' ? 'RECEIVED' : 'AMOUNT', size: 9),
                  const SizedBox(height: 3),
                  Text('₹$amount',
                      style: TextStyle(
                          color: _tint,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            if (balance.isNotEmpty && balance != '0' && balance != '0.0') ...[
              Container(width: 1, height: 30, color: RideColors.line),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RideLabel('STILL DUE', size: 9),
                    const SizedBox(height: 3),
                    Text('₹$balance',
                        style: const TextStyle(
                            color: RideColors.amber,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _otpBlock(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C0C),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: RideColors.sky.withOpacity(.35)),
        ),
        child: Column(
          children: [
            RideLabel('SHARE THIS OTP WITH YOUR RIDER', size: 9),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final ch in otp.split(''))
                  Container(
                    width: 42,
                    height: 50,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: RideColors.sky.withOpacity(.4)),
                    ),
                    child: Text(ch,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: otp));
                      if (context.mounted) {
                        showCunnectToast(context, 'OTP copied');
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('COPY',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: RideColors.line),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final text = 'My CUnnect ride OTP is $otp';
                      final url =
                          'https://wa.me/?text=${Uri.encodeComponent(text)}';
                      openExternalUrl(url);
                    },
                    icon: const Icon(Icons.share_rounded, size: 15),
                    label: const Text('SHARE',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: RideColors.sky,
                      side: BorderSide(color: RideColors.sky.withOpacity(.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buttons(BuildContext context) {
    final store = context.read<AppStore>();
    switch (action) {
      case RideEventAction.accept:
        return Row(
          children: [
            Expanded(
              child: RideButton(
                label: 'REJECT',
                filled: false,
                color: const Color(0xFF8A8A8A),
                onTap: () async {
                  Navigator.pop(context);
                  final err = await store.rideVendorAction('reject', code);
                  if (err != null && context.mounted) {
                    showCunnectToast(context, err, error: true);
                  }
                },
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: RideButton(
                label: 'ACCEPT',
                icon: Icons.check_rounded,
                onTap: () async {
                  Navigator.pop(context);
                  final err = await store.rideVendorAction('accept', code);
                  if (err != null && context.mounted) {
                    showCunnectToast(context, err, error: true);
                  } else if (context.mounted) {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const RiderConsoleScreen()));
                  }
                },
              ),
            ),
          ],
        );
      default:
        final label = switch (action) {
          RideEventAction.pay => 'PAY NOW',
          RideEventAction.track => riderSide ? 'OPEN MY RIDE' : 'TRACK RIDE',
          RideEventAction.rebook => 'BOOK ANOTHER TIME',
          RideEventAction.map => 'OPEN MAP',
          _ => 'OK',
        };
        return Column(
          children: [
            RideButton(
              label: label,
              icon: action == RideEventAction.none
                  ? null
                  : Icons.arrow_forward_rounded,
              color: _tint,
              onTap: () => _run(context),
            ),
            const SizedBox(height: 9),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Dismiss',
                  style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 12.5)),
            ),
          ],
        );
    }
  }

  Future<void> _run(BuildContext context) async {
    final nav = Navigator.of(context);
    switch (action) {
      case RideEventAction.map:
        final la = lat, ln = lng;
        if (la != null && ln != null) {
          await openExternalUrl('https://maps.google.com/?q=$la,$ln');
        }
        nav.pop();
        return;
      case RideEventAction.rebook:
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => const RideHomeScreen()));
        return;
      default:
        nav.pop();
        // \u2b50 v81: an AUTO call belongs to the AUTO portal — a car
        // console must never open for it.
        nav.push(MaterialPageRoute(
            builder: (_) => event == 'auto_call'
                ? const AutoConsoleScreen()
                : riderSide
                    ? const RiderConsoleScreen()
                    : RideTrackingScreen(rideCode: code)));
    }
  }
}
