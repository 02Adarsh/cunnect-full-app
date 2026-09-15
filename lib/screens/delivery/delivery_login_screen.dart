import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'delivery_dashboard_screen.dart';

/// Same centered card as delivery_login.html.
class DeliveryLoginScreen extends StatefulWidget {
  const DeliveryLoginScreen({super.key});

  @override
  State<DeliveryLoginScreen> createState() => _DeliveryLoginScreenState();
}

class _DeliveryLoginScreenState extends State<DeliveryLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.85, -0.86),
            radius: 0.55,
            colors: [Color(0x2BF10B1D), Colors.transparent],
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
                    color: const Color(0xF5121212),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF2B2B2B)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(.55), blurRadius: 55, offset: const Offset(0, 18)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Column(
                          children: [
                            const CunnectWordmark(fontSize: 30),
                            const SizedBox(height: 7),
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
                                  const Text('DELIVERY PARTNER',
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
                      const SizedBox(height: 33),
                      if (_error != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 17),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0x1FF10B1D),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: const Color(0x8CF10B1D)),
                          ),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFFFABB2), fontSize: 12, height: 1.4)),
                        ),
                      const Text('Delivery Login',
                          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 7),
                      const Text(
                        'Sign in to collect ready orders and verify delivery OTPs.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.45),
                      ),
                      const SizedBox(height: 24),
                      const Text('Delivery Mobile Number',
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
                      const SizedBox(height: 24),
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
                          ),
                          child: const Text('Login to Delivery Dashboard'),
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
    );
  }

  Future<void> _login() async {
    final store = context.read<AppStore>();
    final result = await store.deliveryLogin(_phoneController.text, _passwordController.text);
    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DeliveryDashboardScreen()));
    } else {
      setState(() => _error = result.message);
    }
  }
}
