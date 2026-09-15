import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import 'food_home_screen.dart';
import 'my_orders_screen.dart';

/// Same centered card layout as order_success.html.
class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final orders = store.recentOrderSuccess;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 390),
              padding: const EdgeInsets.fromLTRB(25, 38, 25, 26),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF2D2D2D)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(.55), blurRadius: 55, offset: const Offset(0, 20)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x2435B766),
                      border: Border.all(color: const Color(0xA635B766)),
                      boxShadow: const [BoxShadow(color: Color(0x2E35B766), blurRadius: 22)],
                    ),
                    alignment: Alignment.center,
                    child: const Text('✓',
                        style: TextStyle(
                            color: Color(0xFF91E9AE), fontSize: 31, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 18),
                  const Text('Order placed!', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    'Your order has been sent to the partner. You will be notified when it is accepted.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFA0A0A0), fontSize: 13, height: 1.45),
                  ),
                  const SizedBox(height: 22),
                  if (orders.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 23),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: const Color(0xFF2D2D2D)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < orders.length; i++)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: i > 0
                                    ? const Border(top: BorderSide(color: Color(0xFF2D2D2D)))
                                    : null,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(orders[i].orderNumber,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 3),
                                        Text(orders[i].vendorName,
                                            style: const TextStyle(
                                                color: AppColors.muted, fontSize: 10.5)),
                                      ],
                                    ),
                                  ),
                                  Text('₹${orders[i].totalAmount.round()}',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (_) => const MyOrdersScreen(mode: 'food')),
                          (route) => route.isFirst),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      child: const Text('Track My Order'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const FoodHomeScreen()),
                        (route) => route.isFirst),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFC7C7C7),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Continue Ordering'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
