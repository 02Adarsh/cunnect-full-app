import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// Add / Edit Food Item — same fields as vendor_item_form.html.
class VendorItemFormScreen extends StatefulWidget {
  final FoodItem? item;

  const VendorItemFormScreen({super.key, this.item});

  @override
  State<VendorItemFormScreen> createState() => _VendorItemFormScreenState();
}

class _VendorItemFormScreenState extends State<VendorItemFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _stockController;
  late String _category;

  static const _categories = [
    'wrap', 'burger', 'dosa', 'pasta', 'bowl', 'dessert', 'pizza', 'other',
  ];
  late bool _isAvailable;
  String? _error;
  Uint8List? _photoBytes;
  String _photoName = '';

  bool get _editing => widget.item != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _priceController =
        TextEditingController(text: widget.item != null ? widget.item!.price.round().toString() : '');
    _descriptionController = TextEditingController(text: widget.item?.description ?? '');
    _category = (widget.item?.category.isNotEmpty ?? false)
        ? widget.item!.category
        : 'wrap';
    _isAvailable = widget.item?.isAvailable ?? true;
    _stockController = TextEditingController(
        text: (widget.item?.stock ?? 0) > 0
            ? (widget.item?.stock ?? 0).toString()
            : '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const CunnectHeader(useWordmark: false),
          Expanded(child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(_editing ? 'Edit Food Item' : 'Add Food Item',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text('This item will only be visible under ${store.vendor.businessName}.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 22),
          _label('Photo'),
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF373737)),
              ),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: _photoBytes != null
                      ? Image.memory(_photoBytes!,
                          width: 56, height: 56, fit: BoxFit.cover)
                      : (widget.item?.imageUrl.isNotEmpty == true
                          ? CunnectImage(widget.item!.imageUrl,
                              width: 56, height: 56)
                          : Container(
                              width: 56,
                              height: 56,
                              color: const Color(0xFF1B1B1B),
                              alignment: Alignment.center,
                              child: const Icon(Icons.add_a_photo_outlined,
                                  size: 22, color: Color(0xFF5A5A5A)),
                            )),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                      'Tap to set / change the dish photo',
                      style: TextStyle(
                          color: Color(0xFFB5B5B5), fontSize: 11.5)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          _label('Name'),
          TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 13),
            decoration: cunnectInputDecoration(placeholder: 'Item name'),
          ),
          const SizedBox(height: 16),
          _label('Price (₹)'),
          TextField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13),
            decoration: cunnectInputDecoration(placeholder: 'e.g. 120'),
          ),
          const SizedBox(height: 16),
          _label('Stock (kitne bache — khali = unlimited)'),
          TextField(
            controller: _stockController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13),
            decoration: cunnectInputDecoration(placeholder: 'e.g. 20'),
          ),
          const SizedBox(height: 16),
          _label('Category'),
          Container(
            height: 43,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFF373737)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _categories.contains(_category) ? _category : 'other',
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.muted),
                dropdownColor: const Color(0xFF1C1C1C),
                items: [
                  for (final category in _categories)
                    DropdownMenuItem(
                      value: category,
                      child: Text(category[0].toUpperCase() + category.substring(1),
                          style: const TextStyle(fontSize: 13, color: Color(0xFFF5F5F5))),
                    ),
                ],
                onChanged: (value) => setState(() => _category = value ?? 'wrap'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _label('Description'),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: cunnectInputDecoration(placeholder: 'Short tasty description'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _isAvailable,
                  onChanged: (value) => setState(() => _isAvailable = value ?? true),
                  activeColor: AppColors.red,
                  side: const BorderSide(color: Color(0xFF555555)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              const Text('Available for students',
                  style: TextStyle(color: Color(0xFFD8D8D8), fontSize: 12)),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFFF9EA6), fontSize: 10.5)),
            ),
          const SizedBox(height: 23),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              child: Text(_editing ? 'Save Changes' : 'Add to Menu'),
            ),
          ),
        ],
      ),
    ),
        ]),
      ),);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            style: const TextStyle(color: Color(0xFFC4C4C4), fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  Future<void> _pickPhoto() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final picked = res.files.first;
    if (picked.bytes == null) return;
    setState(() {
      _photoBytes = picked.bytes;
      _photoName = picked.name;
    });
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceController.text.trim());
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter the item name.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Please enter a valid price.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final store = context.read<AppStore>();
    final result = await store.saveFoodItem(
          id: widget.item?.id,
          name: _nameController.text.trim(),
          price: price,
          description: _descriptionController.text.trim(),
          category: _category,
          isAvailable: _isAvailable,
          stock: int.tryParse(_stockController.text.trim()) ?? 0,
        );
    if (!mounted) return;
    if (result['error'] != null) {
      setState(() => _error = '${result['error']}');
      return;
    }
    if (_photoBytes != null) {
      final itemId = widget.item?.id ?? (result['id'] as int?);
      if (itemId != null) {
        await store.uploadMenuItemPhoto(itemId, _photoBytes!, _photoName);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(_editing ? 'Item updated.' : 'Item added to menu.'),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 96),
      backgroundColor: const Color(0xFF112218),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: Color(0x8C3DB260)),
      ),
      duration: const Duration(seconds: 2),
    ));
  }
}
