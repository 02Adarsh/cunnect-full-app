import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// Yearly Earnings — same layout as vendor_earnings.html.
class VendorEarningsScreen extends StatefulWidget {
  final bool inShell;

  const VendorEarningsScreen({super.key, this.inShell = false});

  @override
  State<VendorEarningsScreen> createState() => _VendorEarningsScreenState();
}

class _VendorEarningsScreenState extends State<VendorEarningsScreen> {
  int? _selectedYear;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadVendorEarnings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final years = store.availableYears;
    final year = _selectedYear ?? years.first;

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
            padding: EdgeInsets.fromLTRB(16, 0, 16, 35 + MediaQuery.of(context).padding.bottom),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 22, 0, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Yearly Earnings',
                              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -.7)),
                          SizedBox(height: 4),
                          Text('Completed orders and historical daily sales',
                              style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFF393939)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: year,
                          icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.muted),
                          dropdownColor: const Color(0xFF1C1C1C),
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          items: [
                            for (final y in years)
                              DropdownMenuItem(value: y, child: Text('$y')),
                          ],
                          onChanged: (value) => setState(() => _selectedYear = value),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _stat('$year SALES', '₹${store.yearlyTotal(year).round()}', 'All completed orders'),
                  const SizedBox(width: 10),
                  _stat('COMPLETED ORDERS', '${store.completedOrderCount(year)}', 'Delivered successfully'),
                  const SizedBox(width: 10),
                  _stat('AVG ORDER VALUE', '₹${store.averageOrderValue(year).round()}', 'Per completed order'),
                ],
              ),
              const SizedBox(height: 16),
              Panel(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 15, 14, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Monthly Sales · $year',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          const Text('Tap a bar for amount',
                              style: TextStyle(color: AppColors.muted, fontSize: 10)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
                      child: SizedBox(
                        height: 180,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final entry in store.monthlySales(year))
                              Expanded(child: _MonthBar(entry: entry, max: _maxMonthly(store, year))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Panel(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 15, 14, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('Previous Earnings',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          Text('Latest 12 delivered orders',
                              style: TextStyle(color: AppColors.muted, fontSize: 10)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: store.recentEarnings(year).isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 25),
                              child: Text('No completed sales for $year yet.',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < store.recentEarnings(year).length; i++)
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      border: i > 0
                                          ? const Border(top: BorderSide(color: AppColors.line))
                                          : null,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(store.recentEarnings(year)[i].orderNumber,
                                                  style: const TextStyle(
                                                      fontSize: 11, fontWeight: FontWeight.w700)),
                                              const SizedBox(height: 3),
                                              Text(
                                                  '${store.recentEarnings(year)[i].customerName} · ${_formatDate(store.recentEarnings(year)[i].deliveredAt ?? store.recentEarnings(year)[i].updatedAt)}',
                                                  style: const TextStyle(
                                                      color: AppColors.muted, fontSize: 10)),
                                            ],
                                          ),
                                        ),
                                        Text('₹${store.recentEarnings(year)[i].totalAmount.round()}',
                                            style: const TextStyle(
                                                color: Color(0xFF8BDDAA),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    // Standalone pushes need their own Scaffold (yellow-underline fix).
    if (widget.inShell) return body;
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(bottom: false, child: body),
    );
  }

  double _maxMonthly(AppStore store, int year) =>
      store.monthlySales(year).fold<double>(0, (m, e) => e.value > m ? e.value : m);

  Widget _stat(String label, String value, String note) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 94),
        padding: const EdgeInsets.fromLTRB(9, 12, 9, 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.muted, fontSize: 8.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.6)),
            ),
            const SizedBox(height: 4),
            Text(note, style: const TextStyle(color: Color(0xFF8BDDAA), fontSize: 8.5)),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    var hour = dateTime.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dateTime.hour < 12 ? 'AM' : 'PM';
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}, $hour:$minute $ampm';
  }
}

class _MonthBar extends StatefulWidget {
  final MapEntry<String, double> entry;
  final double max;

  const _MonthBar({required this.entry, required this.max});

  @override
  State<_MonthBar> createState() => _MonthBarState();
}

class _MonthBarState extends State<_MonthBar> {
  bool _showAmount = false;

  @override
  Widget build(BuildContext context) {
    final double height = widget.max > 0 ? (widget.entry.value / widget.max) * 130 : 5.0;

    return GestureDetector(
      onTap: () => setState(() => _showAmount = !_showAmount),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: double.infinity,
                  height: height < 5 ? 5.0 : height,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFF33B4B), Color(0xFF940B16)],
                    ),
                    boxShadow: const [BoxShadow(color: Color(0x2EF10B1D), blurRadius: 12)],
                  ),
                ),
                const SizedBox(height: 23),
              ],
            ),
            Positioned(
              bottom: -20,
              child: Text(widget.entry.key,
                  style: const TextStyle(color: Color(0xFF777777), fontSize: 8)),
            ),
            if (_showAmount)
              Positioned(
                bottom: height + 28,
                child: Text('₹${widget.entry.value.round()}',
                    style: const TextStyle(
                        color: Color(0xFFFFABB2), fontSize: 9, fontWeight: FontWeight.w800)),
              ),
          ],
        ),
      ),
    );
  }
}
