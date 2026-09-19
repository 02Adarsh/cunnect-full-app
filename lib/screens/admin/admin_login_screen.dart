import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'admin_panel_screen.dart';
import '../../widgets/platform_video.dart';

/// Admin panel login — same glass card layout and theme as the partner
/// login. Uses a Django staff/superuser account (username + password).
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await context
        .read<AppStore>()
        .adminLogin(_username.text, _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.success) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminPanelScreen()));
    } else {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ⭐ v53: same background video as the student login — muted,
          // served from the shared on-device cache (single download ever).
          platformVideo(
              '${ApiConfig.baseUrl}/static/images/login_background.mp4',
              'admin-login-bg-video',
              true),
          Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xC9000000), Color(0xA3000000)],
          ),
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.85, -0.86),
              radius: 0.5,
              colors: [Color(0x47F10B1D), Colors.transparent],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(25, 34, 25, 25),
                    decoration: BoxDecoration(
                      color: const Color(0xED121212),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFF2B2B2B)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(.6),
                            blurRadius: 55,
                            offset: const Offset(0, 18)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              const CunnectWordmark(fontSize: 42),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                      color: const Color(0x73F10B1D)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.red,
                                        boxShadow: [
                                          BoxShadow(
                                              color: AppColors.red,
                                              blurRadius: 9)
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('ADMIN PANEL',
                                        style: TextStyle(
                                            color: Color(0xFFFF9CA5),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: .7)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        if (_error != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 17),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0x1AF10B1D),
                              borderRadius: BorderRadius.circular(9),
                              border:
                                  Border.all(color: const Color(0x80F10B1D)),
                            ),
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: Color(0xFFFFABB2),
                                    fontSize: 12,
                                    height: 1.4)),
                          ),
                        const Text('Admin Login',
                            style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.5)),
                        const SizedBox(height: 7),
                        const Text(
                          'Sign in to manage vendors, orders, students and everything else in the app.',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                              height: 1.45),
                        ),
                        const SizedBox(height: 25),
                        const Text('Admin Username',
                            style: TextStyle(
                                color: Color(0xFFC3C3C3),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        TextField(
                          controller: _username,
                          style: const TextStyle(fontSize: 13),
                          decoration: cunnectInputDecoration(
                              placeholder: 'Enter admin username'),
                        ),
                        const SizedBox(height: 16),
                        const Text('Password',
                            style: TextStyle(
                                color: Color(0xFFC3C3C3),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          onSubmitted: (_) => _busy ? null : _login(),
                          style: const TextStyle(fontSize: 13),
                          decoration: cunnectInputDecoration(
                              placeholder: 'Enter your password'),
                        ),
                        const SizedBox(height: 23),
                        SizedBox(
                          width: double.infinity,
                          height: 47,
                          child: ElevatedButton(
                            onPressed: _busy ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.red,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800),
                              elevation: 0,
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Login to Admin Panel'),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Center(
                          child: Text(
                            'Only staff / superuser accounts can sign in here.',
                            style: TextStyle(
                                color: Color(0xFF8F8F8F), fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
          ),
        ],
      ),
    );
  }
}
