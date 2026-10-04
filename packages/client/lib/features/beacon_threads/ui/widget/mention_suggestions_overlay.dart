import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
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
  Widget build(BuildContext context) =>
      ComposerSuggestionsOverlay<BeaconParticipant>(
        suggestions: suggestions,
        anchor: anchor,
        selectedIndex: selectedIndex,
        rowHeight: _kMentionSuggestionRowHeight,
        onSelect: onSelect,
        onDismiss: onDismiss,
        onHighlight: onHighlight,
        rowBuilder: (context, participant, selected, onHover, onTap) =>
            _MentionSuggestionRow(
              participant: participant,
              selected: selected,
              onHover: onHover,
              onTap: onTap,
            ),
      );
}

/// Builds one suggestion row; [onHover] highlights it, [onTap] accepts it.
typedef ComposerSuggestionRowBuilder<T> =
    Widget Function(
      BuildContext context,
      T item,
      bool selected,
      VoidCallback onHover,
      VoidCallback onTap,
    );

/// Floating completion card above the composer, shared by `@mention` and
/// `:shortcode:` completion. Shows at most [maxVisible] rows; a tap outside
/// the card dismisses it.
final class ComposerSuggestionsOverlay<T> extends StatelessWidget {
  const ComposerSuggestionsOverlay({
    required this.suggestions,
    required this.anchor,
    required this.selectedIndex,
    required this.rowHeight,
    required this.rowBuilder,
    required this.onSelect,
    required this.onDismiss,
    required this.onHighlight,
    this.maxWidth = _kMentionOverlayMaxWidth,
    super.key,
  });

  static const maxVisible = 5;

  final List<T> suggestions;
  final Rect anchor;
  final int selectedIndex;
  final double rowHeight;
  final double maxWidth;
  final ComposerSuggestionRowBuilder<T> rowBuilder;
  final void Function(T item) onSelect;
  final VoidCallback onDismiss;
  final void Function(int index) onHighlight;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final list = suggestions;
    if (list.isEmpty) return const SizedBox.shrink();

    final viewport = MediaQuery.sizeOf(context);
    if (!viewport.isFinite || viewport.width <= 0 || viewport.height <= 0) {
      return const SizedBox.shrink();
    }

    const margin = TenturaSpacing.row;
    final max = math.min(list.length, maxVisible);
    final height = max * rowHeight;
    final highlighted = selectedIndex.clamp(0, max - 1);

    final left = anchor.left
        .clamp(
          margin,
          math.max(margin, viewport.width - margin),
        )
        .toDouble();
    final width = math.min(
      maxWidth,
      math.max<double>(0, viewport.width - left - margin),
    );
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

                  final index = ((position.dy - top) / rowHeight)
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
                        height: rowHeight,
                        child: rowBuilder(
                          context,
                          list[i],
                          i == highlighted,
                          () => onHighlight(i),
                          () => onSelect(list[i]),
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
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final title = participant.userTitle.trim();
    final handle = participant.handle.trim().toLowerCase();
    return Semantics(
      identifier: TestIds.roomMentionSuggestion(
        handle.isEmpty ? participant.userId : handle,
      ),
      button: true,
      selected: selected,
      label: l10n.beaconRoomMentionSuggestionSemantics(
        handle.isEmpty ? title : '@$handle',
      ),
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.surfaceContainerHighest
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
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
                          handle.isEmpty ? title : '@$handle',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (title.isNotEmpty && handle.isNotEmpty)
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
