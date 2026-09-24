import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'local_store.dart';

const _ch = MethodChannel('cunnect/autostart');

/// ⭐ One-time Autostart/battery permission prompt — instant notifications
/// ⭐ v63: Android-only (OEM autostart menus don't exist on iOS/web).
Future<void> promptAutostartOnce(BuildContext context) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  if (LocalStore.get('autostart_asked') == '1') return;
  LocalStore.set('autostart_asked', '1');
  try {
    final open = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF101010),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Allow notification permission',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open Settings',
                  style: TextStyle(color: Color(0xFFFF7782)))),
        ],
      ),
    );
    if (open == true) {
      await _ch.invokeMethod('openAutostart');
    }
  } catch (_) {}
}
