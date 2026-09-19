import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/local_store.dart';

/// ⭐ v73: the BROADCAST card.
///
/// Tapping a broadcast notification opens the app and this card appears
/// on the home page: a plain BLACK box, centred, with equal space on
/// opposite sides, sized exactly to the length of the message.
/// Everything behind it is dimmed + slightly blurred, and touching
/// anywhere OUTSIDE the box dismisses it.
class BroadcastCard extends StatelessWidget {
  final String title;
  final String message;

  const BroadcastCard({super.key, required this.title, required this.message});

  /// Shows the card once and clears the pending flag.
  static void showIfPending(BuildContext context) {
    final pending = LocalStorePending.pending;
    if (!pending) return;
    final title = LocalStorePending.title;
    final body = LocalStorePending.body;
    LocalStorePending.clear();
    if (title.trim().isEmpty && body.trim().isEmpty) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'broadcast',
      barrierColor: Colors.black.withOpacity(.45),
      transitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (_, __, ___) =>
          BroadcastCard(title: title, message: body),
      transitionBuilder: (_, anim, ___, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return GestureDetector(
      // ⭐ touch anywhere OUTSIDE the box -> dismiss
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          color: Colors.black.withOpacity(.28),
          alignment: Alignment.center,
          child: GestureDetector(
            // taps on the box itself do NOT dismiss it
            onTap: () {},
            child: Container(
              // ⭐ equal space on opposite sides, content-sized
              margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 34),
              constraints: BoxConstraints(
                maxWidth: 430,
                maxHeight: size.height - 68,
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.trim().isNotEmpty) ...[
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.35)),
                      const SizedBox(height: 10),
                    ],
                    Text(message,
                        style: const TextStyle(
                            color: Color(0xFFD6D6DA),
                            fontSize: 13,
                            height: 1.6)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Tiny typed wrapper around the pending-broadcast keys.
class LocalStorePending {
  LocalStorePending._();

  static bool get pending => LocalStore.get('bc_pending') == '1';
  static String get title => LocalStore.get('bc_title') ?? '';
  static String get body => LocalStore.get('bc_body') ?? '';

  static void clear() => LocalStore.set('bc_pending', '0');
}
