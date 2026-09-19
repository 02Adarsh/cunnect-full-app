import 'package:flutter/material.dart';

/// Web/desktop fallback — a simple placeholder card.
Widget feedVideo(String url,
    {VoidCallback? onTap, bool autoplay = false, bool muted = false}) {
  return GestureDetector(
    onTap: onTap,
    child: AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: const Color(0xFF0D0D0D),
        alignment: Alignment.center,
        child: const Icon(Icons.play_circle_outline,
            size: 42, color: Color(0xFF5A5A5A)),
      ),
    ),
  );
}
