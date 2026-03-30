import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/author_info.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';

class InboxItemTile extends StatelessWidget {
  const InboxItemTile({
    required this.item,
    required this.onTap,
    this.onWatch,
    this.onStopWatching,
    this.onCantHelp,
    this.onMoveToInbox,
    super.key,
  });

  final InboxItem item;
  final VoidCallback onTap;
  final VoidCallback? onWatch;
  final VoidCallback? onStopWatching;
  final Future<void> Function()? onCantHelp;
  final VoidCallback? onMoveToInbox;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final beacon = item.beacon;
    if (beacon == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: kPaddingAllS,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.forward_to_inbox,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.forwardedCount(item.forwardCount),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateFormatYMD(item.latestForwardAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  PopupMenuButton<String>(
                    itemBuilder: (_) => [
                      if (onWatch != null)
                        PopupMenuItem(
                          value: 'watch',
                          child: Text(l10n.actionWatch),
                        ),
                      if (onStopWatching != null)
                        PopupMenuItem(
                          value: 'stop_watch',
                          child: Text(l10n.actionStopWatching),
                        ),
                      if (onCantHelp != null)
                        PopupMenuItem(
                          value: 'cant_help',
                          child: Text(l10n.actionCantHelp),
                        ),
                      if (onMoveToInbox != null)
                        PopupMenuItem(
                          value: 'move_inbox',
                          child: Text(l10n.actionMoveToInbox),
                        ),
                    ],
                    onSelected: (v) async {
                      if (v == 'watch') onWatch?.call();
                      if (v == 'stop_watch') onStopWatching?.call();
                      if (v == 'cant_help') await onCantHelp?.call();
                      if (v == 'move_inbox') onMoveToInbox?.call();
                    },
                    child: const Icon(Icons.more_vert, size: 20),
                  ),
                ],
              ),
              AuthorInfo(author: beacon.author),
              BeaconInfo(
                beacon: beacon,
                isTitleLarge: true,
                isShowBeaconEnabled: false,
              ),
              if (item.latestNotePreview.isNotEmpty)
                Padding(
                  padding: kPaddingSmallT,
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.latestNotePreview,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              if (item.status == InboxItemStatus.watching)
                Padding(
                  padding: kPaddingSmallT,
                  child: Chip(
                    label: Text(l10n.inboxTabWatching),
                    avatar: const Icon(Icons.visibility, size: 16),
                    backgroundColor:
                        theme.colorScheme.secondaryContainer,
                    labelStyle: theme.textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (item.status == InboxItemStatus.rejected &&
                  item.rejectionMessage.isNotEmpty)
                Padding(
                  padding: kPaddingSmallT,
                  child: Text(
                    item.rejectionMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
