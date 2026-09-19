import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../../services/open_url.dart';
import '../pdf_viewer_screen.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../vendor/vendor_earnings_screen.dart';
import '../vendor/vendor_login_screen.dart';

/// Print partner dashboard — orders (5s auto refresh), earnings, page
/// prices + UPI/QR settings and profile. Styled like the food vendor
/// dashboard, with only the features a print partner actually needs.
class PrintVendorDashboardScreen extends StatefulWidget {
  const PrintVendorDashboardScreen({super.key});

  @override
  State<PrintVendorDashboardScreen> createState() =>
      _PrintVendorDashboardScreenState();
}

class _PrintVendorDashboardScreenState
    extends State<PrintVendorDashboardScreen> {
  Timer? _pollTimer;
  int _tab = 0; // 0 = Orders, 1 = Earnings, 2 = Settings, 3 = Profile

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadPrintVendorDashboard();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) context.read<AppStore>().loadPrintVendorDashboard();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final orders = store.printVendorOrders;
    final pending =
        orders.where((o) => o.status == PrintOrderStatus.pending).length;
    final active = orders
        .where((o) =>
            o.status == PrintOrderStatus.accepted ||
            o.status == PrintOrderStatus.printing ||
            o.status == PrintOrderStatus.ready)
        .length;
    final done =
        orders.where((o) => o.status == PrintOrderStatus.completed).length;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const CunnectHeader(useWordmark: false),
          // ---- title ----
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.vendor.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    const Text('Print Partner Dashboard',
                        style:
                            TextStyle(color: AppColors.muted, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x26F10B1D),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: const Color(0x59F10B1D)),
                ),
                child: const Text('PRINTOUT',
                    style: TextStyle(
                        color: Color(0xFFFF9CA4),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8)),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          // ---- metrics ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Expanded(
                  child:
                      _metric('Pending', '$pending', const Color(0xFFD9A94E))),
              const SizedBox(width: 10),
              Expanded(
                  child: _metric(
                      'In Progress', '$active', const Color(0xFF6EA8FE))),
              const SizedBox(width: 10),
              Expanded(child: _metric('Completed', '$done', AppColors.green)),
            ]),
          ),
          const SizedBox(height: 12),
          // ---- tabs ----
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF161616),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2B2B2B)),
            ),
            child: Row(children: [
              _tabButton('Orders', 0),
              _tabButton('Earnings', 1),
              _tabButton('Settings', 2),
              _tabButton('Profile', 3),
            ]),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.red,
              backgroundColor: const Color(0xFF1B1B1B),
              onRefresh: () => store.loadPrintVendorDashboard(),
              child: switch (_tab) {
                0 => _ordersList(orders),
                1 => const _PrintEarningsTab(),
                2 => _settings(store),
                _ => const _PrintProfileTab(),
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final activeTab = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: activeTab ? const Color(0x26F10B1D) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color:
                    activeTab ? const Color(0x8CF10B1D) : Colors.transparent),
          ),
          alignment: Alignment.center,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: activeTab
                      ? const Color(0xFFFF9CA4)
                      : const Color(0xFF9A9A9A))),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.lineSoft),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
        ]),
      );

  // ------------------------------------------------ orders
  Widget _ordersList(List<PrintOrder> orders) {
    if (orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 110),
          Center(
            child: Column(children: [
              Icon(Icons.print_outlined, size: 34, color: Color(0xFF3E3E3E)),
              SizedBox(height: 12),
              Text('No print orders yet',
                  style: TextStyle(
                      color: Color(0xFFEEEEEE),
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 5),
              Text('New orders will appear here automatically.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
            ]),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
      itemCount: orders.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _OrderCard(order: orders[i]),
      ),
    );
  }

  // ------------------------------------------------ settings
  Widget _settings(AppStore store) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
      children: [
        _PricesPanel(store: store),
        const SizedBox(height: 12),
        _UpiPanel(store: store),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Account',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton(
                  onPressed: () {
                    store.vendorLogout();
                    Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (_) => const VendorLoginScreen()),
                        (route) => route.isFirst);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0x8CF10B1D)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Logout',
                      style: TextStyle(
                          color: Color(0xFFFF9CA4),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// Order card — file, specs, payment, student details (mobile only after
// accept) and the next status action.
// ----------------------------------------------------------------------
class _OrderCard extends StatelessWidget {
  final PrintOrder order;

  const _OrderCard({required this.order});

  Color get _statusColor {
    switch (order.status) {
      case PrintOrderStatus.pending:
        return const Color(0xFFD9A94E);
      case PrintOrderStatus.accepted:
      case PrintOrderStatus.printing:
        return const Color(0xFF6EA8FE);
      case PrintOrderStatus.ready:
        return const Color(0xFFB58CFF);
      case PrintOrderStatus.completed:
        return AppColors.green;
      case PrintOrderStatus.rejected:
        return const Color(0xFF9A9A9A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final actions = store.printNextActions(order);
    final accepted = order.status != PrintOrderStatus.pending &&
        order.status != PrintOrderStatus.rejected;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- header: file + status ----
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 0),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: const Color(0x26F10B1D),
                  border: Border.all(color: const Color(0x40F10B1D)),
                ),
                child: const Icon(Icons.description_outlined,
                    size: 17, color: Color(0xFFFF9CA4)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(_timeAgo(order.createdAt),
                        style: const TextStyle(
                            color: Color(0xFF747474), fontSize: 9.5)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(.14),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: _statusColor.withOpacity(.55)),
                ),
                child: Text(order.status.label.toUpperCase(),
                    style: TextStyle(
                        color: _statusColor,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6)),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          // ---- specs ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Wrap(
              spacing: 7,
              runSpacing: 6,
              children: [
                _chip('${order.pages} pages'),
                _chip('${order.copies} ${order.copies == 1 ? 'copy' : 'copies'}'),
                _chip(order.printSide == 'double'
                    ? 'Double side'
                    : 'Single side'),
                if (order.bwPages > 0) _chip('B&W: ${order.bwPages} pg'),
                if (order.colorPages > 0)
                  _chip('Color: ${order.colorPages} pg'),
              ],
            ),
          ),
          if (order.bwPageRanges.isNotEmpty || order.colorPageRanges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 8, 13, 0),
              child: Text(
                  [
                    if (order.bwPageRanges.isNotEmpty)
                      'B&W pages: ${order.bwPageRanges}',
                    if (order.colorPageRanges.isNotEmpty)
                      'Color pages: ${order.colorPageRanges}',
                  ].join('   ·   '),
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 10.5)),
            ),
          if (order.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 8, 13, 0),
              child: Text('“${order.note}”',
                  style: const TextStyle(
                      color: Color(0xFFCFCFCF),
                      fontSize: 11,
                      fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 10),
          // ---- payment + student ----
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 13),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFF262626)),
            ),
            child: Column(children: [
              _infoRow('Amount', '₹${order.totalPrice.toStringAsFixed(2)}',
                  valueColor: const Color(0xFFFFABB2)),
              _infoRow(
                  'Transaction ID',
                  order.txnId.isNotEmpty
                      ? order.txnId
                      : (order.txnLast4.isNotEmpty
                          ? '****${order.txnLast4}'
                          : 'Not provided')),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 7),
                child: Divider(height: 1, color: Color(0xFF262626)),
              ),
              _infoRow('Student',
                  order.studentName.isEmpty ? '—' : order.studentName),
              _infoRow('UID', order.studentUid.isEmpty ? '—' : order.studentUid),
              _infoRow(
                  'Mobile',
                  accepted
                      ? (order.studentPhone.isEmpty
                          ? '—'
                          : order.studentPhone)
                      : 'Visible after you accept the order',
                  valueColor: accepted && order.studentPhone.isNotEmpty
                      ? const Color(0xFFA8EBBA)
                      : null,
                  onTap: accepted && order.studentPhone.isNotEmpty
                      ? () => openExternalUrl('tel:${order.studentPhone}')
                      : null),
            ]),
          ),
          const SizedBox(height: 11),
          // ---- actions ----
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
            child: Row(children: [
              // file download / open — only after the order is accepted
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: !accepted || order.fileUrl.isEmpty
                        ? null
                        : () {
                            // ⭐ v59: the document opens INSIDE the app
                            // (PDF/image viewer). The token travels in the
                            // URL because the secure-download endpoint may
                            // redirect (Cloudinary) and headers are lost.
                            final sep =
                                order.fileUrl.contains('?') ? '&' : '?';
                            final url =
                                '${order.fileUrl}${sep}token=${ApiConfig.vendorToken ?? ''}';
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => PdfViewerScreen(
                                    url: url, title: order.fileName)));
                          },
                    icon: Icon(
                        accepted
                            ? Icons.file_download_outlined
                            : Icons.lock_outline,
                        size: 15),
                    label: Text(accepted ? 'File' : 'Locked'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDDDDDD),
                      side: const BorderSide(color: Color(0xFF3A3A3A)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9)),
                      textStyle: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              for (final (label, action) in actions) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: ElevatedButton(
                      onPressed: () =>
                          store.updatePrintOrderStatus(order.id, action),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: action == 'reject'
                            ? const Color(0xFF2A1214)
                            : AppColors.red,
                        foregroundColor: action == 'reject'
                            ? const Color(0xFFFF9CA4)
                            : Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                        textStyle: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                      child: Text(label),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1D1D),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFF2C2C2C)),
        ),
        child: Text(label,
            style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
      );

  Widget _infoRow(String label, String value,
      {Color? valueColor, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Text(value,
                  style: TextStyle(
                      color: valueColor ?? const Color(0xFFE4E4E4),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration:
                          onTap != null ? TextDecoration.underline : null,
                      decorationColor: const Color(0xFFA8EBBA))),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
class _PricesPanel extends StatefulWidget {
  final AppStore store;

  const _PricesPanel({required this.store});

  @override
  State<_PricesPanel> createState() => _PricesPanelState();
}

class _PricesPanelState extends State<_PricesPanel> {
  late final TextEditingController _bw;
  late final TextEditingController _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bw = TextEditingController();
    _color = TextEditingController();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final store = widget.store;
    await store.loadPrintVendors();
    if (!mounted) return;
    final mine = store.printVendors
        .where((v) => v.businessName == store.vendor.businessName)
        .toList();
    if (mine.isNotEmpty) {
      _bw.text = mine.first.bwPricePerPage.toStringAsFixed(2);
      _color.text = mine.first.colorPricePerPage.toStringAsFixed(2);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _bw.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bw = double.tryParse(_bw.text.trim());
    final color = double.tryParse(_color.text.trim());
    if (bw == null || bw <= 0 || color == null || color <= 0) {
      showCunnectToast(context, 'Enter valid page prices.', error: true);
      return;
    }
    setState(() => _saving = true);
    final err =
        await widget.store.updatePrintPrices(bwPrice: bw, colorPrice: color);
    if (!mounted) return;
    setState(() => _saving = false);
    showCunnectToast(context, err ?? 'Prices updated.', error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Page Prices',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Students see these rates while placing an order.',
              style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _priceField('B&W  (₹ / page)', _bw)),
            const SizedBox(width: 10),
            Expanded(child: _priceField('Color  (₹ / page)', _color)),
          ]),
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Prices'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFFC4C4C4),
                fontSize: 10.5,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            hintText: '0.00',
            hintStyle:
                TextStyle(color: AppColors.placeholder, fontSize: 11.5),
            filled: true,
            fillColor: const Color(0xFF0D0D0D),
            contentPadding: const EdgeInsets.all(11),
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
      ],
    );
  }
}

// ----------------------------------------------------------------------
class _UpiPanel extends StatefulWidget {
  final AppStore store;

  const _UpiPanel({required this.store});

  @override
  State<_UpiPanel> createState() => _UpiPanelState();
}

class _UpiPanelState extends State<_UpiPanel> {
  final _upi = TextEditingController();
  bool _saving = false;
  bool _qrBusy = false;
  String _qrUrl = '';

  @override
  void initState() {
    super.initState();
    widget.store.fetchVendorUpiInfo().then((info) {
      if (mounted) {
        setState(() {
          _upi.text = (info['upi_id'] ?? '') as String;
          _qrUrl = (info['qr_url'] ?? '') as String;
        });
      }
    });
  }

  @override
  void dispose() {
    _upi.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final err = await widget.store.saveVendorUpi(_upi.text.trim());
    if (!mounted) return;
    setState(() => _saving = false);
    showCunnectToast(context, err ?? 'UPI ID saved.', error: err != null);
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
    setState(() => _qrBusy = true);
    final err = await widget.store.uploadVendorQr(bytes, picked.name);
    final info = await widget.store.fetchVendorUpiInfo();
    if (!mounted) return;
    setState(() {
      _qrBusy = false;
      _qrUrl = (info['qr_url'] ?? '') as String;
    });
    showCunnectToast(context,
        err == null ? 'QR uploaded — active at checkout.' : err,
        error: err != null);
  }

  Future<void> _removeQr() async {
    setState(() => _qrBusy = true);
    try {
      await widget.store.apiPostRemoveQr();
    } catch (_) {}
    final info = await widget.store.fetchVendorUpiInfo();
    if (!mounted) return;
    setState(() {
      _qrBusy = false;
      _qrUrl = (info['qr_url'] ?? '') as String;
    });
    showCunnectToast(context, 'QR removed — the auto QR will be used.');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('UPI ID (payments)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
              'Students pay to this UPI ID through a QR code at checkout.',
              style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _upi,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              hintText: 'name@upi',
              hintStyle:
                  TextStyle(color: AppColors.placeholder, fontSize: 11.5),
              filled: true,
              fillColor: const Color(0xFF0D0D0D),
              contentPadding: const EdgeInsets.all(11),
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
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save UPI ID'),
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFF262626)),
          const SizedBox(height: 12),
          const Text('QR scanner image (optional)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
              'Upload your own payment QR image — students will scan this '
              'instead of the auto-generated QR.',
              style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
          const SizedBox(height: 11),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: _qrBusy ? null : _pickQr,
                  icon: const Icon(Icons.qr_code_2, size: 15),
                  label: Text(_qrBusy
                      ? 'Please wait…'
                      : (_qrUrl.isEmpty ? 'Upload QR image' : 'Replace QR')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDDDDDD),
                    side: const BorderSide(color: Color(0xFF3A3A3A)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
            if (_qrUrl.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: _qrBusy ? null : _removeQr,
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('Remove QR'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF9CA4),
                      side: const BorderSide(color: Color(0x8CF10B1D)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ]),
          if (_qrUrl.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Text('Your uploaded QR is active at checkout.',
                  style: TextStyle(color: Color(0xFF7ED98B), fontSize: 10)),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Earnings tab — reuses the food vendor earnings layout; the backend
// returns completed print orders for print partners.
// ----------------------------------------------------------------------
class _PrintEarningsTab extends StatelessWidget {
  const _PrintEarningsTab();

  @override
  Widget build(BuildContext context) {
    return const VendorEarningsScreen(inShell: true);
  }
}

// ----------------------------------------------------------------------
// Profile tab — business name + mobile number (editable), account info.
// Mirrors the food vendor profile styling.
// ----------------------------------------------------------------------
class _PrintProfileTab extends StatefulWidget {
  const _PrintProfileTab();

  @override
  State<_PrintProfileTab> createState() => _PrintProfileTabState();
}

class _PrintProfileTabState extends State<_PrintProfileTab> {
  TextEditingController? _name;
  TextEditingController? _phone;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name == null) {
      final vendor = context.read<AppStore>().vendor;
      _name = TextEditingController(text: vendor.businessName);
      _phone = TextEditingController(text: vendor.phone);
    }
  }

  @override
  void dispose() {
    _name?.dispose();
    _phone?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name?.text.trim() ?? '';
    if (name.isEmpty) {
      showCunnectToast(context, 'Business name cannot be empty.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    final err = await context.read<AppStore>().saveVendorProfile(
        businessName: name, phone: _phone?.text.trim() ?? '');
    if (!mounted) return;
    setState(() => _saving = false);
    showCunnectToast(context, err ?? 'Profile saved successfully.',
        error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final vendor = store.vendor;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
      children: [
        // ---- identity card ----
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [0, 0.62],
              colors: [Color(0xFF251014), Color(0xFF151515)],
            ),
          ),
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF310F14),
                border: Border.all(color: AppColors.red, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x38F10B1D), blurRadius: 18)
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                  vendor.businessName.length >= 2
                      ? vendor.businessName.substring(0, 2).toUpperCase()
                      : vendor.businessName.toUpperCase(),
                  style: const TextStyle(
                      color: Color(0xFFFF9DA5),
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 11),
            Text(vendor.businessName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Owner: ${vendor.ownerUsername}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 11),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: const Color(0x1738B765),
                border: Border.all(color: const Color(0x6B38B765)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                _GlowDot(),
                SizedBox(width: 6),
                Text('Active Print Partner',
                    style: TextStyle(
                        color: Color(0xFF98E6B0),
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ),
        // ---- editable profile ----
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Business Profile',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _label('Business / Shop Name'),
              TextField(
                controller: _name,
                style: const TextStyle(fontSize: 13),
                decoration: cunnectInputDecoration(),
              ),
              const SizedBox(height: 13),
              _label('Business Mobile Number'),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 13),
                decoration:
                    cunnectInputDecoration(placeholder: 'Enter mobile number'),
              ),
              const SizedBox(height: 13),
              _label('User ID'),
              _readOnly(vendor.ownerUsername),
              const SizedBox(height: 13),
              _label('Email Address'),
              _readOnly(vendor.email.isNotEmpty
                  ? vendor.email
                  : '${vendor.ownerUsername}@cunnect.app'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('SAVE PROFILE'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFFAAAAAA),
                fontSize: 10.5,
                fontWeight: FontWeight.w700)),
      );

  Widget _readOnly(String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF383838)),
        ),
        child: Text(value,
            style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
      );
}

class _GlowDot extends StatelessWidget {
  const _GlowDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.green,
        boxShadow: [BoxShadow(color: AppColors.green, blurRadius: 8)],
      ),
    );
  }
}

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
