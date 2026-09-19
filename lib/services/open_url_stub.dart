import 'package:flutter/services.dart';

/// Non-web fallback: copy the link to the clipboard so the user can open it in a browser.
/// Returns a toast message (null = no toast needed).
Future<String?> openExternalUrl(String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  return 'Link copied — paste it in your browser';
}
