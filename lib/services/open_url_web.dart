// ignore: deprecated_member_use
import 'dart:html' as html;

/// Web: naya tab mein URL kholo. Returns null (toast ki zaroorat nahi).
Future<String?> openExternalUrl(String url) async {
  html.window.open(url, '_blank');
  return null;
}
