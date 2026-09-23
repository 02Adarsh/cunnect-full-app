import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import 'chat_room_screen.dart';

/// Chatrooms list — same design as network/chat_home.html
/// (page #0d0d0d, card #101010, accent #e8000d, online #31c67a).
class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadChatRooms();
    });
  }

  static const Color accent = Color(0xFFE8000D);
  static const Color online = Color(0xFFF5F5F5);
  static const Color page = Color(0xFF0D0D0D);
  static const Color card = Color(0xFF101010);

  bool _searchVisible = false;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final rooms = store.chatRooms
        .where((room) =>
            _query.isEmpty || room.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 430),
            color: page,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 28, 18, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Chatrooms',
                          style: TextStyle(
                              fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -1.1)),
                      Row(
                        children: [
                          _circleButton(
                            icon: Icons.search,
                            borderColor: Colors.white.withOpacity(.1),
                            iconColor: Colors.white,
                            onTap: () => setState(() => _searchVisible = !_searchVisible),
                          ),
                          const SizedBox(width: 12),
                          _circleButton(
                            icon: Icons.add,
                            borderColor: accent,
                            iconColor: accent,
                            onTap: _openCreateModal,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_searchVisible)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      onChanged: (value) => setState(() => _query = value),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search chatrooms...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(.35)),
                        filled: true,
                        fillColor: const Color(0xFF151515),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accent),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: rooms.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accent.withOpacity(.1),
                                ),
                                alignment: Alignment.center,
                                child: const Text('#',
                                    style: TextStyle(
                                        color: accent, fontSize: 24, fontWeight: FontWeight.w800)),
                              ),
                              const Text('No chatrooms found.',
                                  style: TextStyle(color: Colors.white54, fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 48),
                          itemCount: rooms.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 11),
                          itemBuilder: (context, index) =>
                              _RoomCard(room: rooms[index], isFirst: index == 0 && _query.isEmpty),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Color borderColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 17, color: iconColor),
      ),
    );
  }

  void _openCreateModal() {
    final nameController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create a Chatroom',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Your group will be visible to all campus users.',
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(.45))),
              const SizedBox(height: 20),
              const Text('ROOM NAME',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: Colors.white38)),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Boys Hostel',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(.3)),
                  filled: true,
                  fillColor: page,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: accent),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('PRIVACY',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: Colors.white38)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: page,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(.1)),
                ),
                child: const Text('Campus Public', style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(sheetContext).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Text('Cancel',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (nameController.text.trim().isNotEmpty) {
                          context.read<AppStore>().createChatRoom(nameController.text, 'public');
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Text('Create',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final ChatRoom room;
  final bool isFirst;

  const _RoomCard({required this.room, required this.isFirst});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE8000D);

    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ChatRoomScreen(roomName: room.name))),
      child: Container(
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: isFirst ? accent : Colors.white.withOpacity(.1), width: isFirst ? 1.5 : 1),
          gradient: isFirst
              ? LinearGradient(colors: [const Color(0x1AB71C1C), Colors.transparent])
              : null,
          color: isFirst ? null : const Color(0xFF101010),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x33B91C1C),
              ),
              alignment: Alignment.center,
              child: Text(room.name.isNotEmpty ? room.name[0].toUpperCase() : '#',
                  style: const TextStyle(
                      color: accent, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -.25)),
                      ),
                      if (room.official) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(.15),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text('OFFICIAL',
                              style: TextStyle(
                                  color: accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .55)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text('${room.membersCount} members',
                          style: TextStyle(
                              fontSize: 10, color: Colors.white.withOpacity(.5))),
                      Text(' • ', style: TextStyle(color: Colors.white.withOpacity(.25))),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Color(0xFFF5F5F5)),
                      ),
                      const SizedBox(width: 4),
                      Text('${room.onlineCount} online',
                          style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 19, color: Colors.white.withOpacity(.35)),
          ],
        ),
      ),
    );
  }
}
