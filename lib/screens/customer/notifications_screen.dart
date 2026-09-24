import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  /// ⭐ if opened from the vendor portal, show vendor notifications only
  final bool forVendor;

  /// ⭐ v84: when set, only rows of this category are listed — the food
  /// bell passes 'food' so ride / auto / print / hostel rows stay out.
  final String? category;

  const NotificationsScreen(
      {super.key, this.forVendor = false, this.category});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int get _userId =>
      widget.forVendor ? AppStore.vendorUserId : AppStore.customerUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = context.read<AppStore>();
      if (widget.forVendor) {
        store.loadVendorNotifications();
      } else {
        store.loadNotifications();
      }
    });
    // Same as the Django view: opening the page marks everything read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().markAllRead(_userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final all = store.notificationsFor(_userId);
    final items = category == null
        ? all
        : [for (final n in all) if (n.category == category) n];

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const CunnectHeader(),
          Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 21, 14, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Notifications',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    widget.forVendor
                        ? 'New orders and updates for your kitchen.'
                        : 'Order updates from your food partners.',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No notifications yet',
                            style: TextStyle(
                                color: Color(0xFFEEEEEE), fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                            widget.forVendor
                                ? 'New order alerts will show here.'
                                : 'Partner order updates will show here.',
                            style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 0, thickness: 1, color: AppColors.line),
                    itemBuilder: (context, index) {
                      final notification = items[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 31,
                              height: 31,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0x21F10B1D),
                              ),
                              alignment: Alignment.center,
                              child: const Text('●',
                                  style: TextStyle(color: Color(0xFFFF9CA4), fontSize: 12)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(notification.title,
                                      style: const TextStyle(
                                          color: Color(0xFFF1F1F1),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text(notification.message,
                                      style: const TextStyle(
                                          color: AppColors.muted, fontSize: 11.5, height: 1.4)),
                                  const SizedBox(height: 5),
                                  Text(_timeAgo(notification.createdAt),
                                      style: const TextStyle(color: Color(0xFF747474), fontSize: 10)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
        ]),
      ),);
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes';
    if (diff.inHours < 24) return '${diff.inHours} hours';
    return '${diff.inDays} days';
  }
}
