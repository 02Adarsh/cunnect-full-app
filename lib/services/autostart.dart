import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'local_store.dart';

const _ch = MethodChannel('cunnect/autostart');

/// ⭐ Ek baar Autostart/battery permission prompt — instant notifications
Future<void> promptAutostartOnce(BuildContext context) async {
  if (LocalStore.get('autostart_asked') == '1') return;
  LocalStore.set('autostart_asked', '1');
  try {
    final open = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
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
