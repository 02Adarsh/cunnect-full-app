import 'package:flutter/material.dart';

Widget platformVideo(String url, String viewId, bool muted,
    {VoidCallback? onError}) {
  return Container(
    color: const Color(0xFF0A0A0A),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                size: 40, color: Color(0xFF9D9D9D)),
            const SizedBox(height: 10),
            Text('Open this video in a browser:\n$url',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF9D9D9D), fontSize: 11, height: 1.5)),
          ],
        ),
      ),
    ),
  );
}
