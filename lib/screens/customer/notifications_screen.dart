import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadNotifications();
    });
    // Same as the Django view: opening the page marks everything read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().markAllRead(AppStore.customerUserId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = store.notificationsFor(AppStore.customerUserId);

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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notifications',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('Order updates from your food partners.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('No notifications yet',
                            style: TextStyle(
                                color: Color(0xFFEEEEEE), fontSize: 17, fontWeight: FontWeight.w700)),
                        SizedBox(height: 8),
                        Text('Partner order updates will show here.',
                            style: TextStyle(color: AppColors.muted, fontSize: 13)),
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
