import 'package:flutter/material.dart';

import 'feed_video_stub.dart'
    if (dart.library.io) 'feed_video_mobile.dart' as impl;

/// ⭐ Inline feed video — renders at the video's OWN aspect ratio
/// (16:9, 1:1, 9:16 — whatever was uploaded), tap to play/pause.
///
/// ⭐ v62: [onTap] overrides the default play/pause tap (used by the
/// dashboard banner to open the fullscreen lightbox), [autoplay] starts
/// playback immediately and [muted] silences it (banner-style autoplay).
Widget feedVideo(String url,
        {VoidCallback? onTap, bool autoplay = false, bool muted = false}) =>
    impl.feedVideo(url, onTap: onTap, autoplay: autoplay, muted: muted);
