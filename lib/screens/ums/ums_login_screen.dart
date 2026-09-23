import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../services/open_url.dart';
import '../../widgets/common.dart';
import '../support_form_screen.dart';
import 'ums_dashboard_screen.dart';
import '../../widgets/platform_video.dart';

/// CUIMS login — scraper_app ke login.html + enter_password.html ka
/// exact Flutter mirror: black bg + glass card, CU-wordmark glow,
/// stage1 (UID → NEXT) → stage2 (UID verified badge + password
/// show/hide + captcha box) → dashboard.
class UmsLoginScreen extends StatefulWidget {
  const UmsLoginScreen({super.key});

  @override
  State<UmsLoginScreen> createState() => _UmsLoginScreenState();
}

class _UmsLoginScreenState extends State<UmsLoginScreen> {
  static const _red = Color(0xFFEF1022);
  static const _line = Color(0x1FFFFFFF);
  static const _card = Color(0xE8131313);

  final _uidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();

  String? _error;
  bool _busy = false;
  bool _stage1Done = false;
  bool _showPw = false;
  String? _captchaB64;
  String _stage1Uid = '';

  @override
  void initState() {
    super.initState();
    // ⭐ v62: saved UMS session on the backend? Restore it silently and
    // jump straight to the dashboard — no re-login, no manual refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<AppStore>();
      final restored = await store.umsAutoRestore();
      if (restored && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => const UmsDashboardScreen()));
      }
    });
  }

  @override
  void dispose() {
    _uidController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  Future<void> _startStage1() async {
    final uid = _uidController.text.trim();
    if (uid.isEmpty) {
      setState(() => _error = 'Enter your CUIMS UID.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = context.read<AppStore>();
    final data = await store.umsStage1(uid);
    if (!mounted) return;
    if (data['error'] != null) {
      setState(() {
        _busy = false;
        _error = data['error'] as String;
      });
      return;
    }
    setState(() {
      _busy = false;
      _stage1Done = true;
      _stage1Uid = uid;
      _captchaB64 = data['captcha_b64'] as String?;
    });
  }

  Future<void> _submitStage2() async {
    final password = _passwordController.text;
    final captcha = _captchaController.text.trim();
    if (password.isEmpty || (_captchaB64 != null && captcha.isEmpty)) {
      setState(() => _error = 'Enter both password and captcha.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = context.read<AppStore>();
    final data = await store.umsStage2(_stage1Uid, password, captcha);
    if (!mounted) return;
    if (data['error'] != null) {
      final fresh = await store.umsStage1(_stage1Uid);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = data['error'] as String;
        _captchaB64 = fresh['captcha_b64'] as String?;
        _captchaController.clear();
      });
      return;
    }
    await store.loadUmsDashboard();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const UmsDashboardScreen()));
  }

  Future<void> _demoLogin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = context.read<AppStore>();
    final data = await store.umsDemoLogin();
    if (!mounted) return;
    if (data['error'] != null) {
      setState(() {
        _busy = false;
        _error = data['error'] as String;
      });
      return;
    }
    await store.loadUmsDashboard();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const UmsDashboardScreen()));
  }

  Widget _mono(String text, double size,
          {Color color = const Color(0xFF777777),
          FontWeight w = FontWeight.w700,
          double ls = 1.4}) =>
      Text(text,
          style: TextStyle(
              fontFamily: 'monospace',
              fontSize: size,
              color: color,
              fontWeight: w,
              letterSpacing: ls));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Stack(
        children: [
          // ⭐ v53: same background video as the student login — plays
          // muted from the on-device cache (downloaded once, ever).
          Positioned.fill(
            child: platformVideo(
                '${ApiConfig.baseUrl}/static/images/login_background.mp4',
                'ums-login-bg-video',
                true),
          ),
          // dark scrim so the form stays perfectly readable
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xD90A0A0A),
                  Color(0xE6050505),
                  Color(0xF2000000),
                ],
              ),
            ),
          ),
          Positioned(
            top: -120,
            right: -140,
            child: Container(
              width: 360,
              height: 360,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Color(0x2EEF1022), blurRadius: 160),
                ],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Container(
                  padding:
                      const EdgeInsets.fromLTRB(25, 30, 25, 25),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: _line),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x8C000000),
                          blurRadius: 55,
                          offset: Offset(0, 18)),
                    ],
                  ),
                  child: _stage1Done ? _stage2Form() : _stage1Form(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════ STAGE 1 — login.html ══════════
  Widget _stage1Form() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // wordmark
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: 'CU',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -3,
                  color: _red,
                  shadows: const [
                    Shadow(color: Color(0x73FF1022), blurRadius: 20),
                    Shadow(color: Color(0x2EFF1022), blurRadius: 60),
                  ],
                ),
              ),
              const TextSpan(
                text: 'nnect',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -3,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: Color(0x29FFFFFF), blurRadius: 10, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          _mono('YOUR CAMPUS. CONNECTED.', 9,
              color: const Color(0xFFC9C9C9), w: FontWeight.w700, ls: 2),
          const SizedBox(height: 29),
          const Text('LOGIN',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5)),
          const SizedBox(height: 7),
          const Text('Enter your User ID to continue',
              style: TextStyle(color: Color(0xFFA4A4A4), fontSize: 12)),
          const SizedBox(height: 23),
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x1FEF1022),
                border: Border.all(color: const Color(0x80EF1022)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFFFB0B7), fontSize: 12, height: 1.35)),
            ),
            const SizedBox(height: 16),
          ],
          _field(
            controller: _uidController,
            placeholder: 'Enter User ID',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 16),
          _redButton('NEXT', _busy && !_stage1Done, _startStage1),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Container(height: 1, color: _line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _mono('OR', 10, color: const Color(0xFF9A9A9A)),
              ),
              Expanded(child: Container(height: 1, color: _line)),
            ],
          ),

        ],
      );

  // ══════════ STAGE 2 — enter_password.html ══════════
  Widget _stage2Form() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: 'CU',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -3,
                  color: _red,
                  shadows: const [
                    Shadow(color: Color(0x73FF1022), blurRadius: 20),
                  ],
                ),
              ),
              const TextSpan(
                text: 'nnect',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -3,
                  color: Colors.white,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          _mono('YOUR CAMPUS. CONNECTED.', 9,
              color: const Color(0xFFC9C9C9), w: FontWeight.w700, ls: 2),
          const SizedBox(height: 29),
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x1FEF1022),
                border: Border.all(color: const Color(0x80EF1022)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFFFB0B7), fontSize: 12, height: 1.35)),
            ),
            const SizedBox(height: 16),
          ],
          // uid display + verified badge
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0x14EF1022),
              border: Border.all(color: const Color(0x59EF1022)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(_stage1Uid,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .6,
                          color: Color(0xFFFFB0B7))),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x1AF5F5F5),
                    border: Border.all(color: const Color(0x4DF5F5F5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 10, color: Color(0xFFF5F5F5)),
                      const SizedBox(width: 5),
                      _mono('VERIFIED', 8,
                          color: const Color(0xFFF5F5F5), ls: 1.6),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _field(
            controller: _passwordController,
            placeholder: 'Enter Password',
            obscure: !_showPw,
            trailing: GestureDetector(
              onTap: () => setState(() => _showPw = !_showPw),
              child: _mono(_showPw ? 'HIDE' : 'SHOW', 9,
                  color: const Color(0xFFAAAAAA), ls: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          if (_captchaB64 != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0x14EF1022),
                border: Border.all(color: const Color(0x4DEF1022)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _mono('SECURITY CAPTCHA CODE', 10,
                          color: const Color(0xFF87878D), ls: 1.4),
                      _mono('CASE SENSITIVE', 8,
                          color: const Color(0x99EF1022), ls: 1.8),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: _captchaController,
                          placeholder: 'Solve Captcha',
                          icon: Icons.shield_outlined,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Container(
                        width: 101,
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F2),
                          border:
                              Border.all(color: const Color(0x2EFFFFFF)),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x40000000),
                                blurRadius: 3,
                                offset: Offset(0, 1)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            base64Decode(_captchaB64!),
                            height: 48,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          _redButton('LOGIN', _busy, _submitStage2),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => openCunnectSupportForm(context),
            child: const Text('Forgot Password?',
                style: TextStyle(color: Color(0xFFFF8994), fontSize: 12)),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() {
              _stage1Done = false;
              _error = null;
              _captchaB64 = null;
            }),
            child: _mono('‹ CHANGE UID', 9,
                color: const Color(0xFF9A9A9A), ls: 1.4),
          ),

        ],
      );

  Widget _field({
    required TextEditingController controller,
    required String placeholder,
    IconData? icon,
    Widget? trailing,
    bool obscure = false,
  }) =>
      Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xCC262626),
          border: Border.all(color: const Color(0x1FFFFFFF)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
            hintText: placeholder,
            hintStyle: const TextStyle(color: Color(0xFF999999), fontSize: 13),
            suffixIcon: trailing != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: trailing,
                  )
                : icon != null
                    ? Padding(
                        padding: const EdgeInsets.only(right: 17),
                        child: Icon(icon, size: 17, color: const Color(0xFFAAAAAA)),
                      )
                    : null,
            suffixIconConstraints:
                const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ),
      );

  Widget _redButton(String label, bool busy, VoidCallback onTap) =>
      GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: double.infinity,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: busy ? const Color(0x80EF1022) : _red,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x40EF1022), blurRadius: 20, offset: Offset(0, 9)),
            ],
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Colors.white)),
        ),
      );
}
