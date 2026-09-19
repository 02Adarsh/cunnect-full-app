import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../support_form_screen.dart' show openForgotPasswordSheet;

/// ⭐ v66: opened by the cunnect://reset/expired/1 deep link.
///
/// Earlier an expired (or already-used) reset link left the user sitting
/// on a WEBSITE page that just said "expired". Now the link opens the APP
/// and this themed screen sends a fresh link in one tap — the user never
/// has to deal with a browser at all.
class ResetLinkExpiredScreen extends StatelessWidget {
  const ResetLinkExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        backgroundColor: AppColors.page,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('RESET LINK',
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              Container(
                width: 62,
                height: 62,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red.withOpacity(.12),
                  border: Border.all(color: AppColors.red.withOpacity(.45)),
                ),
                child: const Icon(Icons.lock_clock_rounded,
                    color: AppColors.red, size: 28),
              ),
              const SizedBox(height: 22),
              const Text('Link expired',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text(
                'This password reset link is no longer valid — it was '
                'already used, or it is older than 24 hours.',
                style: TextStyle(
                    color: AppColors.muted, fontSize: 13.5, height: 1.55)),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () => openForgotPasswordSheet(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('SEND ME A NEW LINK',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1)),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _backToLogin(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF303030)),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('BACK TO LOGIN',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1)),
                ),
              ),
              const Spacer(),
              const Text(
                'TIP: use the new link within 24 hours — it works once.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }

  void _backToLogin(BuildContext context) {
    // Drop back to whatever the user was on before the link opened.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
