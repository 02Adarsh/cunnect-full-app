import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'my_print_orders_screen.dart';

/// ⭐ print_vendor_shop.html (original) ka exact mirror — hero + panel,
/// page-range dropdowns, automatic total, red submit.
class PrintVendorShopScreen extends StatefulWidget {
  final PrintVendor vendor;

  const PrintVendorShopScreen({super.key, required this.vendor});

  @override
  State<PrintVendorShopScreen> createState() => _PrintVendorShopScreenState();
}

class _PrintVendorShopScreenState extends State<PrintVendorShopScreen> {
  Uint8List? _fileBytes;
  String? _fileName;
  bool _counting = false;
  String? _uploadError;
  int _totalPages = 0;
  int _copies = 1;
  String _printSide = 'single';
  int? _bwFrom;
  int? _bwTo;
  int? _colorFrom;
  int? _colorTo;
  final _notesController = TextEditingController();
  final _txnId = TextEditingController();
  bool _busy = false;

  // ---- UPI payment (QR + copyable ID), like the hostel store ----
  String? _qrB64;
  String? _qrUrl;
  String? _qrErr;
  bool _qrLoading = false;

  // ⭐ v55: an uploaded QR alone also enables UPI payment.
  bool get _hasUpi => widget.vendor.upiId.isNotEmpty || widget.vendor.hasQr;

  @override
  void initState() {
    super.initState();
    if (_hasUpi) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadQr());
    }
  }

  @override
  void dispose() {
    _qrDebounce?.cancel();
    _notesController.dispose();
    _txnId.dispose();
    super.dispose();
  }

  // ⭐ v56: the QR embeds the live total (upi://...&am=X) so scanning
  // from another phone auto-fills the exact amount in the UPI app.
  double _qrAmount = 0;
  Timer? _qrDebounce;

  num? _amountParam(double total) {
    if (total <= 0) return null;
    return total == total.roundToDouble()
        ? total.round()
        : double.parse(total.toStringAsFixed(2));
  }

  /// Called from build(): when the computed total changes (pages/copies/
  /// colour edits), re-fetch the QR with the new amount — debounced so
  /// fast typing does not spam the server.
  void _scheduleQrReload(double total) {
    if (widget.vendor.upiId.isEmpty) return; // amount QR needs a UPI ID
    if ((total - _qrAmount).abs() < 0.005) return;
    _qrAmount = total;
    _qrDebounce?.cancel();
    _qrDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _loadQr();
    });
  }

  Future<void> _loadQr() async {
    setState(() {
      _qrLoading = true;
      _qrErr = null;
    });
    final store = context.read<AppStore>();
    final data =
        await store.fetchUpiQr(widget.vendor.id, _amountParam(_qrAmount));
    if (!mounted) return;
    setState(() {
      _qrLoading = false;
      if (data == null || data['error'] != null) {
        _qrErr = data == null
            ? 'QR could not load — check your network and retry.'
            : '${data['error']}';
      } else {
        _qrB64 = (data['qr_b64'] ?? '').toString();
        // ⭐ v54: uploaded QR arrives as a relative /media/ URL — make
        // it absolute so Image.network can actually load it.
        final rawUrl = (data['qr_url'] ?? '').toString();
        _qrUrl = rawUrl.isEmpty ? '' : ApiConfig.media(rawUrl);
      }
    });
  }

  /// QR image widget (URL preferred, else base64) — rendered from one place.
  Widget _qrImage(double size) {
    if (_qrUrl != null && _qrUrl!.isNotEmpty) {
      return Image.network(_qrUrl!, width: size, height: size);
    }
    return Image.memory(base64Decode(_qrB64!), width: size, height: size);
  }

  /// ⭐ QR tap -> full-screen enlarge (dark overlay, tap-anywhere / × close).
  void _showQrFullScreen(BuildContext context, double total) {
    if (_qrB64 == null) return;
    showDialog(
      context: context,
      barrierColor: const Color(0xF2000000),
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size.width - 56;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Column(children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 14, 0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => Navigator.of(dialogContext).pop(),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF3A3A3A)),
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 18, color: Color(0xFFCCCCCC)),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20)),
                  child: _qrImage(size.clamp(180.0, 340.0)),
                ),
                const SizedBox(height: 18),
                Text(
                    total > 0
                        ? 'Scan to pay  ₹${total.toStringAsFixed(2)}'
                        : 'Scan to pay',
                    style: const TextStyle(
                        color: Color(0xFFF2F2F2),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .3)),
                const SizedBox(height: 5),
                const Text('Tap anywhere to close',
                    style: TextStyle(
                        color: Color(0xFF8A8A8A), fontSize: 10.5)),
                const Spacer(),
              ]),
            ),
          ),
        );
      },
    );
  }

  bool get _isImage {
    final n = (_fileName ?? '').toLowerCase();
    return n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.webp');
  }

  Set<int> _rangeSet(int? from, int? to) {
    if (from == null || to == null || from < 1 || to < from) return {};
    return {for (var p = from; p <= to; p++) p};
  }

  Map<String, dynamic> get _calc {
    final bw = _rangeSet(_bwFrom, _bwTo);
    final color = _rangeSet(_colorFrom, _colorTo);
    final overlap = bw.any(color.contains);
    final union = {...bw, ...color};
    final valid = _totalPages > 0 &&
        _copies > 0 &&
        !overlap &&
        union.length == _totalPages;
    final total = bw.length * _copies * widget.vendor.bwPricePerPage +
        color.length * _copies * widget.vendor.colorPricePerPage;
    return {'bw': bw, 'color': color, 'valid': valid, 'total': total};
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() {
      _fileBytes = file.bytes;
      _fileName = file.name;
      _counting = true;
      _uploadError = null;
      _totalPages = 0;
      _bwFrom = _bwTo = _colorFrom = _colorTo = null;
    });
    final store = context.read<AppStore>();
    final data = await store.printPageCount(file.bytes!, file.name);
    if (!mounted) return;
    setState(() {
      _counting = false;
      if (data['error'] != null) {
        _uploadError = data['error'] as String;
        return;
      }
      _totalPages = (data['pages'] as num?)?.toInt() ?? 1;
      // No automatic B&W pre-selection — the student assigns ranges manually.
      _bwFrom = null;
      _bwTo = null;
      _colorFrom = null;
      _colorTo = null;
    });
  }

  Future<void> _placeOrder() async {
    if (_fileBytes == null || !(_calc['valid'] as bool)) return;
    if (_hasUpi && _txnId.text.trim().length < 6) {
      showCunnectToast(
          context, 'Paste the UPI transaction ID from your payment app.',
          error: true);
      return;
    }
    setState(() => _busy = true);
    final store = context.read<AppStore>();
    String rng(int? f, int? t) => (f == null || t == null) ? '' : '$f-$t';
    final error = await store.placePrintOrder(
      vendorId: widget.vendor.id,
      fileBytes: _fileBytes!,
      fileName: _fileName ?? 'document',
      copies: _copies,
      printSide: _printSide,
      bwPageRanges: rng(_bwFrom, _bwTo),
      colorPageRanges: rng(_colorFrom, _colorTo),
      notes: _notesController.text.trim(),
      txnId: _hasUpi ? _txnId.text.trim() : '',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      showCunnectToast(context, error, error: true);
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => const MyPrintOrdersScreen(justPlaced: true)));
  }

  @override
  Widget build(BuildContext context) {
    final calc = _calc;
    final valid = calc['valid'] as bool;
    final total = calc['total'] as double;
    // ⭐ v56: keep the QR's embedded amount in sync with the live total.
    _scheduleQrReload(total);
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 35),
          children: [
            // header
            SizedBox(
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: -8,
                    child: IconButton(
                      icon: const Text('‹',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              height: 1)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const CunnectWordmark(),
                ],
              ),
            ),
            // hero
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x59F10B1D)),
                gradient: const LinearGradient(
                  colors: [Color(0xFF291014), Color(0xFF151515)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.vendor.businessName,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  const Text(
                      'Assign each document page to Black & White or Color '
                      'print. Total is calculated automatically.',
                      style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // panel
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New Print Request',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  _label('PDF or Image Document'),
                  InkWell(
                    onTap: (_busy || _counting) ? null : _pickFile,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0D0D),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF353535)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                              _fileBytes == null
                                  ? Icons.upload_file_outlined
                                  : Icons.description_outlined,
                              size: 15,
                              color: AppColors.muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                _fileName ?? 'Choose file… (PDF / image)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _fileName == null
                                        ? AppColors.muted
                                        : Colors.white)),
                          ),
                          const Text('⌁',
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_counting)
                    _statusRow('📄', _fileName ?? '', 'Reading document...',
                        ok: true),
                  if (!_counting && _fileBytes != null && _uploadError == null)
                    _statusRow(
                        _isImage ? '🖼️' : '📄',
                        _fileName ?? '',
                        '$_totalPages page${_totalPages == 1 ? '' : 's'} automatically detected',
                        ok: true),
                  if (_uploadError != null)
                    _statusRow('⚠️', _fileName ?? '', _uploadError!, ok: false),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Total Pages (Automatic)'),
                            _readOnlyBox(_totalPages > 0
                                ? '$_totalPages'
                                : 'Select file first'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Copies'),
                            _copiesField(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _label('Select Print Side'),
                  Row(
                    children: [
                      Expanded(child: _sideCard('One Side',
                          'Print on one side of each sheet', 'single')),
                      const SizedBox(width: 10),
                      Expanded(child: _sideCard('Double Side',
                          'Print on both sides of each sheet', 'double')),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      Expanded(
                          child: _rate('B&W RATE',
                              '₹${widget.vendor.bwPricePerPage.toStringAsFixed(2)} / page')),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _rate('COLOR RATE',
                              '₹${widget.vendor.colorPricePerPage.toStringAsFixed(2)} / page')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _label('Assign Page Ranges'),
                  _pageBox('Black & White Range', true),
                  const SizedBox(height: 10),
                  _pageBox('Color Range', false),
                  const SizedBox(height: 13),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x73F10B1D)),
                      gradient: const LinearGradient(
                        colors: [Color(0x21F10B1D), Color(0xFF121212)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Automatic Total',
                            style: TextStyle(
                                color: Color(0xFFC9C9C9),
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        Text('₹${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Color(0xFFFFABB2),
                                fontSize: 19,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _totalPages == 0
                        ? 'Upload document first. Then select B&W and Color page ranges from dropdowns.'
                        : valid
                            ? 'B&W: ${(calc['bw'] as Set).length} page(s) · Color: ${(calc['color'] as Set).length} page(s) · Ready to submit.'
                            : 'Use valid non-overlapping ranges and assign all pages.',
                    style: TextStyle(
                        color: _totalPages == 0
                            ? const Color(0xFFAAAAAA)
                            : valid
                                ? const Color(0xFFF5F5F5)
                                : const Color(0xFFFF9DA5),
                        fontSize: 9.5,
                        height: 1.4),
                  ),
                  if (_hasUpi) ...[
                    const SizedBox(height: 14),
                    _label('Payment — UPI Transfer'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2C2C2C)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: _qrLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(26),
                                    child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.red)))
                                : _qrB64 != null
                                    ? GestureDetector(
                                        onTap: () => _showQrFullScreen(
                                            context, total),
                                        child: Column(children: [
                                          Container(
                                              padding:
                                                  const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              child: _qrImage(168)),
                                          const SizedBox(height: 7),
                                          Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Icon(
                                                    Icons
                                                        .zoom_out_map_rounded,
                                                    size: 11,
                                                    color: Color(0xFF7A7A7A)),
                                                SizedBox(width: 4),
                                                Text('Tap QR to enlarge',
                                                    style: TextStyle(
                                                        color: Color(
                                                            0xFF7A7A7A),
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        letterSpacing: .3)),
                                              ]),
                                        ]),
                                      )
                                    : InkWell(
                                        onTap: _loadQr,
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text(
                                              _qrErr ??
                                                  'QR could not load — tap to retry',
                                              style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 11)),
                                        ),
                                      ),
                          ),
                          const SizedBox(height: 12),
                          // ---- elegant UPI ID strip (copy chip) ----
                          if (widget.vendor.upiId.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF141414),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                  color: const Color(0xFF2C2C2C)),
                            ),
                            child: Row(children: [
                              const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 16,
                                  color: Color(0xFFF5F5F5)),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('PAY TO UPI ID',
                                        style: TextStyle(
                                            color: Color(0xFF8A8A8A),
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.1)),
                                    const SizedBox(height: 2),
                                    Text(widget.vendor.upiId,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: .4,
                                            color: Color(0xFFF4F4F4))),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  Clipboard.setData(ClipboardData(
                                      text: widget.vendor.upiId));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('UPI ID copied')));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0x1AF10B1D),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0x40F10B1D)),
                                  ),
                                  child: Row(children: const [
                                    Icon(Icons.copy_rounded,
                                        size: 11,
                                        color: Color(0xFFFFABB2)),
                                    SizedBox(width: 4),
                                    Text('COPY',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: .6,
                                            color: Color(0xFFFFABB2))),
                                  ]),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 10),
                          // ⭐ v60: concise bullet-point payment steps
                          const PaymentSteps(
                              actionLabel: 'Send Print Request'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _txnId,
                            maxLength: 64,
                            style: const TextStyle(fontSize: 12.5),
                            decoration: InputDecoration(
                              hintText: 'UPI Transaction ID (paste here)',
                              hintStyle: TextStyle(
                                  color: AppColors.placeholder,
                                  fontSize: 11.5),
                              counterText: '',
                              filled: true,
                              fillColor: const Color(0xFF0D0D0D),
                              contentPadding: const EdgeInsets.all(12),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFF353535)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: AppColors.red),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _label('Special Instructions'),
                  TextField(
                    controller: _notesController,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Any special instructions? (optional)',
                      hintStyle: TextStyle(
                          color: AppColors.placeholder, fontSize: 11.5),
                      filled: true,
                      fillColor: const Color(0xFF0D0D0D),
                      contentPadding: const EdgeInsets.all(12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF353535)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.red),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          (valid && !_busy) ? _placeOrder : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        disabledBackgroundColor:
                            AppColors.red.withOpacity(.5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('SEND PRINT REQUEST'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String icon, String name, String sub, {required bool ok}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: ok ? const Color(0x59F5F5F5) : const Color(0x80F10B1D)),
        color: ok ? const Color(0x14F5F5F5) : const Color(0x1AF10B1D),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        color: ok
                            ? const Color(0xFFF5F5F5)
                            : const Color(0xFFFFABB2),
                        fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFFD7D7D7),
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );

  Widget _readOnlyBox(String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF353535)),
        ),
        child: Text(value,
            style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12)),
      );

  Widget _copiesField() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF353535)),
        ),
        child: Row(
          children: [
            IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 14),
                color: AppColors.muted,
                onPressed: () {
                  if (_copies > 1) setState(() => _copies--);
                }),
            Expanded(
              child: Text('$_copies',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 14),
                color: AppColors.muted,
                onPressed: () => setState(() => _copies++)),
          ],
        ),
      );

  Widget _sideCard(String title, String sub, String value) {
    final on = _printSide == value;
    return InkWell(
      onTap: () => setState(() => _printSide = value),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: on ? const Color(0x1AF10B1D) : const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: on ? AppColors.red : const Color(0xFF353535)),
          boxShadow: on
              ? [const BoxShadow(color: Color(0x1AF10B1D), blurRadius: 0, spreadRadius: 2)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(sub,
                style: TextStyle(
                    color: on ? const Color(0xFFFFABB2) : const Color(0xFF9D9D9D),
                    fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _rate(String label, String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF353535)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF9D9D9D),
                    fontSize: 9,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _pageBox(String title, bool isBw) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF353535)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Color(0xFFD7D7D7),
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _pageDropdown('FROM PAGE',
                    isBw ? _bwFrom : _colorFrom, (v) {
                  setState(() {
                    if (isBw) {
                      _bwFrom = v;
                    } else {
                      _colorFrom = v;
                    }
                  });
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _pageDropdown('TO PAGE', isBw ? _bwTo : _colorTo, (v) {
                  setState(() {
                    if (isBw) {
                      _bwTo = v;
                    } else {
                      _colorTo = v;
                    }
                  });
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pageDropdown(String mini, int? value, ValueChanged<int?> onCh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(mini,
            style: const TextStyle(
                color: Color(0xFF999999),
                fontSize: 9,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0D),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF353535)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF141414),
              style: const TextStyle(color: Colors.white, fontSize: 11),
              hint: const Text('Select',
                  style: TextStyle(fontSize: 11, color: Colors.white)),
              items: [
                const DropdownMenuItem(value: null, child: Text('Select')),
                for (var p = 1; p <= _totalPages; p++)
                  DropdownMenuItem(value: p, child: Text('Page $p')),
              ],
              onChanged: _totalPages > 0 ? onCh : null,
            ),
          ),
        ),
      ],
    );
  }
}
