import 'package:flutter/services.dart';

/// Non-web fallback: link clipboard mein copy karo, user browser mein kholega.
/// Returns a toast message (null = no toast needed).
Future<String?> openExternalUrl(String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  return 'Link copied — paste it in your browser';
}
