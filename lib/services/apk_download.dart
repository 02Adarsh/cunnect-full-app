
import 'dart:async';

import 'package:flutter/services.dart';

const _dl = MethodChannel('cunnect/autostart');
const _events = EventChannel('cunnect/apk_progress');

/// ⭐ v85: APK download inside the app (DownloadManager) with live
/// progress. No browser, no GitHub UI. When the file lands the native
/// side opens the package installer automatically.
///
/// [onProgress] receives (0.0..1.0, status). A negative first value
/// means "indeterminate / size unknown".
Future<bool> downloadApk(
  String url, {
  void Function(double progress, String status)? onProgress,
}) async {
  StreamSubscription? sub;
  try {
    if (onProgress != null) {
      sub = _events.receiveBroadcastStream().listen((raw) {
        try {
          final m = Map<String, dynamic>.from(raw as Map);
          final p = (m['progress'] as num?)?.toDouble() ?? -1.0;
          final st = '${m['status'] ?? ''}';
          onProgress(p, st);
        } catch (_) {}
      });
    }
    final ok = await _dl.invokeMethod('downloadApk', {'url': url});
    return ok == true;
  } catch (_) {
    return false;
  } finally {
    await sub?.cancel();
  }
}
