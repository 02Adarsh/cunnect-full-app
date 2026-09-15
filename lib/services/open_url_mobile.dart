import 'package:url_launcher/url_launcher.dart';

/// ⭐ APK/mobile: external browser me link kholo (null = koi toast nahi).
Future<String?> openExternalUrl(String url) async {
  try {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    return ok ? null : 'Could not open the link';
  } catch (_) {
    return 'Could not open the link';
  }
}
