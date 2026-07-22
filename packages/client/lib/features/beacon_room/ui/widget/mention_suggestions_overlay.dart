import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/presence_avatar.dart';

const double _kMentionOverlayMaxWidth = 360;
const double _kMentionSuggestionRowHeight = 56;

final class MentionSuggestionsOverlay extends StatelessWidget {
  const MentionSuggestionsOverlay({
    required this.suggestions,
    required this.anchor,
    required this.selectedIndex,
    required this.onSelect,
    required this.onDismiss,
    required this.onHighlight,
    super.key,
  });

  final List<BeaconParticipant> suggestions;
  final Rect anchor;
  final int selectedIndex;
  final void Function(BeaconParticipant participant) onSelect;
  final VoidCallback onDismiss;
  final void Function(int index) onHighlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final list = suggestions;
    if (list.isEmpty) return const SizedBox.shrink();

    final viewport = MediaQuery.sizeOf(context);
    if (!viewport.isFinite || viewport.width <= 0 || viewport.height <= 0) {
      return const SizedBox.shrink();
    }

    final margin = TenturaSpacing.row;
    final max = list.length < 5 ? list.length : 5;
    final height = max * _kMentionSuggestionRowHeight;
    final highlighted = selectedIndex.clamp(0, max - 1);

    final left = anchor.left
        .clamp(
          margin,
          math.max(margin, viewport.width - margin),
        )
        .toDouble();
    final width = math
        .min(
          _kMentionOverlayMaxWidth,
          math.max(0.0, viewport.width - left - margin),
        )
        .toDouble();
    final top = math.max(margin, anchor.top - height - margin);

    if (width <= 0 || height <= 0) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: TextFieldTapRegion(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) {
                  final position = event.localPosition;
                  final insideCard =
                      position.dx >= left &&
                      position.dx <= left + width &&
                      position.dy >= top &&
                      position.dy <= top + height;
                  if (!insideCard) {
                    onDismiss();
                    return;
                  }

                  final index =
                      ((position.dy - top) / _kMentionSuggestionRowHeight)
                          .floor()
                          .clamp(0, max - 1);
                  onSelect(list[index]);
                },
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(tt.cardRadius),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < max; i++)
                      SizedBox(
                        height: _kMentionSuggestionRowHeight,
                        child: _MentionSuggestionRow(
                          participant: list[i],
                          selected: i == highlighted,
                          onHover: () => onHighlight(i),
                          onTap: () => onSelect(list[i]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MentionSuggestionRow extends StatelessWidget {
  const _MentionSuggestionRow({
    required this.participant,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final BeaconParticipant participant;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final title = participant.userTitle.trim();
    final handle = participant.handle.trim().toLowerCase();
    return Semantics(
      identifier: TestIds.roomMentionSuggestion(handle),
      button: true,
      selected: selected,
      label: '@$handle',
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.surfaceContainerHighest : null,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: TenturaSpacing.cardPadding,
                vertical: TenturaSpacing.row,
              ),
              child: Row(
                children: [
                  PresenceAvatar.small(
                    profile: participant.toProfile(),
                    userId: participant.userId,
                    size: 28,
                  ),
                  SizedBox(width: tt.avatarTextGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${participant.handle}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (title.isNotEmpty)
                          Text(
                            title,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension on BeaconParticipant {
  Profile toProfile() => Profile(
    id: userId,
    displayName: userTitle,
  );
}
