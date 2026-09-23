import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'vendor_item_form_screen.dart';

/// Manage Menu — same layout as vendor_menu.html.
class VendorMenuScreen extends StatelessWidget {
  final bool inShell;

  const VendorMenuScreen({super.key, this.inShell = false});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = store.menuItems;

    final body = Column(
      children: [
        if (!inShell)
          Padding(
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top),
            child: const CunnectHeader(useWordmark: false),
          )
        else
          const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 22, 14, 17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Manage Menu',
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.5)),
                    const SizedBox(height: 4),
                    Text('${store.vendor.businessName} · ${items.length} item${items.length == 1 ? '' : 's'}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const VendorItemFormScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                child: const Text('+ Add Item'),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('No menu items yet',
                          style: TextStyle(color: Color(0xFFEEEEEE), fontSize: 16, fontWeight: FontWeight.w700)),
                      SizedBox(height: 7),
                      Text('Add your first food item for students to see it in the Food menu.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 0, thickness: 1, color: AppColors.line),
                  itemBuilder: (context, index) => _MenuItemRow(item: items[index]),
                ),
        ),
      ],
    );
    // Standalone pushes need their own Scaffold (yellow-underline fix).
    if (inShell) return body;
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(bottom: false, child: body),
    );
  }
}

class _MenuItemRow extends StatelessWidget {
  final FoodItem item;

  const _MenuItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: item.image.isNotEmpty
                ? Image.asset(item.image,
                    width: 65, height: 65, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder())
                : _placeholder(),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DishNameWithMark(
                    name: item.stock > 0 ? '${item.name}  ·  Stock ${item.stock}' : item.name,
                    isVeg: item.isVeg,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('₹${item.price.round()}',
                    style: const TextStyle(
                        color: AppColors.red, fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(item.category.toLowerCase(),
                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              InkWell(
                onTap: () => store.toggleItemAvailability(item.id),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 76),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: item.isAvailable ? const Color(0x17F5F5F5) : AppColors.surface,
                    border: Border.all(
                        color: item.isAvailable
                            ? const Color(0x7AF5F5F5)
                            : const Color(0xFF3C3C3C)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    item.isAvailable ? 'Available' : 'Unavailable',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: item.isAvailable ? const Color(0xFFF5F5F5) : const Color(0xFFAAAAAA),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => VendorItemFormScreen(item: item))),
                child: const Text('Edit item',
                    style: TextStyle(
                        color: Color(0xFFFF8791), fontSize: 10.5, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 7),
              GestureDetector(
                onTap: () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF1C1C21),
                      title: const Text('Delete item?',
                          style: TextStyle(color: Colors.white, fontSize: 15)),
                      content: Text('"${item.name}" will be deleted permanently.',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFB9B9BE))),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete',
                                style: TextStyle(color: Color(0xFFFF5252)))),
                      ],
                    ),
                  );
                  if (yes == true) {
                    final err = await store.deleteMenuItem(item.id);
                    if (context.mounted && err != null) {
                      showCunnectToast(context,
                          'Could not delete — $err', error: true);
                    }
                  }
                },
                child: const Text('Delete',
                    style: TextStyle(
                        color: Color(0xFFFF5252),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 65,
        height: 65,
        color: const Color(0xFF222222),
        alignment: Alignment.center,
        child: const Text('🍽️', style: TextStyle(fontSize: 22)),
      );
}
