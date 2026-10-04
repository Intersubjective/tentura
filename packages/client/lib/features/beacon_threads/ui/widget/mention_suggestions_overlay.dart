import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/emoji/domain/emoji_catalog.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/presence_avatar.dart';

const double _kSuggestionsOverlayMaxWidth = 360;
const double _kMentionSuggestionRowHeight = 56;
const double _kEmojiSuggestionRowHeight = kMinInteractiveDimension;

/// Most rows a composer suggestion list shows at once.
const kComposerSuggestionsMaxRows = 5;

/// `@` completion list above the composer.
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
  Widget build(BuildContext context) => _ComposerSuggestionsOverlay(
    itemCount: suggestions.length,
    rowHeight: _kMentionSuggestionRowHeight,
    anchor: anchor,
    selectedIndex: selectedIndex,
    onSelectIndex: (i) => onSelect(suggestions[i]),
    onDismiss: onDismiss,
    rowBuilder: (i, selected) => _MentionSuggestionRow(
      participant: suggestions[i],
      selected: selected,
      onHover: () => onHighlight(i),
      onTap: () => onSelect(suggestions[i]),
    ),
  );
}

/// `:shortcode` completion list above the composer.
final class EmojiSuggestionsOverlay extends StatelessWidget {
  const EmojiSuggestionsOverlay({
    required this.suggestions,
    required this.anchor,
    required this.selectedIndex,
    required this.onSelect,
    required this.onDismiss,
    required this.onHighlight,
    super.key,
  });

  final List<EmojiMatch> suggestions;
  final Rect anchor;
  final int selectedIndex;
  final void Function(EmojiMatch match) onSelect;
  final VoidCallback onDismiss;
  final void Function(int index) onHighlight;

  @override
  Widget build(BuildContext context) => _ComposerSuggestionsOverlay(
    itemCount: suggestions.length,
    rowHeight: _kEmojiSuggestionRowHeight,
    anchor: anchor,
    selectedIndex: selectedIndex,
    onSelectIndex: (i) => onSelect(suggestions[i]),
    onDismiss: onDismiss,
    rowBuilder: (i, selected) => _EmojiSuggestionRow(
      match: suggestions[i],
      selected: selected,
      onHover: () => onHighlight(i),
      onTap: () => onSelect(suggestions[i]),
    ),
  );
}

/// Card of fixed-height rows placed just above [anchor]; a tap outside it
/// dismisses, a tap inside selects the row under the pointer.
final class _ComposerSuggestionsOverlay extends StatelessWidget {
  const _ComposerSuggestionsOverlay({
    required this.itemCount,
    required this.rowHeight,
    required this.anchor,
    required this.selectedIndex,
    required this.onSelectIndex,
    required this.onDismiss,
    required this.rowBuilder,
  });

  final int itemCount;
  final double rowHeight;
  final Rect anchor;
  final int selectedIndex;
  final void Function(int index) onSelectIndex;
  final VoidCallback onDismiss;
  final Widget Function(int index, bool selected) rowBuilder;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    if (itemCount <= 0) return const SizedBox.shrink();

    final viewport = MediaQuery.sizeOf(context);
    if (!viewport.isFinite || viewport.width <= 0 || viewport.height <= 0) {
      return const SizedBox.shrink();
    }

    const margin = TenturaSpacing.row;
    final max = math.min(itemCount, kComposerSuggestionsMaxRows);
    final height = max * rowHeight;
    final highlighted = selectedIndex.clamp(0, max - 1);

    final left = anchor.left
        .clamp(
          margin,
          math.max(margin, viewport.width - margin),
        )
        .toDouble();
    final width = math.min(
      _kSuggestionsOverlayMaxWidth,
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

                  final index = ((position.dy - top) / rowHeight).floor().clamp(
                    0,
                    max - 1,
                  );
                  onSelectIndex(index);
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
                        child: rowBuilder(i, i == highlighted),
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

class _EmojiSuggestionRow extends StatelessWidget {
  const _EmojiSuggestionRow({
    required this.match,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final EmojiMatch match;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final shortcode = ':${match.shortcode}:';
    return Semantics(
      identifier: TestIds.roomEmojiSuggestion(match.shortcode),
      button: true,
      selected: selected,
      label: '${match.entry.emoji} $shortcode',
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
              ),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Text(
                      match.entry.emoji,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  SizedBox(width: tt.avatarTextGap),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        shortcode,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
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
