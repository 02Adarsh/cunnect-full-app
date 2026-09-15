import 'package:flutter/material.dart';

import 'platform_video_stub.dart'
    if (dart.library.html) 'platform_video_web.dart'
    if (dart.library.io) 'platform_video_mobile.dart' as impl;

/// ⭐ Full-screen background video — web pe HTML5, APK pe video_player,
/// sound video ka apna (koi mute option nahi).
Widget platformVideo(String url, String viewId, bool muted,
    {VoidCallback? onError}) {
  return impl.platformVideo(url, viewId, muted, onError: onError);
}
