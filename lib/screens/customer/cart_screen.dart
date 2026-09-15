import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'checkout_screen.dart';
import 'food_home_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const CunnectHeader(),
          Expanded(child: store.cart.isEmpty
          ? _emptyCart(context)
          : Column(
              children: [
                _heading(store),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 14, 14, 150),
                    children: [
                      for (final cartItem in store.cart)
                        _CartItemRow(cartItem: cartItem, store: store),
                    ],
                  ),
                ),
                _footer(context, store),
              ],
            ),
    ),
        ]),
      ),);
  }

  Widget _heading(AppStore store) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your Cart', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.15)),
          const SizedBox(height: 3),
          Text(
            '${store.cartCount} item${store.cartCount == 1 ? '' : 's'} selected',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, AppStore store) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 12, 14, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: AppColors.footerBg,
        border: Border(top: BorderSide(color: Color(0xFF363636))),
        boxShadow: [BoxShadow(color: Color(0x4D000000), blurRadius: 28, offset: Offset(0, -9))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total amount', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              Text('₹${store.cartTotal.round()}',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CheckoutScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              child: const Text('Proceed to Checkout'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCart(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF353535)),
              ),
              alignment: Alignment.center,
              child: const Text('🛒', style: TextStyle(fontSize: 27)),
            ),
            const SizedBox(height: 16),
            const Text('Your cart is empty',
                style: TextStyle(color: Color(0xFFF4F4F4), fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            const Text('Add something tasty from the menu.',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const FoodHomeScreen()), (route) => route.isFirst),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              child: const Text('Browse Food'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemRow extends StatelessWidget {
  final CartItem cartItem;
  final AppStore store;

  const _CartItemRow({required this.cartItem, required this.store});

  @override
  Widget build(BuildContext context) {
    final item = cartItem.foodItem;

    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: CunnectImage(item.image, width: 68, height: 68, fit: BoxFit.cover),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 3),
                Text('₹${item.price.round()}',
                    style: const TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      height: 29,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF343434)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _qtyButton('−', () => store.updateCartItem(item.id, 'decrease')),
                          SizedBox(
                            width: 24,
                            child: Text('${cartItem.quantity}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          _qtyButton('+', () => store.updateCartItem(item.id, 'increase')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 11),
                    GestureDetector(
                      onTap: () => store.updateCartItem(item.id, 'remove'),
                      child: const Text('Remove',
                          style: TextStyle(
                              color: AppColors.red, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('₹${cartItem.subtotal.round()}',
                style: const TextStyle(color: Color(0xFFE5E5E5), fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 29,
        height: 29,
        child: Center(
          child: Text(label, style: const TextStyle(fontSize: 18, height: 1, color: Colors.white)),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 68,
        height: 68,
        color: const Color(0xFF1F1F1F),
        alignment: Alignment.center,
        child: const Text('🍽️', style: TextStyle(fontSize: 24)),
      );
}
