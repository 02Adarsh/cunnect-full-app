import 'package:flutter/services.dart';

const _dl = MethodChannel('cunnect/autostart');

/// ⭐ APK downloads inside the app (DownloadManager) — no browser, no GitHub UI
Future<bool> downloadApk(String url) async {
  try {
    final ok = await _dl.invokeMethod('downloadApk', {'url': url});
    return ok == true;
  } catch (_) {
    return false;
  }
}
