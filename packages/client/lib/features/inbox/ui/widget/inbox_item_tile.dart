import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/author_info.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';

import '../../domain/entity/inbox_item.dart';

class InboxItemTile extends StatelessWidget {
  const InboxItemTile({
    required this.item,
    required this.onTap,
    required this.onHide,
    required this.onToggleWatch,
    super.key,
  });

  final InboxItem item;
  final VoidCallback onTap;
  final VoidCallback onHide;
  final VoidCallback onToggleWatch;

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
              // Forward provenance row
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
                  // Actions menu
                  PopupMenuButton<String>(
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'watch',
                        child: Text(
                          item.isWatching
                              ? l10n.actionStopWatching
                              : l10n.actionWatch,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'hide',
                        child: Text(l10n.actionHide),
                      ),
                    ],
                    onSelected: (v) {
                      if (v == 'hide') onHide();
                      if (v == 'watch') onToggleWatch();
                    },
                    child: const Icon(Icons.more_vert, size: 20),
                  ),
                ],
              ),

              // Author
              AuthorInfo(author: beacon.author),

              // Beacon info
              BeaconInfo(
                beacon: beacon,
                isTitleLarge: true,
                isShowBeaconEnabled: false,
              ),

              // Latest note preview
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

              // Watching badge
              if (item.isWatching)
                Padding(
                  padding: kPaddingSmallT,
                  child: Chip(
                    label: Text(l10n.inboxWatching),
                    avatar: const Icon(Icons.visibility, size: 16),
                    backgroundColor:
                        theme.colorScheme.secondaryContainer,
                    labelStyle: theme.textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
