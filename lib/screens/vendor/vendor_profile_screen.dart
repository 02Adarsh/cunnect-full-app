import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'vendor_earnings_screen.dart';
import 'vendor_login_screen.dart';
import 'vendor_menu_screen.dart';

/// Vendor Profile — same layout as vendor_profile.html.
class VendorProfileScreen extends StatefulWidget {
  final bool inShell;

  const VendorProfileScreen({super.key, this.inShell = false});

  @override
  State<VendorProfileScreen> createState() => _VendorProfileScreenState();
}

class _VendorProfileScreenState extends State<VendorProfileScreen> {
  TextEditingController? _nameController;
  TextEditingController? _phoneController;
  TextEditingController? _upiController;
  // ⭐ v61: vendors control their storefront description themselves
  TextEditingController? _descController;
  bool _upiLoaded = false;
  String _qrUrl = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_nameController == null) {
      final vendor = context.read<AppStore>().vendor;
      _nameController = TextEditingController(text: vendor.businessName);
      _phoneController = TextEditingController(text: vendor.phone);
      _upiController = TextEditingController();
      _descController = TextEditingController();
      context.read<AppStore>().fetchVendorUpiInfo().then((info) {
        if (mounted) {
          setState(() {
            _upiController?.text = (info['upi_id'] ?? '') as String;
            _qrUrl = (info['qr_url'] ?? '') as String;
            _upiLoaded = true;
          });
        }
      });
      context.read<AppStore>().vendorStoreSettings().then((info) {
        if (mounted && info['error'] == null) {
          setState(() {
            _descController?.text = (info['store_description'] ?? '') as String;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController?.dispose();
    _phoneController?.dispose();
    _upiController?.dispose();
    _descController?.dispose();
    super.dispose();
  }

  bool _busy = false;
  String _logoUrl = '';

  Future<void> _pickLogo() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final picked = res.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        showCunnectToast(context, 'Could not read the image.', error: true);
      }
      return;
    }
    setState(() => _busy = true);
    final store = context.read<AppStore>();
    final err = await store.uploadVendorLogo(bytes, picked.name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _logoUrl = err == null ? 'set' : '';
    });
    showCunnectToast(context,
        err == null ? 'Shop icon uploaded.' : err,
        error: err != null);
  }

  Future<void> _pickQr() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final picked = res.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        showCunnectToast(context, 'Could not read the image.', error: true);
      }
      return;
    }
    setState(() => _busy = true);
    final store = context.read<AppStore>();
    final err = await store.uploadVendorQr(bytes, picked.name);
    final info = await store.fetchVendorUpiInfo();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _qrUrl = (info['qr_url'] ?? '') as String;
    });
    showCunnectToast(context,
        err == null ? 'QR uploaded — active at checkout.' : err,
        error: err != null);
  }

  Future<void> _removeQr() async {
    setState(() => _busy = true);
    final store = context.read<AppStore>();
    try {
      await store.apiPostRemoveQr();
    } catch (_) {}
    final info = await store.fetchVendorUpiInfo();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _qrUrl = (info['qr_url'] ?? '') as String;
    });
    showCunnectToast(context, 'QR removed — auto QR will be used.');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final vendor = store.vendor;

    final body = Column(
      children: [
        if (!widget.inShell)
          Padding(
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top),
            child: const CunnectHeader(useWordmark: false),
          )
        else
          const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 35 + MediaQuery.of(context).padding.bottom),
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(0, 22, 0, 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                  color: AppColors.surface,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('UPI ID (payments)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Students will see this UPI as a QR code at checkout.',
                        style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _upiController,
                      style: const TextStyle(fontSize: 13),
                      decoration: cunnectInputDecoration(placeholder: 'name@upi'),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () async {
                          final err = await store.saveVendorUpi(
                              _upiController?.text.trim() ?? '');
                          if (!mounted) return;
                          showCunnectToast(context,
                              err == null ? 'UPI ID saved.' : err,
                              error: err != null);
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            foregroundColor: Colors.white),
                        child: const Text('Save UPI',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _pickLogo,
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.line)),
                          child: const Text('Upload shop icon',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                    if (_logoUrl.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                            'Your icon is live on food cards.',
                            style: TextStyle(
                                color: Color(0xFF7ED98B), fontSize: 10)),
                      ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _pickQr,
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.line)),
                          child: const Text('Upload QR image',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      if (_qrUrl.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : _removeQr,
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.line)),
                            child: const Text('Remove QR',
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ]),
                    if (_qrUrl.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                            'Your uploaded QR is active at checkout.',
                            style: TextStyle(
                                color: Color(0xFF7ED98B), fontSize: 10)),
                      ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(0, 0, 0, 17),
                padding: const EdgeInsets.fromLTRB(16, 23, 16, 23),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: [0, 0.62],
                    colors: [Color(0xFF251014), Color(0xFF151515)],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF310F14),
                        border: Border.all(color: AppColors.red, width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x38F10B1D), blurRadius: 18)],
                      ),
                      alignment: Alignment.center,
                      child: Text(vendor.businessName.substring(0, 2).toUpperCase(),
                          style: const TextStyle(
                              color: Color(0xFFFF9DA5), fontSize: 25, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 12),
                    Text(vendor.businessName,
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text('Owner: ${vendor.ownerUsername}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: const Color(0x1738B765),
                        border: Border.all(color: const Color(0x6B38B765)),
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
                              boxShadow: [BoxShadow(color: AppColors.red, blurRadius: 8)],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(vendor.isActive ? 'Active Partner' : 'Inactive Partner',
                              style: const TextStyle(
                                  color: Color(0xFFF5F5F5), fontSize: 10, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 15, 14, 11),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.line)),
                      ),
                      child: const Text('Business Profile',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Business / Store Name'),
                          TextField(
                            controller: _nameController,
                            style: const TextStyle(fontSize: 13),
                            decoration: cunnectInputDecoration(),
                          ),
                          const SizedBox(height: 14),
                          _label('Business Mobile Number'),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(fontSize: 13),
                            decoration: cunnectInputDecoration(placeholder: 'Enter mobile number'),
                          ),
                          const SizedBox(height: 14),
                          // ⭐ v61: storefront description — shown to students
                          _label('Storefront Description'),
                          TextField(
                            controller: _descController,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 13, height: 1.45),
                            decoration: cunnectInputDecoration(
                                placeholder:
                                    'A short line students see on your store page'),
                          ),
                          const SizedBox(height: 14),
                          _label('User ID'),
                          _readOnly(store.vendor.ownerUsername),
                          const SizedBox(height: 14),
                          _label('Email Address'),
                          _readOnly(store.vendor.email.isNotEmpty
              ? store.vendor.email
              : '${store.vendor.ownerUsername}@cunnect.app'),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                final err = await store.saveVendorProfile(
                                  businessName: _nameController!.text.trim(),
                                  phone: _phoneController!.text.trim(),
                                );
                                // ⭐ v61: persist storefront description too
                                await store.vendorStoreSettings(save: {
                                  'store_description':
                                      _descController!.text.trim(),
                                });
                                if (!mounted) return;
                                showCunnectToast(context,
                                    err ?? 'Profile saved successfully.',
                                    error: err != null);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              child: const Text('SAVE PROFILE'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 15, 14, 11),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.line)),
                      ),
                      child: const Text('Partner Account',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        children: [
                          _info('Approval Status', vendor.isApproved ? 'Approved' : 'Pending Approval'),
                          _info('Store Status', vendor.isActive ? 'Active' : 'Inactive'),
                          _infoLink('Manage Products', 'Open Menu', () {
                            Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const VendorMenuScreen()));
                          }),
                          _infoLink('View Earnings', 'Open Earnings', () {
                            Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const VendorEarningsScreen()));
                          }),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () {
                                store.vendorLogout();
                                Navigator.of(context).pushAndRemoveUntil(
                                    MaterialPageRoute(builder: (_) => const VendorLoginScreen()),
                                    (route) => route.isFirst);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFFF9CA5),
                                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                              child: const Text('Logout'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    // When pushed standalone (outside the shell) the screen needs its own
    // Scaffold, otherwise text renders with the yellow-underline glitch.
    if (widget.inShell) return body;
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(bottom: false, child: body),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  Widget _readOnly(String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF383838)),
        ),
        child: Text(value, style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
      );

  Widget _info(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            Text(value, style: const TextStyle(color: Color(0xFFEEEEEE), fontSize: 11)),
          ],
        ),
      );

  Widget _infoLink(String label, String value, VoidCallback onTap) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            GestureDetector(
              onTap: onTap,
              child: Text(value,
                  style: const TextStyle(
                      color: Color(0xFFFF9CA5), fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}
