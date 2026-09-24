import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import 'student_login_screen.dart';

/// ⭐ v63: IN-APP password reset — opened by the cunnect://reset deep
/// link from the "Forgot password" email. The user sets the new
/// password right here and is dropped on the login screen. No website.
class ResetPasswordScreen extends StatefulWidget {
  final String uidb64;
  final String token;

  const ResetPasswordScreen(
      {super.key, required this.uidb64, required this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _show1 = false;
  bool _show2 = false;
  bool _busy = false;
  bool _done = false;
  String? _error;
  String _userId = '';

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final p1 = _p1.text;
    final p2 = _p2.text;
    if (p1.length < 6) {
      setState(
          () => _error = 'Keep the password at least 6 characters long.');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await context
        .read<AppStore>()
        .authResetLinkPassword(widget.uidb64, widget.token, p1);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res['error'] != null) {
        _error = '${res['error']}';
      } else {
        _done = true;
        _userId = '${res['user_id'] ?? ''}';
      }
    });
  }

  InputDecoration _dec(String hint, bool shown, VoidCallback onEye) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6E6E6E), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF0D0D0D),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xFF303030)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: AppColors.red),
        ),
        suffixIcon: IconButton(
          onPressed: onEye,
          icon: Icon(shown ? Icons.visibility_off : Icons.visibility,
              size: 18, color: const Color(0xFF7A7A7A)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _done ? _successCard() : _formCard(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() => RichText(
        text: const TextSpan(
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              fontFamily: 'Poppins'),
          children: [
            TextSpan(text: 'CU', style: TextStyle(color: Colors.white)),
            TextSpan(text: 'nnect', style: TextStyle(color: AppColors.red)),
          ],
        ),
      );

  Widget _formCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _logo(),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x8CF10B1D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🔐 Set a new password',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                  'You arrived here from the reset email. Choose a new '
                  'password for your CUnnect account below.',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: 11.5, height: 1.5)),
              const SizedBox(height: 18),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x1FF10B1D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x59F10B1D)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Color(0xFFFF8791),
                          fontSize: 11.5,
                          height: 1.4)),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _p1,
                obscureText: !_show1,
                style: const TextStyle(fontSize: 13.5),
                decoration: _dec('New password', _show1,
                    () => setState(() => _show1 = !_show1)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _p2,
                obscureText: !_show2,
                style: const TextStyle(fontSize: 13.5),
                decoration: _dec('Confirm new password', _show2,
                    () => setState(() => _show2 = !_show2)),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('RESET PASSWORD'),
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text('Minimum 6 characters.',
                    style: TextStyle(
                        color: Color(0xFF7A7A7A), fontSize: 10.5)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _successCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _logo(),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x7338B765)),
          ),
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x1738B765),
                ),
                child: const Center(
                    child: Icon(Icons.check_rounded,
                        size: 34, color: Color(0xFF7ED98B))),
              ),
              const SizedBox(height: 14),
              const Text('Password changed!',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                  _userId.isEmpty
                      ? 'Your new password is active. Log in with it now.'
                      : 'Your new password for $_userId is active. '
                          'Log in with it now.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 12, height: 1.5)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    // Straight to login — clear everything above it.
                    Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (_) => const StudentLoginScreen()),
                        (route) => false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('GO TO LOGIN'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
