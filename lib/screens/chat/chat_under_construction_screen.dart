import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/platform_video.dart';

/// ⭐ Chat under construction — sirf full-screen background video
/// (sound ke saath, koi mute option nahi) + back button. Koi extra
/// text/button nahi. Video na ho to chhota sa fallback message.
class ChatUnderConstructionScreen extends StatefulWidget {
  const ChatUnderConstructionScreen({super.key});

  @override
  State<ChatUnderConstructionScreen> createState() =>
      _ChatUnderConstructionScreenState();
}

class _ChatUnderConstructionScreenState
    extends State<ChatUnderConstructionScreen> {
  bool _videoError = false;

  String get _videoUrl =>
      '${ApiConfig.baseUrl}/static/images/chat_under_construction.mp4';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!_videoError)
            platformVideo(_videoUrl, 'uc-video', false, onError: () {
              if (mounted) setState(() => _videoError = true);
            })
          else
            const Center(
              child: Text('🚧 CHAT UNDER CONSTRUCTION 🚧',
                  style: TextStyle(
                      color: Color(0xFF8F8F8F),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5)),
            ),
          // back
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            left: 6,
            child: IconButton(
              icon: const Text('‹',
                  style: TextStyle(color: Colors.white, fontSize: 26, height: 1)),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
