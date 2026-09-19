import 'package:url_launcher/url_launcher.dart';

/// APK/mobile: open the link in an external app (null = no error toast).
/// Tries the external browser first, then falls back to the platform
/// default handler so documents/downloads always open.
Future<String?> openExternalUrl(String url) async {
  final uri = Uri.parse(url);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok) return null;
  } catch (_) {}
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    return ok ? null : 'Could not open the link';
  } catch (_) {
    return 'Could not open the link';
  }
}
