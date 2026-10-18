import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

/// U087 — one "latest" line per Request card: who wrote last, what, how long
/// ago, and how many messages are unread ("Nina: Parking sorted? · 1m",
/// "2 new"). Renders nothing without a member message.
class MyWorkLatestMessageLine extends StatelessWidget {
  const MyWorkLatestMessageLine({
    required this.vm,
    required this.currentUserId,
    this.now,
    super.key,
  });

  final MyWorkCardViewModel vm;
  final String currentUserId;

  /// Fixed clock for tests; the card passes none and reads the wall clock.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final text = vm.roomLatestMessageText.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
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
        : ' · ${cardRelativeAge(when: at, now: now ?? DateTime.now(), l10n: l10n)}';
    final unread = vm.roomUnreadCount;
    // One spoken sentence for the whole line (#541 review): the visible
    // text uses abbreviations ("1m") meant for the eye.
    final details = [
      if (at != null)
        cardRelativeAgeSpoken(when: at, now: now ?? DateTime.now(), l10n: l10n),
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
      color: unread > 0
          ? scheme.onSurface
          : tt.textFaint,
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
