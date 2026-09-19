import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../admin/admin_login_screen.dart';
import '../admin/admin_panel_screen.dart';
import '../support_form_screen.dart';
import 'vendor_shell.dart';
import '../../widgets/platform_video.dart';

/// Same centered glass card layout as vendor_login.html
/// (background video replaced by the same dark + red glow gradient).
class VendorLoginScreen extends StatefulWidget {
  const VendorLoginScreen({super.key});

  @override
  State<VendorLoginScreen> createState() => _VendorLoginScreenState();
}

class _VendorLoginScreenState extends State<VendorLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _remember = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ⭐ v53: same background video as the student login — muted,
          // plays from the shared on-device cache (single download ever).
          platformVideo(
              '${ApiConfig.baseUrl}/static/images/login_background.mp4',
              'vendor-login-bg-video',
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
                            color: Colors.black.withOpacity(.6), blurRadius: 55, offset: const Offset(0, 18)),
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
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(color: const Color(0x73F10B1D)),
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
                                        boxShadow: [BoxShadow(color: AppColors.red, blurRadius: 9)],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('PARTNER PORTAL',
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
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0x1AF10B1D),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: const Color(0x80F10B1D)),
                            ),
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: Color(0xFFFFABB2), fontSize: 12, height: 1.4)),
                          ),
                        const Text('Partner Login',
                            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -.5)),
                        const SizedBox(height: 7),
                        const Text(
                          'Sign in to manage your store, menu and incoming orders.',
                          style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.45),
                        ),
                        const SizedBox(height: 25),
                        const Text('Partner Mobile Number',
                            style: TextStyle(
                                color: Color(0xFFC3C3C3), fontSize: 11.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontSize: 13),
                          decoration: cunnectInputDecoration(placeholder: 'Enter mobile number'),
                        ),
                        const SizedBox(height: 16),
                        const Text('Password',
                            style: TextStyle(
                                color: Color(0xFFC3C3C3), fontSize: 11.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: const TextStyle(fontSize: 13),
                          decoration: cunnectInputDecoration(placeholder: 'Enter your password'),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Checkbox(
                                      value: _remember,
                                      onChanged: (value) =>
                                          setState(() => _remember = value ?? false),
                                      activeColor: AppColors.red,
                                      side: const BorderSide(color: Color(0xFF555555)),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Flexible(
                                    child: Text('Keep me signed in',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                                  ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: InkWell(
                                onTap: () => openForgotPasswordSheet(context),
                                child: const Text('Forgot password?',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Color(0xFFFF7F89), fontSize: 11.5)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 23),
                        SizedBox(
                          width: double.infinity,
                          height: 47,
                          child: ElevatedButton(
                            onPressed: _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.red,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                              elevation: 0,
                            ),
                            child: const Text('Login to Dashboard'),
                          ),
                        ),
                        const SizedBox(height: 21),
                        Center(
                          child: Text.rich(
                            TextSpan(text: 'Need a partner account? ', children: [
                              TextSpan(
                                  text: 'Contact Us',
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => openCunnectSupportForm(context),
                                  style: const TextStyle(
                                      color: Color(0xFFEFEFEF), fontWeight: FontWeight.w700)),
                            ]),
                            style: const TextStyle(color: Color(0xFF8F8F8F), fontSize: 11.5),
                          ),
                        ),
                        const SizedBox(height: 13),
                        // ⭐ Admin panel entry — same portal, separate login.
                        Center(
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => ApiConfig.adminToken != null
                                      ? const AdminPanelScreen()
                                      : const AdminLoginScreen()));
                            },
                            borderRadius: BorderRadius.circular(99),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                border:
                                    Border.all(color: const Color(0xFF333333)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.admin_panel_settings_outlined,
                                      size: 13, color: Color(0xFF9A9A9A)),
                                  SizedBox(width: 5),
                                  Text('Admin Panel',
                                      style: TextStyle(
                                          color: Color(0xFF9A9A9A),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
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

  Future<void> _login() async {
    final store = context.read<AppStore>();
    final result = await store.vendorLogin(_phoneController.text, _passwordController.text);
    if (!mounted) return;
    if (result.success) {
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => const VendorShell()));
    } else {
      setState(() => _error = result.message);
    }
  }
}
