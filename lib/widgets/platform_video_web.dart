import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// ⭐ Full-screen background video — HTML5. Video me sound hai to
/// sound ke saath chalta hai; koi mute/unmute button nahi. Agar browser
/// autoplay-with-sound block kare to ek baar tap karna padta hai
/// (play button sirf tab dikhta hai).
Widget platformVideo(String url, String viewId, bool muted,
    {VoidCallback? onError}) {
  final el = html.VideoElement()
    ..autoplay = true
    ..loop = true
    ..muted = muted
    ..controls = false
    ..setAttribute('playsinline', 'true')
    ..setAttribute('preload', 'auto');
  el.style
    ..width = '100%'
    ..height = '100%'
    ..objectFit = 'cover'
    ..border = 'none'
    ..background = 'transparent';
  el.append(html.SourceElement()
    ..src = url
    ..type = 'video/mp4');
  if (onError != null) {
    el.onError.listen((_) => onError());
    el.addEventListener('error', (_) => onError());
  }
  ui_web.platformViewRegistry.registerViewFactory(viewId, (_) => el);
  return _VideoWithSound(el: el, viewId: viewId);
}

class _VideoWithSound extends StatefulWidget {
  final html.VideoElement el;
  final String viewId;

  const _VideoWithSound({required this.el, required this.viewId});

  @override
  State<_VideoWithSound> createState() => _VideoWithSoundState();
}

class _VideoWithSoundState extends State<_VideoWithSound> {
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    // Browser ne sound wala autoplay roka? -> play button dikhao.
    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      try {
        if (widget.el.paused) setState(() => _blocked = true);
      } catch (_) {}
    });
  }

  void _startWithSound() {
    try {
      widget.el.muted = false;
      widget.el.play();
    } catch (_) {}
    setState(() => _blocked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: widget.viewId),
        if (_blocked)
          GestureDetector(
            onTap: _startWithSound,
            child: Container(
              color: const Color(0x66000000),
              child: Center(
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: const Color(0xCC141414),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x80FFFFFF)),
                  ),
                  alignment: Alignment.center,
                  child: const Text('▶',
                      style: TextStyle(color: Colors.white, fontSize: 26)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
