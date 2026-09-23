import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// ⭐ v61: Hostel Essentials vendor — full catalogue control from the
/// vendor portal: store open/close, storefront description, and every
/// product (name, MRP, stock, description, photos) managed right here.
class HostelProductsScreen extends StatefulWidget {
  const HostelProductsScreen({super.key});

  @override
  State<HostelProductsScreen> createState() => _HostelProductsScreenState();
}

class _HostelProductsScreenState extends State<HostelProductsScreen> {
  String _storeDescription = '';
  bool _descLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<AppStore>();
      store.loadVendorHostelProducts();
      final s = await store.vendorStoreSettings();
      if (!mounted) return;
      setState(() {
        _descLoading = false;
        _storeDescription = '${s['store_description'] ?? ''}';
      });
    });
  }

  String _mrpText(dynamic mrp) {
    final n = mrp is num ? mrp : num.tryParse('$mrp') ?? 0;
    return n % 1 == 0 ? '${n.toInt()}' : '$n';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final products = store.vendorHostelProducts;
    final open = store.kitchenOpen;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.red,
          backgroundColor: const Color(0xFF1B1B1B),
          onRefresh: () async {
            await store.loadVendorHostelProducts();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
            children: [
              const SizedBox(height: 10),
              // ---- header ----
              Row(children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🛏 MY STORE',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1)),
                      SizedBox(height: 3),
                      Text('Products, photos, stock and storefront — '
                          'everything is yours to shape.',
                          style: TextStyle(
                              color: AppColors.muted, fontSize: 10)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              // ---- store open/close pill (same feel as the kitchen) ----
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _confirmStoreToggle(store, !open),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: open
                        ? const Color(0x17F5F5F5)
                        : const Color(0x1FF10B1D),
                    border: Border.all(
                        color: open
                            ? const Color(0x73F5F5F5)
                            : const Color(0xA6F10B1D)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: open
                            ? const Color(0xFFF5F5F5)
                            : const Color(0xFFF10B1D),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(open ? 'STORE OPEN' : 'STORE CLOSED',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .8,
                                  color: open
                                      ? const Color(0xFFF5F5F5)
                                      : const Color(0xFFFFABB2))),
                          const SizedBox(height: 2),
                          Text(
                              open
                                  ? 'Students can browse and place orders.'
                                  : 'Ordering is paused — students see the '
                                      'store as closed.',
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 9.5)),
                        ],
                      ),
                    ),
                    Text(open ? 'TAP TO CLOSE' : 'TAP TO OPEN',
                        style: const TextStyle(
                            color: Color(0xFF8A8A8A),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              // ---- storefront description ----
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Expanded(
                        child: Text('STOREFRONT DESCRIPTION',
                            style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1)),
                      ),
                      InkWell(
                        onTap: _editDescription,
                        borderRadius: BorderRadius.circular(7),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(7),
                            border:
                                Border.all(color: const Color(0xFF3A3A3A)),
                          ),
                          child: const Text('EDIT',
                              style: TextStyle(
                                  color: Color(0xFFC9C9C9),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .6)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    _descLoading
                        ? const Text('Loading…',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 11))
                        : Text(
                            _storeDescription.isEmpty
                                ? 'No description yet — tap EDIT to tell '
                                    'students what your store is about. It '
                                    'appears at the top of your store page.'
                                : _storeDescription,
                            style: TextStyle(
                                color: _storeDescription.isEmpty
                                    ? AppColors.muted
                                    : const Color(0xFFC9C9C9),
                                fontSize: 11.5,
                                height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // ---- products ----
              Row(children: [
                const Expanded(
                  child: Text('PRODUCTS',
                      style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ),
                Text('${products.length} item${products.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 9.5)),
              ]),
              const SizedBox(height: 8),
              for (final p in products) _productCard(store, p),
              if (products.isEmpty)
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Center(
                    child: Text('No products yet — add your first one below.',
                        style:
                            TextStyle(color: AppColors.muted, fontSize: 11)),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: () => _showProductForm(),
                  icon: const Icon(Icons.add, size: 16),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  label: const Text('Add New Product'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- store open/close ----------------

  void _confirmStoreToggle(AppStore store, bool opening) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.line)),
        title: Text(opening ? 'Open the store?' : 'Close the store?',
            style: const TextStyle(fontSize: 15)),
        content: Text(
          opening
              ? 'Students will be able to browse and place orders again.'
              : 'Students will see the store as closed and ordering will '
                  'be paused until you reopen.',
          style: const TextStyle(
              color: AppColors.muted, fontSize: 12, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child:
                  const Text('Cancel', style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                context.read<AppStore>().setKitchenOpen(opening);
                Navigator.pop(dialogContext);
              },
              child: Text(opening ? 'Open' : 'Close',
                  style: const TextStyle(color: AppColors.red))),
        ],
      ),
    );
  }

  // ---------------- storefront description ----------------

  Future<void> _editDescription() async {
    final c = TextEditingController(text: _storeDescription);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 20, 18, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Storefront Description',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
                'Shown to students at the top of your store page.',
                style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0D),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFF303030)),
              ),
              child: TextField(
                controller: c,
                maxLines: 5,
                maxLength: 2000,
                style: const TextStyle(fontSize: 12.5, height: 1.5),
                decoration: const InputDecoration(
                  hintText:
                      'e.g. Everything your hostel room needs — mattresses, '
                      'buckets, hangers and more, delivered on campus.',
                  hintStyle: TextStyle(
                      color: AppColors.placeholder, fontSize: 11.5),
                  border: InputBorder.none,
                  counterStyle:
                      TextStyle(color: AppColors.muted, fontSize: 9),
                  contentPadding: EdgeInsets.all(13),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final store = context.read<AppStore>();
                  final r = await store.vendorStoreSettings(
                      save: {'store_description': c.text.trim()});
                  if (!mounted) return;
                  if (r['error'] != null) {
                    showCunnectToast(context, '${r['error']}', error: true);
                  } else {
                    setState(() =>
                        _storeDescription = '${r['store_description'] ?? ''}');
                    showCunnectToast(context, 'Storefront description saved.');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                child: const Text('SAVE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- product card ----------------

  Widget _productCard(AppStore store, Map<String, dynamic> p) {
    final active = (p['is_active'] ?? true) as bool;
    final stock = (p['stock'] ?? 0) as int;
    final photos = [
      for (final ph in (p['photos'] as List? ?? [])) ph as Map,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: active ? AppColors.line : const Color(0x59F10B1D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0x2EF10B1D),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                  child: Text('${p['emoji'] ?? '🛒'}',
                      style: const TextStyle(fontSize: 18))),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p['name'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                      'MRP ₹${_mrpText(p['mrp'])}'
                      '${stock > 0 ? ' · Stock $stock' : ' · Stock off'}'
                      ' · ${photos.length} photo${photos.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: stock > 0 && stock <= 3
                              ? const Color(0xFFF5F5F5)
                              : AppColors.muted,
                          fontSize: 9.5)),
                ],
              ),
            ),
            // available / unavailable switch (like the food menu)
            Switch(
              value: active,
              activeColor: AppColors.red,
              onChanged: (_) async {
                final was = active;
                setState(() => p['is_active'] = !was);
                final err = await store.vendorHostelProductPost(
                    '/api/vendor/hostel-products/${p['id']}/',
                    {'is_active': !was});
                if (err != null) {
                  setState(() => p['is_active'] = was);
                  showCunnectToast(context, err, error: true);
                }
              },
            ),
          ]),
          if (!active)
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 6),
              child: Text('UNAVAILABLE — hidden from students',
                  style: TextStyle(
                      color: Color(0xFFFFABB2),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8)),
            ),
          const SizedBox(height: 8),
          // action row: edit · photos · delete — evenly spread
          Row(children: [
            Expanded(
              child: _actionChip(
                  icon: Icons.edit_outlined,
                  label: 'EDIT',
                  color: const Color(0xFFC9C9C9),
                  onTap: () => _showProductForm(product: p)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionChip(
                  icon: Icons.photo_library_outlined,
                  label: 'PHOTOS (${photos.length})',
                  color: const Color(0xFFF5F5F5),
                  onTap: () => _showPhotoManager(p)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionChip(
                  icon: Icons.delete_outline,
                  label: 'DELETE',
                  color: const Color(0xFFFF8791),
                  onTap: () => _confirmDeleteProduct(store, p)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _actionChip(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF2B2B2B)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5)),
          ),
        ]),
      ),
    );
  }

  void _confirmDeleteProduct(AppStore store, Map<String, dynamic> p) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.line)),
        title: const Text('Delete this product?',
            style: TextStyle(fontSize: 15)),
        content: Text(
          '"${p['name']}" will be removed from your store permanently.',
          style: const TextStyle(
              color: AppColors.muted, fontSize: 12, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child:
                  const Text('Cancel', style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                final err = await store.vendorHostelProductDelete(
                    '/api/vendor/hostel-products/${p['id']}/');
                if (!mounted) return;
                if (err != null) {
                  showCunnectToast(context, err, error: true);
                } else {
                  showCunnectToast(context, 'Product deleted.');
                }
                store.loadVendorHostelProducts();
              },
              child:
                  const Text('Delete', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
  }

  // ---------------- product form (create / edit) ----------------

  Future<void> _showProductForm({Map<String, dynamic>? product}) async {
    final name = TextEditingController(text: '${product?['name'] ?? ''}');
    final mrp = TextEditingController(
        text: product == null ? '' : _mrpText(product['mrp']));
    final stock = TextEditingController(
        text: product == null ? '' : '${product['stock'] ?? 0}');
    final desc =
        TextEditingController(text: '${product?['description'] ?? ''}');
    final emoji =
        TextEditingController(text: '${product?['emoji'] ?? '🛒'}');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 20, 18, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product == null ? 'New Product' : 'Edit Product',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                  'Name, price, live stock and the description students '
                  'read in the product dropdown.',
                  style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
              const SizedBox(height: 14),
              Row(children: [
                SizedBox(width: 80, child: _field('Emoji', emoji)),
                const SizedBox(width: 10),
                Expanded(child: _field('Product name', name)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _field('MRP (₹)', mrp,
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true))),
                const SizedBox(width: 10),
                Expanded(
                    child: _field('Stock (0 = unlimited)', stock,
                        keyboard: TextInputType.number)),
              ]),
              const SizedBox(height: 10),
              _field('Description', desc, maxLines: 4),
              const SizedBox(height: 6),
              const Text(
                  'Stock counts down with every order and the product '
                  'turns unavailable automatically at 0 — exactly like '
                  'the food menu.',
                  style: TextStyle(color: AppColors.muted, fontSize: 9.5)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  onPressed: () async {
                    final priceVal = double.tryParse(mrp.text.trim()) ?? 0;
                    if (name.text.trim().isEmpty || priceVal <= 0) {
                      showCunnectToast(
                          ctx, 'Enter a product name and a valid MRP.',
                          error: true);
                      return;
                    }
                    Navigator.of(ctx).pop();
                    final store = context.read<AppStore>();
                    final body = {
                      'name': name.text.trim(),
                      'mrp': priceVal,
                      'stock': int.tryParse(stock.text.trim()) ?? 0,
                      'description': desc.text.trim(),
                      'emoji': emoji.text.trim(),
                    };
                    final err = await store.vendorHostelProductPost(
                        product == null
                            ? '/api/vendor/hostel-products/'
                            : '/api/vendor/hostel-products/${product['id']}/',
                        body);
                    if (!mounted) return;
                    if (err != null) {
                      showCunnectToast(context, err, error: true);
                    } else {
                      showCunnectToast(
                          context,
                          product == null
                              ? 'Product added to your store.'
                              : 'Product updated.');
                    }
                    store.loadVendorHostelProducts();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  child: Text(product == null ? 'ADD PRODUCT' : 'SAVE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String hint, TextEditingController c,
      {TextInputType? keyboard, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF303030)),
      ),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 12.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(color: AppColors.placeholder, fontSize: 11.5),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        ),
      ),
    );
  }

  // ---------------- photo manager ----------------

  Future<void> _showPhotoManager(Map<String, dynamic> p) async {
    var photos = [
      for (final ph in (p['photos'] as List? ?? [])) ph as Map,
    ];
    bool uploading = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Photos — ${p['name']}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text(
                      'Students swipe through these in the product '
                      'dropdown. Add as many angles as you like.',
                      style:
                          TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  const SizedBox(height: 14),
                  Wrap(spacing: 9, runSpacing: 9, children: [
                    for (final ph in photos)
                      Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                              ApiConfig.media('${ph['url'] ?? ''}'),
                              width: 74,
                              height: 74,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                  width: 74,
                                  height: 74,
                                  color: const Color(0xFF222222),
                                  child: const Icon(Icons.broken_image,
                                      size: 16, color: AppColors.muted))),
                        ),
                        Positioned(
                          top: 3,
                          right: 3,
                          child: InkWell(
                            onTap: () async {
                              setInner(() => photos.remove(ph));
                              p['photos'] = photos;
                              await context
                                  .read<AppStore>()
                                  .vendorHostelProductDelete(
                                      '/api/vendor/hostel-products/'
                                      '${p['id']}/photo/?photo_id=${ph['id']}');
                              if (mounted) {
                                context
                                    .read<AppStore>()
                                    .loadVendorHostelProducts();
                              }
                            },
                            child: Container(
                              width: 19,
                              height: 19,
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xCC000000)),
                              child: const Icon(Icons.close,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ]),
                    // add tile
                    InkWell(
                      onTap: uploading
                          ? null
                          : () async {
                              final res =
                                  await FilePicker.platform.pickFiles(
                                type: FileType.image,
                                withData: true,
                              );
                              final f = res?.files.firstOrNull;
                              if (f == null || f.bytes == null) return;
                              setInner(() => uploading = true);
                              final store = context.read<AppStore>();
                              final err = await store.vendorHostelPhoto(
                                  (p['id'] as num).toInt(),
                                  f.bytes!,
                                  f.name);
                              await store.loadVendorHostelProducts();
                              final fresh = store.vendorHostelProducts
                                  .where((x) => x['id'] == p['id'])
                                  .toList();
                              setInner(() {
                                uploading = false;
                                if (fresh.isNotEmpty) {
                                  photos = [
                                    for (final ph
                                        in (fresh.first['photos'] as List? ??
                                            [])) ph as Map,
                                  ];
                                  p['photos'] = photos;
                                }
                              });
                              if (err != null && mounted) {
                                showCunnectToast(context, err, error: true);
                              }
                            },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: const Color(0xFF3A3A3A)),
                        ),
                        child: uploading
                            ? const Center(
                                child: SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.red)))
                            : const Icon(Icons.add_a_photo_outlined,
                                size: 19, color: Color(0xFF9A9A9A)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 43,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDDDDDD),
                        side: const BorderSide(color: Color(0xFF3A3A3A)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      child: const Text('DONE'),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
