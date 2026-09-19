import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// ⭐ Inline feed video (mobile) — keeps the ORIGINAL aspect ratio of the
/// uploaded video, tap to play/pause, small progress line at the bottom.
///
/// ⭐ v62: [onTap] overrides the default play/pause tap (dashboard banner
/// uses this to open the lightbox), [autoplay]/[muted] give banner-style
/// silent autoplay.
Widget feedVideo(String url,
        {VoidCallback? onTap, bool autoplay = false, bool muted = false}) =>
    _FeedVideo(url: url, onTap: onTap, autoplay: autoplay, muted: muted);

class _FeedVideo extends StatefulWidget {
  final String url;
  final VoidCallback? onTap;
  final bool autoplay;
  final bool muted;

  const _FeedVideo(
      {required this.url, this.onTap, this.autoplay = false,
      this.muted = false});

  @override
  State<_FeedVideo> createState() => _FeedVideoState();
}

class _FeedVideoState extends State<_FeedVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      c.setLooping(true);
      if (widget.muted) c.setVolume(0);
      if (widget.autoplay) c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: const Color(0xFF0D0D0D),
          alignment: Alignment.center,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_off_outlined,
                  size: 32, color: Color(0xFF5A5A5A)),
              SizedBox(height: 6),
              Text('Video could not be loaded',
                  style: TextStyle(color: Color(0xFF6E6E6E), fontSize: 11)),
            ],
          ),
        ),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: const Color(0xFF0D0D0D),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFFF10B1D)),
          ),
        ),
      );
    }
    // Original ratio of the uploaded video — never cropped.
    final ratio = c.value.aspectRatio <= 0 ? 16 / 9 : c.value.aspectRatio;
    return GestureDetector(
      // ⭐ v62: when the parent supplies onTap (banner -> lightbox) the
      // tap goes THERE, not to play/pause — this is what makes the
      // dashboard video enlarge on tap.
      onTap: widget.onTap ??
          () {
            setState(() {
              c.value.isPlaying ? c.pause() : c.play();
            });
          },
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(c),
            if (!c.value.isPlaying)
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(.5),
                  border: Border.all(color: const Color(0x66FFFFFF)),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    size: 34, color: Colors.white),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: true,
                padding: EdgeInsets.zero,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFFF10B1D),
                  bufferedColor: Color(0x40FFFFFF),
                  backgroundColor: Color(0x26FFFFFF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
