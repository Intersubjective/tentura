import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// U087 — one "latest" line per Request card: who wrote last, what, how long
/// ago, and how many messages are unread ("Nina: Parking sorted? · 1m",
/// "2 new"). A message with no text reads as what it carries ("📷 Photo",
/// #498); a poll reads as its question ("📊 Lunch?", #609). Renders
/// nothing without a member message.
class MyWorkLatestMessageLine extends StatelessWidget {
  const MyWorkLatestMessageLine({
    required this.vm,
    required this.currentUserId,
    this.now,
    super.key,
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;

  /// Fixed clock for tests; the card passes none and follows the shared
  /// relative-time clock.
  final DateTime? now;

  // Without a fixed clock the line follows the shared one, so «· 1m» keeps
  // counting while the card stays open (#532). The line is the age's own
  // widget: one Text and its spoken label.
  @override
  Widget build(BuildContext context) {
    final fixed = now;
    if (fixed != null) return _buildLine(context, fixed);
    return RelativeTimestampTicker(
      builder: (c) => _buildLine(c, RelativeTimestampTicker.now()),
    );
  }

  Widget _buildLine(BuildContext context, DateTime clock) {
    final l10n = L10n.of(context)!;
    final caption = vm.roomLatestMessageText.trim();
    // #609: a poll with no text arrives as its question; mark it as a poll,
    // as reply excerpts do ("📊 Lunch?").
    final text = caption.isNotEmpty
        ? (vm.roomLatestMessageKind == 'poll' ? '📊 $caption' : caption)
        : switch (vm.roomLatestMessageKind) {
            'image' => l10n.myWorkLatestPhoto,
            'file' => l10n.myWorkLatestFile,
            'poll' => l10n.myWorkLatestPoll,
            'fact' => l10n.myWorkLatestFact,
            _ => '',
          };
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final isMe =
        vm.roomLatestMessageAuthorId.isNotEmpty &&
        vm.roomLatestMessageAuthorId == currentUserId;
    final name = isMe
        ? l10n.labelYou
        : (vm.roomLatestMessageAuthorName.isEmpty
              ? l10n.myWorkLatestSomeone
              : vm.roomLatestMessageAuthorName);
    final at = vm.roomLatestMessageAt;
    final age = at == null
        ? ''
        : ' · ${cardRelativeAge(when: at, now: clock, l10n: l10n)}';
    final unread = vm.roomUnreadCount;
    // One spoken sentence for the whole line (#541 review): the visible
    // text uses abbreviations ("1m") meant for the eye.
    final details = [
      if (at != null) cardRelativeAgeSpoken(when: at, now: clock, l10n: l10n),
      if (unread > 0) l10n.myWorkUnreadCount(unread),
    ].join(', ');
    // A message that already ends a sentence gets no second full stop.
    final separator = RegExp(r'[.!?…]$').hasMatch(text.trimRight())
        ? ' '
        : '. ';
    final semanticsLabel = l10n.myWorkLatestMessageSemantics(
      name,
      text,
      details.isEmpty ? '' : '$separator$details',
    );
    final style = theme.textTheme.bodySmall!.copyWith(
      color: unread > 0 ? scheme.onSurface : tt.textFaint,
    );
    return Padding(
      padding: EdgeInsets.only(top: tt.tightGap),
      child: Semantics(
        container: true,
        label: semanticsLabel,
        child: ExcludeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${l10n.myWorkLatestMessage(name, text)}$age',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              if (unread > 0) ...[
                SizedBox(width: tt.tightGap),
                Text(
                  l10n.myWorkUnreadCount(unread),
                  style: theme.textTheme.labelSmall!.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
