// ignore: deprecated_member_use
import 'dart:html' as html;

/// Web: open the URL in a new tab. Returns null (no toast needed).
Future<String?> openExternalUrl(String url) async {
  html.window.open(url, '_blank');
  return null;
}
