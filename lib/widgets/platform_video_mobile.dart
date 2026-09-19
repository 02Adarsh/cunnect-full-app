import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// ⭐ v53: one download is shared across ALL screens that show the same
/// video (student/UMS/vendor/admin logins) — if two screens ask at the
/// same moment only one network request happens.
final Map<String, Future<File?>> _videoFetches = {};

/// ⭐ APK/mobile: background video — downloaded ONCE, then it
/// plays from cache (saves Render bandwidth, loads instantly).
Widget platformVideo(String url, String viewId, bool muted,
    {VoidCallback? onError}) {
  if (!(Platform.isAndroid || Platform.isIOS)) {
    return _placeholder(url);
  }
  return _NativeVideo(url: url, muted: muted, onError: onError);
}

Widget _placeholder(String url) {
  return Container(
    color: const Color(0xFF0A0A0A),
    child: Center(
      child: const Icon(Icons.videocam_off_outlined,
          size: 40, color: Color(0xFF9D9D9D)),
    ),
  );
}

class _NativeVideo extends StatefulWidget {
  final String url;
  final bool muted;
  final VoidCallback? onError;

  const _NativeVideo(
      {required this.url, required this.muted, this.onError});

  @override
  State<_NativeVideo> createState() => _NativeVideoState();
}

class _NativeVideoState extends State<_NativeVideo> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<File?> _cachedFile() {
    // ⭐ v53: shared in-flight fetch — never downloads twice.
    return _videoFetches.putIfAbsent(widget.url, () => _fetchOnce());
  }

  Future<File?> _fetchOnce() async {
    try {
      // ⭐ v53: permanent app storage (the temp dir can be wiped by the
      // OS which would force a re-download and burn backend bandwidth).
      final dir = await getApplicationDocumentsDirectory();
      final name = widget.url
          .split('/')
          .last
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final f = File('${dir.path}/cunnect_video_$name');
      if (await f.exists() && (await f.length()) > 100000) {
        return f;
      }
      // ⭐ one-time migration from the old temp-dir cache (no re-download)
      try {
        final tmp = await getTemporaryDirectory();
        final old = File('${tmp.path}/cunnect_video_$name');
        if (await old.exists() && (await old.length()) > 100000) {
          await old.copy(f.path);
          return f;
        }
      } catch (_) {}
      final resp = await http
          .get(Uri.parse(widget.url))
          .timeout(const Duration(seconds: 90));
      if (resp.statusCode == 200 && resp.bodyBytes.length > 100000) {
        await f.writeAsBytes(resp.bodyBytes, flush: true);
        return f;
      }
    } catch (_) {
      _videoFetches.remove(widget.url); // allow a retry next time
    }
    return null;
  }

  Future<void> _init() async {
    try {
      final local = await _cachedFile();
      final c = local != null
          ? VideoPlayerController.file(local)
          : VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(widget.muted ? 0 : 1);
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _c = c);
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
        widget.onError?.call();
      }
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_failed || c == null || !c.value.isInitialized) {
      return _placeholder(widget.url);
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}
