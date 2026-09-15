import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../services/open_url.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// Room view — chat_room.html jaisa: header, pinned bar, messages, composer.
class ChatRoomScreen extends StatefulWidget {
  final String roomName;

  const ChatRoomScreen({super.key, required this.roomName});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _pollTimer;
  bool _firstLoadDone = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<AppStore>();
      await store.loadRoom(widget.roomName);
      if (!mounted) return;
      setState(() => _firstLoadDone = true);
      _scrollToBottom();
    });
    // Live poll — network app ke websocket ka light replacement.
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      context.read<AppStore>().loadRoom(widget.roomName);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController
            .jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _attach() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    final name = f.name.toLowerCase();
    final isVideo = name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.mkv');
    final isImage = name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
    setState(() => _sending = true);
    final error = await context.read<AppStore>().sendChatMessage(
          widget.roomName,
          _messageController.text.trim(),
          fileBytes: f.bytes,
          fileName: f.name,
          fileField: isVideo ? 'video' : (isImage ? 'image' : 'attachment'),
        );
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      showCunnectToast(context, error, error: true);
      return;
    }
    _messageController.clear();
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    final error = await context.read<AppStore>().sendChatMessage(widget.roomName, text);
    if (!mounted) return;
    if (error != null) {
      showCunnectToast(context, error, error: true);
    } else {
      _scrollToBottom();
    }
  }

  void _showPollSheet() {
    final questionController = TextEditingController();
    final optionControllers = [TextEditingController(), TextEditingController()];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 18, 18, MediaQuery.of(sheetContext).viewInsets.bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create Poll',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: questionController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Question',
                filled: true,
                fillColor: const Color(0xFF1B1B1B),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF303030))),
              ),
            ),
            const SizedBox(height: 10),
            for (final controller in optionControllers)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Option',
                    filled: true,
                    fillColor: const Color(0xFF1B1B1B),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF303030))),
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () async {
                  final question = questionController.text.trim();
                  final options = optionControllers
                      .map((c) => c.text.trim())
                      .where((o) => o.isNotEmpty)
                      .toList();
                  if (question.isEmpty || options.length < 2) {
                    showCunnectToast(sheetContext,
                        'Question + at least 2 options required', error: true);
                    return;
                  }
                  Navigator.of(sheetContext).pop();
                  final error = await context
                      .read<AppStore>()
                      .sendChatPoll(widget.roomName, question, options);
                  if (mounted && error != null) {
                    showCunnectToast(context, error, error: true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8000D),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                child: const Text('Post Poll'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final room = store.roomByName(widget.roomName);
    final red = const Color(0xFFE8000D);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(widget.roomName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                      if (room?.official ?? false)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: red.withOpacity(.16),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('OFFICIAL',
                                style: TextStyle(
                                    color: Color(0xFFFFB1B8),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                  Text('${room?.membersCount ?? 0} members · ${room?.onlineCount ?? 0} online',
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined, size: 19),
            onPressed: _showPollSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.4),
                  radius: .8,
                  colors: [red.withOpacity(.065), Colors.transparent],
                ),
              ),
              child: room == null || !_firstLoadDone
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFEC1C24), strokeWidth: 2))
                  : Stack(
                      children: [
                        ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
                          children: [
                            if (room.activePoll != null)
                              _PollCard(poll: room.activePoll!),
                            for (final message in room.messages)
                              _MessageCard(
                                message: message,
                                own: message.username == store.studentUid,
                                roomName: room.name,
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          _buildComposer(store, room),
        ],
      ),
    );
  }

  Widget _buildComposer(AppStore store, ChatRoom? room) {
    final joined = room?.isMember ?? true;
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
      decoration: const BoxDecoration(
        color: Color(0xFF101010),
        border: Border(top: BorderSide(color: Color(0xFF1F1F1F))),
      ),
      child: joined
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      hintStyle: TextStyle(color: AppColors.muted, fontSize: 12.5),
                      filled: true,
                      fillColor: const Color(0xFF181818),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: Color(0xFFE8000D)),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 9),
                GestureDetector(
                  onTap: _sending ? null : _attach,
                  child: Container(
                    width: 41,
                    height: 41,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF2A2A2A)),
                      color: const Color(0xFF181818),
                    ),
                    child: const Icon(Icons.attach_file,
                        size: 17, color: AppColors.muted),
                  ),
                ),
                const SizedBox(width: 9),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 41,
                    height: 41,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8000D),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send, size: 17, color: Colors.white),
                  ),
                ),
              ],
            )
          : SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed: () async {
                  final error =
                      await context.read<AppStore>().joinRoom(widget.roomName);
                  if (mounted && error != null) {
                    showCunnectToast(context, error, error: true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8000D),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(21)),
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                child: const Text('Request to Join'),
              ),
            ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final ChatMessage message;
  final bool own;
  final String roomName;

  const _MessageCard({
    required this.message,
    required this.own,
    required this.roomName,
  });

  String _time() {
    final dt = message.createdAt.toLocal();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
        decoration: BoxDecoration(
          color: own ? const Color(0xFF2A1215) : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: own
                  ? const Color(0x59E8000D)
                  : const Color(0xFF202020)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!own)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(message.displayName,
                    style: const TextStyle(
                        color: Color(0xFFFF9CA5),
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
            if (message.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CunnectImage(message.imageUrl,
                    width: 220, fit: BoxFit.cover),
              ),
            if (message.videoUrl.isNotEmpty)
              GestureDetector(
                onTap: () => openExternalUrl(message.videoUrl),
                child: Container(
                  width: 220,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF353535)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.play_circle_fill,
                          size: 34, color: AppColors.red),
                      SizedBox(height: 6),
                      Text('VIDEO · TAP TO PLAY',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
            if (message.content.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                    top: message.imageUrl.isNotEmpty ? 6 : 0),
                child: Text(message.content,
                    style: const TextStyle(
                        fontSize: 13, height: 1.35, color: Color(0xFFEFEFEF))),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => store.toggleChatLike(message.id, roomName),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          message.likedByMe
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 13,
                          color: message.likedByMe
                              ? const Color(0xFFE8000D)
                              : AppColors.muted),
                      if (message.likeCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text('${message.likeCount}',
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 10.5)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => store.togglePinMessage(message.id, roomName),
                  child: Icon(Icons.push_pin_outlined,
                      size: 13,
                      color: message.pinned
                          ? const Color(0xFFE8000D)
                          : AppColors.muted),
                ),
                const Spacer(),
                Text(_time(),
                    style: TextStyle(color: AppColors.muted, fontSize: 9.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  final ChatPoll poll;

  const _PollCard({required this.poll});

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final total = poll.totalVotes;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x40E8000D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, size: 15, color: Color(0xFFE8000D)),
              const SizedBox(width: 7),
              const Text('POLL',
                  style: TextStyle(
                      color: Color(0xFFE8000D),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const Spacer(),
              Text('$total votes',
                  style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text(poll.question,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final option in poll.options)
            GestureDetector(
              onTap: option.votedByMe
                  ? null
                  : () => store.votePoll(poll.id, option.id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: option.votedByMe
                      ? const Color(0x26E8000D)
                      : const Color(0xFF1B1B1B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: option.votedByMe
                          ? const Color(0x80E8000D)
                          : const Color(0xFF2A2A2A)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(option.text,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                    Text(
                        total == 0
                            ? '0%'
                            : '${(option.votes / total * 100).round()}%',
                        style: TextStyle(
                            color: option.votedByMe
                                ? const Color(0xFFFF9CA5)
                                : AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
