import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'app_portal.dart';

/// ⭐ v75: the vendor ring.
///
/// Every partner portal (food, printout, ride) rings NON-STOP for 20
/// seconds the moment new work arrives — an order, a print job or a ride
/// request. Accepting or rejecting stops it at once.
///
/// The tone is `assets/sounds/universfield_new_notification_066_494545.wav`.
/// To use your own sound just drop a file with the SAME name in
/// `assets/sounds/` (and in `android/app/src/main/res/raw/` for the tray
/// notification) — nothing else has to change.
class RingService {
  RingService._();

  /// ⭐ The tone is looked up in this order, so whichever file you drop
  /// into assets/sounds/ (mp3 OR wav) is the one that plays.
  static const String asset =
      'assets/sounds/universfield_new_notification_066_494545.mp3';
  static const List<String> _candidates = [
    'assets/sounds/universfield_new_notification_066_494545.mp3',
    'assets/sounds/universfield_new_notification_066_494545.wav',
    'assets/sounds/universfield_new_notification_066_494545.m4a',
  ];

  static AudioPlayer? _player;
  static Timer? _stopTimer;
  static bool _ringing = false;

  /// Keeps the ring from starting twice for the same order/ride.
  static String? _lastKey;
  static DateTime? _lastAt;

  static bool get isRinging => _ringing;

  /// Ring for [seconds] (default 20). [key] de-duplicates repeated
  /// poll hits for the same order/ride.
  static Future<void> ring({int seconds = 20, String? key}) async {
    if (key != null) {
      final last = _lastAt;
      if (_lastKey == key && last != null &&
          DateTime.now().difference(last) < const Duration(minutes: 3)) {
        return; // already rang for this one
      }
      _lastKey = key;
      _lastAt = DateTime.now();
    }
    await stop();
    try {
      _player ??= AudioPlayer();
      // ⭐ try every supported name — mp3 (your own clip) first, then the
      // bundled placeholder, so the ring never dies silently.
      var loaded = false;
      for (final file in _candidates) {
        try {
          await _player!.setAsset(file);
          loaded = true;
          break;
        } catch (_) {}
      }
      if (!loaded) await _player!.setAsset(asset);
      await _player!.setLoopMode(LoopMode.one);
      await _player!.setVolume(1.0);
      await _player!.play();
      _ringing = true;
      _stopTimer?.cancel();
      _stopTimer = Timer(Duration(seconds: seconds), () => stop());
    } catch (e) {
      debugPrint('[ring] could not play the tone: $e');
    }
  }

  /// Stop immediately — called when the partner accepts or rejects.
  static Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    _ringing = false;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Ring only if this push belongs to the portal on screen.
  static Future<void> ringForPush(
    Map<String, dynamic> data, {
    int seconds = 20,
  }) async {
    final portal = '${data['portal'] ?? ''}';
    if (!ActivePortal.accepts(portal)) return;
    final event = '${data['event'] ?? ''}';
    final title = '${data['title'] ?? ''}'.toLowerCase();
    final isNewWork = event == 'new_request' ||
        event == 'new_order' ||
        event == 'new_print_order' ||
        // ⭐ v79: the one-tap AUTO button — every auto partner rings at
        // the same moment. There is no ride code behind it, so every tap
        // rings again (no de-duplication).
        event == 'auto_call' ||
        title.contains('new order') ||
        title.contains('auto needed') ||
        title.contains('new ride request') ||
        title.contains('new printout');
    if (!isNewWork) return;
    if (event == 'auto_call') {
      await ring(seconds: seconds, key: null);
      return;
    }
    final key = '${data['order_id'] ?? ''}'
        '${data['ride_code'] ?? ''}'
        '${data['order_number'] ?? ''}';
    await ring(seconds: seconds, key: key.isEmpty ? null : key);
  }
}
