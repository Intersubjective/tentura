import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/features/post_view/ui/post_remaining_label.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../domain/constellation_post_fade.dart';
import '../../domain/entity/constellation_field.dart';
import 'constellation_anchor_controls.dart';

/// Post context card on the map, sharing the adaptive preview placement.
class ConstellationPostPreviewSheet extends StatelessWidget {
  const ConstellationPostPreviewSheet({
    required this.post,
    required this.authorDisplayName,
    required this.onOpen,
    required this.onClose,
    super.key,
  });

  final ConstellationPost post;
  final String authorDisplayName;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final footer = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: onOpen,
          child: Text(l10n.constellationOpenPost),
        ),
        SizedBox(height: tt.rowGap),
        ConstellationAnchorTargetButton(
          target: ConstellationAnchorTarget.beacon(post.id),
        ),
      ],
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.postCreateMenuPost,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: l10n.buttonClose,
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        if (post.rootExcerpt.trim().isNotEmpty) ...[
          SizedBox(height: tt.sectionGap),
          Text(post.rootExcerpt, style: theme.textTheme.bodyMedium),
        ],
        if (post.expiresAt != null) ...[
          SizedBox(height: tt.tightGap),
          PostLifetimeTicker(
            expiresAt: post.expiresAt,
            archived: !constellationPostActive(
              post,
              RelativeTimestampTicker.now(),
            ),
            builder: (context, label) {
              if (label.isEmpty) return const SizedBox.shrink();
              return Text(
                label,
                key: const Key('constellation.post_preview.lifetime'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
        ],
        SizedBox(height: tt.sectionGap),
        Text(
          l10n.constellationPreviewAuthorLine(authorDisplayName),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );

    return Material(
      key: const Key('constellation.post_preview'),
      color: scheme.surfaceContainerHigh,
      elevation: 4,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: tt.cardPadding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scroll = SingleChildScrollView(child: body);
            if (!constraints.maxHeight.isFinite) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  scroll,
                  SizedBox(height: tt.rowGap),
                  footer,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: scroll),
                SizedBox(height: tt.rowGap),
                footer,
              ],
            );
          },
        ),
      ),
    );
  }
}
