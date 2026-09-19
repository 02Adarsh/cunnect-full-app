import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../../widgets/feed_video.dart';

/// ⭐ CUnnect Feed — one mixed channel (announcements, media and polls,
/// newest first). Pinned posts (WhatsApp-style, up to 15) live behind the
/// "View Pinned content" bar under the tagline. Every post sits in its own
/// rounded card with clear spacing, media keeps its original aspect ratio,
/// and comments support replies, reactions and deleting your own.
class CunnectFeedScreen extends StatefulWidget {
  const CunnectFeedScreen({super.key});

  @override
  State<CunnectFeedScreen> createState() => _CunnectFeedScreenState();
}

class _CunnectFeedScreenState extends State<CunnectFeedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppStore>().loadNotices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    // ---- notices + polls -> one mixed feed (newest first) ----
    final items = <FeedEntry>[
      for (final n in store.notices) FeedEntry.notice(n),
      for (final p in store.polls) FeedEntry.poll(p),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final pinned = items.where((e) => e.pinned).toList();

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const CunnectHeader(),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
            alignment: Alignment.centerLeft,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CUnnect Feed',
                    style:
                        TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('Stay updated and CUnnected',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          // ---- ⭐ pinned bar (WhatsApp-style) ----
          if (pinned.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _PinnedBar(
                count: pinned.length,
                onTap: () => _openPinned(context, pinned),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.red,
              backgroundColor: const Color(0xFF1B1B1B),
              onRefresh: () => store.loadNotices(),
              child: store.noticesLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.red))
                  : items.isEmpty
                      ? _empty()
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 30),
                          itemCount: items.length,
                          itemBuilder: (context, i) =>
                              FeedCard(entry: items[i]),
                        ),
            ),
          ),
        ]),
      ),
    );
  }

  void _openPinned(BuildContext context, List<FeedEntry> pinned) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _PinnedFeedScreen(entries: pinned)));
  }

  Widget _empty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Center(
          child: Column(children: [
            Text('Feed is quiet right now',
                style: TextStyle(
                    color: Color(0xFFEEEEEE),
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 7),
            Text('Campus updates and polls will show here.',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// ⭐ Pinned bar — horizontal tab: 📌  View Pinned content  (x)
// ----------------------------------------------------------------------
class _PinnedBar extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _PinnedBar({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x59F10B1D)),
          boxShadow: const [
            BoxShadow(color: Color(0x14F10B1D), blurRadius: 18),
          ],
        ),
        child: Row(children: [
          const Text('📌', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 9),
          const Text('View Pinned content',
              style: TextStyle(
                  color: Color(0xFFF3F3F3),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0x26F10B1D),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: const Color(0x59F10B1D)),
            ),
            child: Text('$count',
                style: const TextStyle(
                    color: Color(0xFFFF9CA4),
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded,
              size: 19, color: Color(0xFF8A8A8A)),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// ⭐ Pinned posts screen — same cards, pinned only.
// ----------------------------------------------------------------------
class _PinnedFeedScreen extends StatelessWidget {
  final List<FeedEntry> entries;

  const _PinnedFeedScreen({required this.entries});

  @override
  Widget build(BuildContext context) {
    // Rebuild from the store so reactions/votes stay live on this screen.
    final store = context.watch<AppStore>();
    final items = <FeedEntry>[
      for (final n in store.notices)
        if (n.pinned) FeedEntry.notice(n),
      for (final p in store.polls)
        if (p.pinned) FeedEntry.poll(p),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const CunnectHeader(useWordmark: false),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            alignment: Alignment.centerLeft,
            child: Row(children: [
              const Text('📌', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              const Text('Pinned content',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x26F10B1D),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: const Color(0x59F10B1D)),
                ),
                child: Text('${items.length}',
                    style: const TextStyle(
                        color: Color(0xFFFF9CA4),
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('Nothing is pinned right now.',
                        style:
                            TextStyle(color: AppColors.muted, fontSize: 12)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 30),
                    itemCount: items.length,
                    itemBuilder: (context, i) => FeedCard(entry: items[i]),
                  ),
          ),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// ⭐ Mixed feed entry — a notice or a poll in one card shell.
// ----------------------------------------------------------------------
class FeedEntry {
  final CampusNotice? notice;
  final AppPollModel? poll;

  FeedEntry.notice(this.notice) : poll = null;
  FeedEntry.poll(this.poll) : notice = null;

  bool get isPoll => poll != null;
  String get kind => isPoll ? 'poll' : 'notice';
  int get id => isPoll ? poll!.id : notice!.id;
  DateTime get createdAt => isPoll ? poll!.createdAt : notice!.createdAt;
  String get imageUrl => isPoll ? poll!.imageUrl : notice!.imageUrl;
  String get videoUrl => isPoll ? poll!.videoUrl : notice!.videoUrl;
  bool get pinned => isPoll ? poll!.pinned : notice!.pinned;
  FeedSocial get social => isPoll ? poll!.social : notice!.social;
}

// ----------------------------------------------------------------------
// ⭐ Feed card — rounded box, clear spacing between posts.
// Header (CUnnect + red tick) -> text -> media (original ratio) ->
// poll options (below media) -> social summary -> React | Comment row.
// ----------------------------------------------------------------------
class FeedCard extends StatelessWidget {
  final FeedEntry entry;

  const FeedCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final social = entry.social;
    final hasText = entry.isPoll
        ? entry.poll!.question.isNotEmpty
        : (entry.notice!.title.isNotEmpty ||
            entry.notice!.message.isNotEmpty);
    final hasMedia = entry.videoUrl.isNotEmpty || entry.imageUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.35),
              blurRadius: 14,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -------- header: CUnnect + red tick + time (+ pin mark) --------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x26F10B1D),
                  border: Border.all(color: const Color(0x59F10B1D)),
                ),
                child: const Text('C',
                    style: TextStyle(
                        color: Color(0xFFFF9CA4),
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Text('CUnnect',
                          style: TextStyle(
                              color: Color(0xFFF3F3F3),
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      SizedBox(width: 4),
                      Icon(Icons.verified, size: 13, color: Color(0xFFF10B1D)),
                    ]),
                    const SizedBox(height: 2),
                    Text(_timeAgo(entry.createdAt),
                        style: const TextStyle(
                            color: Color(0xFF747474), fontSize: 10)),
                  ],
                ),
              ),
              if (entry.pinned)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('📌', style: TextStyle(fontSize: 13)),
                ),
            ]),
          ),
          // -------- text --------
          if (hasText)
            Padding(
              padding: EdgeInsets.fromLTRB(12, 11, 12, hasMedia ? 11 : 12),
              child: entry.isPoll
                  ? _PollQuestion(poll: entry.poll!)
                  : _NoticeBody(notice: entry.notice!),
            )
          else
            SizedBox(height: hasMedia ? 11 : 4),
          // -------- media — ORIGINAL aspect ratio, never cropped --------
          if (entry.videoUrl.isNotEmpty)
            feedVideo(entry.videoUrl)
          else if (entry.imageUrl.isNotEmpty)
            _NaturalImage(url: entry.imageUrl),
          // -------- poll options (always BELOW the media) --------
          if (entry.isPoll)
            Padding(
              padding: EdgeInsets.fromLTRB(12, hasMedia ? 12 : 0, 12, 4),
              child: _PollOptions(poll: entry.poll!),
            ),
          // -------- social summary --------
          if (social.totalReactions > 0 || social.commentCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              child: Row(children: [
                if (social.totalReactions > 0) ...[
                  Text(_topEmojis(social),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 5),
                  Text('${social.totalReactions}',
                      style: const TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
                const Spacer(),
                if (social.commentCount > 0)
                  InkWell(
                    onTap: () => _openComments(context),
                    child: Text(
                        '${social.commentCount} comment${social.commentCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: Color(0xFF9A9A9A), fontSize: 11)),
                  ),
              ]),
            )
          else
            const SizedBox(height: 8),
          // -------- action row --------
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Row(children: [
              _action(
                context,
                icon: social.myReaction.isEmpty
                    ? const Icon(Icons.add_reaction_outlined,
                        size: 16, color: Color(0xFF9A9A9A))
                    : Text(social.myReaction,
                        style: const TextStyle(fontSize: 15)),
                label: social.myReaction.isEmpty ? 'React' : 'Reacted',
                highlighted: social.myReaction.isNotEmpty,
                onTap: () => _openReactionPicker(context),
              ),
              Container(width: 1, height: 26, color: AppColors.line),
              _action(
                context,
                icon: const Icon(Icons.mode_comment_outlined,
                    size: 15, color: Color(0xFF9A9A9A)),
                label: 'Comment',
                highlighted: false,
                onTap: () => _openComments(context),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  String _topEmojis(FeedSocial social) {
    final entries = social.reactions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(3).map((e) => e.key).join(' ');
  }

  Widget _action(BuildContext context,
      {required Widget icon,
      required String label,
      required bool highlighted,
      required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: highlighted
                          ? const Color(0xFFFF9CA4)
                          : const Color(0xFF9A9A9A),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------ reactions
  void _openReactionPicker(BuildContext context) {
    final store = context.read<AppStore>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161616),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ReactionPickerSheet(
        current: entry.social.myReaction,
        onPick: (emoji) => store.reactToFeed(entry.kind, entry.id, emoji),
      ),
    );
  }

  // ------------------------------------------------ comments
  void _openComments(BuildContext context) {
    final store = context.read<AppStore>();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'comments',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) => _CommentsOverlay(
        kind: entry.kind,
        objectId: entry.id,
        store: store,
      ),
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(0, .12), end: Offset.zero)
              .animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// ⭐ Image at its ORIGINAL aspect ratio — full card width, no cropping.
// ----------------------------------------------------------------------
class _NaturalImage extends StatelessWidget {
  final String url;

  const _NaturalImage({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty || !url.startsWith('http')) {
      return const SizedBox.shrink();
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: double.infinity,
      fit: BoxFit.fitWidth,
      fadeInDuration: Duration.zero,
      placeholder: (_, __) => AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: const Color(0xFF101010),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF3A3A3A)),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: const Color(0xFF101010),
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined,
              color: Color(0xFF3A3A3A), size: 24),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
class _NoticeBody extends StatelessWidget {
  final CampusNotice notice;

  const _NoticeBody({required this.notice});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (notice.title.isNotEmpty)
          Text(notice.title,
              style: const TextStyle(
                  color: Color(0xFFF3F3F3),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800)),
        if (notice.message.isNotEmpty) ...[
          if (notice.title.isNotEmpty) const SizedBox(height: 6),
          // ⭐ v72: shared links show up RED and open on a single tap.
          LinkText(notice.message,
              style: const TextStyle(
                  color: Color(0xFFBBBBBB), fontSize: 12, height: 1.5)),
        ],
      ],
    );
  }
}

// ----------------------------------------------------------------------
class _PollQuestion extends StatelessWidget {
  final AppPollModel poll;

  const _PollQuestion({required this.poll});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(poll.question,
            style: const TextStyle(
                color: Color(0xFFF3F3F3),
                fontSize: 14.5,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${poll.totalVotes} vote${poll.totalVotes == 1 ? '' : 's'}',
            style: const TextStyle(color: Color(0xFF747474), fontSize: 10)),
      ],
    );
  }
}

// ----------------------------------------------------------------------
class _PollOptions extends StatelessWidget {
  final AppPollModel poll;

  const _PollOptions({required this.poll});

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final voted = poll.myOptionId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in poll.options)
          _PollOptionTile(
            option: option,
            poll: poll,
            voted: voted,
            onVote: () async {
              final err = await store.voteAppPoll(poll.id, option.id);
              if (err != null && context.mounted) {
                showCunnectToast(context, err, error: true);
              }
            },
          ),
        if (voted)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Tap another option to change your vote.',
                style: TextStyle(color: Color(0xFF6E6E6E), fontSize: 10)),
          ),
      ],
    );
  }
}

class _PollOptionTile extends StatelessWidget {
  final AppPollOptionModel option;
  final AppPollModel poll;
  final bool voted;
  final VoidCallback onVote;

  const _PollOptionTile(
      {required this.option,
      required this.poll,
      required this.voted,
      required this.onVote});

  @override
  Widget build(BuildContext context) {
    final isMine = poll.myOptionId == option.id;
    final pct = poll.totalVotes == 0 ? 0.0 : option.votes / poll.totalVotes;

    return GestureDetector(
      onTap: onVote,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: isMine ? const Color(0xB3F10B1D) : const Color(0xFF2E2E2E),
              width: isMine ? 1.4 : 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(children: [
            if (voted)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct.clamp(0.0, 1.0),
                  child: Container(
                      color: isMine
                          ? const Color(0x30F10B1D)
                          : const Color(0x1AFFFFFF)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(children: [
                if (option.imageUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: CunnectImage(option.imageUrl, width: 38, height: 38),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(option.text,
                      style: TextStyle(
                          color: isMine
                              ? const Color(0xFFFFC2C7)
                              : const Color(0xFFDDDDDD),
                          fontSize: 12.5,
                          fontWeight:
                              isMine ? FontWeight.w800 : FontWeight.w600)),
                ),
                if (voted)
                  Text('${(pct * 100).round()}%',
                      style: TextStyle(
                          color: isMine
                              ? const Color(0xFFFF9CA4)
                              : const Color(0xFF9A9A9A),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800))
                else
                  const Icon(Icons.radio_button_unchecked,
                      size: 15, color: Color(0xFF555555)),
                if (isMine) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_circle,
                      size: 15, color: Color(0xFFF10B1D)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// ⭐ Reaction picker — quick bar + FULL emoji grid (WhatsApp-style,
// pick any emoji). Tapping your current reaction again removes it.
// ----------------------------------------------------------------------
class ReactionPickerSheet extends StatelessWidget {
  final String current;
  final void Function(String emoji) onPick;

  const ReactionPickerSheet(
      {super.key, required this.current, required this.onPick});

  static const _quick = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

  static const _all = [
    // smileys
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
    '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚',
    '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🥸',
    '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '☹️',
    '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😤', '😠', '😡',
    '🤬', '🤯', '😳', '🥵', '🥶', '😱', '😨', '😰', '😥', '😓',
    '🤗', '🤔', '🤭', '🤫', '🤥', '😶', '😐', '😑', '😬', '🙄',
    '😯', '😦', '😧', '😮', '😲', '🥱', '😴', '🤤', '😪', '😵',
    '🤐', '🥴', '🤢', '🤮', '🤧', '😷', '🤒', '🤕', '🤑', '🤠',
    // gestures & people
    '👍', '👎', '👌', '🤌', '✌️', '🤞', '🤟', '🤘', '🤙', '👈',
    '👉', '👆', '👇', '☝️', '👏', '🙌', '👐', '🤲', '🤝', '🙏',
    '✊', '👊', '🤛', '🤜', '💪', '🫶', '👀', '🧠', '🗣️', '💃',
    // hearts
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
    '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '♥️',
    // symbols & celebration
    '🔥', '✨', '⭐', '🌟', '💫', '⚡', '💥', '💯', '✅', '❌',
    '🎉', '🎊', '🎈', '🎂', '🎁', '🏆', '🥇', '🥈', '🥉', '🎯',
    // food
    '🍕', '🍔', '🍟', '🌭', '🍿', '🥪', '🌮', '🌯', '🍜', '🍝',
    '🍛', '🍚', '🍱', '🥗', '🍩', '🍪', '🍰', '🧁', '🍫', '🍬',
    '☕', '🍵', '🥤', '🧃', '🍦', '🍧', '🍨', '🥞', '🧇', '🍳',
    // activities & objects
    '⚽', '🏀', '🏏', '🎮', '🎧', '🎵', '🎶', '📚', '📝', '💻',
    '📱', '📸', '🎬', '🚀', '✈️', '🚗', '🏠', '🌈', '🌙', '☀️',
    '🌸', '🌹', '🌻', '🍀', '🎓', '💡', '🔔', '📢', '📣', '🗳️',
  ];

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.5;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          // ---- quick reactions ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final emoji in _quick)
                InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () {
                    Navigator.of(context).pop();
                    onPick(emoji);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: current == emoji
                          ? const Color(0x26F10B1D)
                          : const Color(0xFF1E1E1E),
                      border: Border.all(
                          color: current == emoji
                              ? const Color(0x8CF10B1D)
                              : const Color(0xFF2E2E2E)),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 21)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.line),
          const SizedBox(height: 4),
          // ---- full emoji grid ----
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8),
              itemCount: _all.length,
              itemBuilder: (context, i) {
                final emoji = _all[i];
                final mine = current == emoji;
                return InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () {
                    Navigator.of(context).pop();
                    onPick(emoji);
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: mine
                        ? BoxDecoration(
                            color: const Color(0x26F10B1D),
                            borderRadius: BorderRadius.circular(9))
                        : null,
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// ⭐ Comments overlay — 75% height sheet, top 25% blurred; swipe-down
// dismiss. Comments support replies (one level), emoji reactions and
// deleting your own comment (long-press or the ⋯ affordances).
// ----------------------------------------------------------------------
class _CommentsOverlay extends StatefulWidget {
  final String kind;
  final int objectId;
  final AppStore store;

  const _CommentsOverlay(
      {required this.kind, required this.objectId, required this.store});

  @override
  State<_CommentsOverlay> createState() => _CommentsOverlayState();
}

class _CommentsOverlayState extends State<_CommentsOverlay> {
  final _controller = TextEditingController();
  final _inputFocus = FocusNode();
  List<FeedCommentModel> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  bool _popped = false;
  FeedCommentModel? _replyTo; // set while composing a reply

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final comments =
        await widget.store.loadFeedComments(widget.kind, widget.objectId);
    if (!mounted) return;
    setState(() {
      _comments = comments;
      _loading = false;
    });
  }

  int get _totalCount {
    var total = 0;
    for (final c in _comments) {
      total += 1 + c.replies.length;
    }
    return total;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final updated = await widget.store.addFeedComment(
        widget.kind, widget.objectId, text,
        parentId: _replyTo?.id);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (updated != null) {
        _comments = updated;
        _controller.clear();
        _replyTo = null;
      }
    });
    if (updated == null) {
      showCunnectToast(context, 'Could not post your comment. Try again.',
          error: true);
    }
  }

  void _startReply(FeedCommentModel comment) {
    setState(() => _replyTo = comment);
    _inputFocus.requestFocus();
  }

  Future<void> _react(FeedCommentModel comment) async {
    final updated = await showModalBottomSheet<List<FeedCommentModel>?>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => ReactionPickerSheet(
        current: comment.myReaction,
        onPick: (emoji) async {
          final result = await widget.store.reactToFeedComment(
              widget.kind, widget.objectId, comment.id, emoji);
          if (result != null && mounted) {
            setState(() => _comments = result);
          }
        },
      ),
    );
    if (updated != null && mounted) setState(() => _comments = updated);
  }

  Future<void> _delete(FeedCommentModel comment) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete comment?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        content: const Text(
            'This removes your comment (and any replies to it) for everyone.',
            style: TextStyle(
                color: AppColors.muted, fontSize: 12, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Color(0xFFFF9CA4),
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final updated = await widget.store
        .deleteFeedComment(widget.kind, widget.objectId, comment.id);
    if (!mounted) return;
    if (updated != null) {
      setState(() => _comments = updated);
    } else {
      showCunnectToast(context, 'Could not delete the comment.', error: true);
    }
  }

  void _dismiss() {
    if (_popped) return;
    _popped = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        // ---- blurred backdrop (top 25% visible under blur) ----
        Positioned.fill(
          child: GestureDetector(
            onTap: _dismiss,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3.2, sigmaY: 3.2),
              child: Container(color: Colors.black.withOpacity(.35)),
            ),
          ),
        ),
        // ---- 75% sheet ----
        NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            if (n.extent <= n.minExtent + 0.02) _dismiss();
            return false;
          },
          child: DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.35,
            maxChildSize: 0.92,
            snap: true,
            builder: (context, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Color(0xFF141414),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                    top: BorderSide(color: Color(0xFF2E2E2E)),
                    left: BorderSide(color: Color(0xFF2E2E2E)),
                    right: BorderSide(color: Color(0xFF2E2E2E))),
              ),
              child: Column(children: [
                const SizedBox(height: 10),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3A),
                        borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
                  child: Row(children: [
                    const Text('Comments',
                        style: TextStyle(
                            color: Color(0xFFF3F3F3),
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 7),
                    if (!_loading)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF232323),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text('$_totalCount',
                            style: const TextStyle(
                                color: Color(0xFF9A9A9A),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800)),
                      ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: _dismiss,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            size: 18, color: Color(0xFF8A8A8A)),
                      ),
                    ),
                  ]),
                ),
                Container(height: 1, color: AppColors.line),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.red)))
                      : _comments.isEmpty
                          ? ListView(
                              controller: scrollController,
                              children: const [
                                SizedBox(height: 70),
                                Center(
                                  child: Column(children: [
                                    Icon(Icons.mode_comment_outlined,
                                        size: 30, color: Color(0xFF3E3E3E)),
                                    SizedBox(height: 10),
                                    Text('No comments yet',
                                        style: TextStyle(
                                            color: Color(0xFFDDDDDD),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                    SizedBox(height: 4),
                                    Text('Be the first one to comment!',
                                        style: TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 11)),
                                  ]),
                                ),
                              ],
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              itemCount: _comments.length,
                              itemBuilder: (context, i) => _CommentThread(
                                comment: _comments[i],
                                onReply: _startReply,
                                onReact: _react,
                                onDelete: _delete,
                              ),
                            ),
                ),
                // ---- reply banner ----
                if (_replyTo != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1B1B1B),
                      border:
                          Border(top: BorderSide(color: Color(0xFF2A2A2A))),
                    ),
                    child: Row(children: [
                      const Icon(Icons.reply_rounded,
                          size: 14, color: Color(0xFFFF9CA4)),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                            'Replying to ${_replyTo!.mine ? 'yourself' : _replyTo!.user}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFFBBBBBB),
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => setState(() => _replyTo = null),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded,
                              size: 15, color: Color(0xFF8A8A8A)),
                        ),
                      ),
                    ]),
                  ),
                // ---- input row ----
                Container(
                  padding: EdgeInsets.fromLTRB(12, 9, 12,
                      9 + MediaQuery.of(context).viewInsets.bottom),
                  decoration: BoxDecoration(
                    color: const Color(0xFF191919),
                    border: _replyTo == null
                        ? const Border(
                            top: BorderSide(color: Color(0xFF2A2A2A)))
                        : null,
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(children: [
                      Expanded(
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 13),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121212),
                            borderRadius: BorderRadius.circular(22),
                            border:
                                Border.all(color: const Color(0xFF2E2E2E)),
                          ),
                          child: TextField(
                            controller: _controller,
                            focusNode: _inputFocus,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 600,
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFFEDEDED)),
                            decoration: InputDecoration(
                              hintText: _replyTo == null
                                  ? 'Write a comment…'
                                  : 'Write a reply…',
                              hintStyle: const TextStyle(
                                  color: Color(0xFF6E6E6E), fontSize: 12),
                              counterText: '',
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: _send,
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                              color: AppColors.red, shape: BoxShape.circle),
                          child: _sending
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded,
                                  size: 17, color: Colors.white),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ----------------------------------------------------------------------
// ⭐ Comment thread — a top-level comment with its replies indented.
// ----------------------------------------------------------------------
class _CommentThread extends StatelessWidget {
  final FeedCommentModel comment;
  final void Function(FeedCommentModel) onReply;
  final void Function(FeedCommentModel) onReact;
  final void Function(FeedCommentModel) onDelete;

  const _CommentThread(
      {required this.comment,
      required this.onReply,
      required this.onReact,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommentTile(
          comment: comment,
          isReply: false,
          onReply: () => onReply(comment),
          onReact: () => onReact(comment),
          onDelete: comment.mine ? () => onDelete(comment) : null,
        ),
        for (final reply in comment.replies)
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: _CommentTile(
              comment: reply,
              isReply: true,
              onReply: () => onReply(comment),
              onReact: () => onReact(reply),
              onDelete: reply.mine ? () => onDelete(reply) : null,
            ),
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final FeedCommentModel comment;
  final bool isReply;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback? onDelete;

  const _CommentTile(
      {required this.comment,
      required this.isReply,
      required this.onReply,
      required this.onReact,
      this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isReply ? 26 : 30,
            height: isReply ? 26 : 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: comment.mine
                  ? const Color(0x26F10B1D)
                  : const Color(0xFF232323),
              border: Border.all(
                  color: comment.mine
                      ? const Color(0x59F10B1D)
                      : const Color(0xFF313131)),
            ),
            child: Text(
                comment.user.isNotEmpty ? comment.user[0].toUpperCase() : '?',
                style: TextStyle(
                    color: comment.mine
                        ? const Color(0xFFFF9CA4)
                        : const Color(0xFFBBBBBB),
                    fontSize: isReply ? 11 : 12.5,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(comment.mine ? 'You' : comment.user,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: comment.mine
                                      ? const Color(0xFFFF9CA4)
                                      : const Color(0xFFDDDDDD),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 7),
                        Text(_timeAgo(comment.createdAt),
                            style: const TextStyle(
                                color: Color(0xFF6E6E6E), fontSize: 9.5)),
                      ]),
                      const SizedBox(height: 4),
                      LinkText(comment.text,
                          style: const TextStyle(
                              color: Color(0xFFC9C9C9),
                              fontSize: 12,
                              height: 1.45)),
                    ],
                  ),
                ),
                // ---- comment actions: react · reply · reactions · delete
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 5, 0, 0),
                  child: Row(children: [
                    InkWell(
                      onTap: onReact,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 2),
                        child: comment.myReaction.isEmpty
                            ? const Text('React',
                                style: TextStyle(
                                    color: Color(0xFF8A8A8A),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800))
                            : Text(comment.myReaction,
                                style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: onReply,
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                        child: Text('Reply',
                            style: TextStyle(
                                color: Color(0xFF8A8A8A),
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: onDelete,
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 3, vertical: 2),
                          child: Text('Delete',
                              style: TextStyle(
                                  color: Color(0xFFFF9CA4),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (comment.totalReactions > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(99),
                          border:
                              Border.all(color: const Color(0xFF2A2A2A)),
                        ),
                        child: Text(
                            '${_topEmojis(comment)} ${comment.totalReactions}',
                            style: const TextStyle(
                                color: Color(0xFF9A9A9A), fontSize: 10)),
                      ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _topEmojis(FeedCommentModel c) {
    final entries = c.reactions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(3).map((e) => e.key).join('');
  }
}

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
