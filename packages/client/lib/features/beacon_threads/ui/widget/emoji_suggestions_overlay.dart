import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/emoji/emoji_catalog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'package:tentura/features/beacon_threads/ui/widget/mention_suggestions_overlay.dart';

const double _kEmojiOverlayMaxWidth = 320;

/// `:shortcode:` completion card: emoji glyph plus its shortcode per row.
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

  final List<EmojiEntry> suggestions;
  final Rect anchor;
  final int selectedIndex;
  final void Function(EmojiEntry entry) onSelect;
  final VoidCallback onDismiss;
  final void Function(int index) onHighlight;

  @override
  Widget build(BuildContext context) => ComposerSuggestionsOverlay<EmojiEntry>(
    suggestions: suggestions,
    anchor: anchor,
    selectedIndex: selectedIndex,
    rowHeight: kMinInteractiveDimension,
    maxWidth: _kEmojiOverlayMaxWidth,
    onSelect: onSelect,
    onDismiss: onDismiss,
    onHighlight: onHighlight,
    rowBuilder: (context, entry, selected, onHover, onTap) =>
        _EmojiSuggestionRow(
          entry: entry,
          selected: selected,
          onHover: onHover,
          onTap: onTap,
        ),
  );
}

class _EmojiSuggestionRow extends StatelessWidget {
  const _EmojiSuggestionRow({
    required this.entry,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final EmojiEntry entry;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final shortcode = ':${entry.shortcode}:';
    return Semantics(
      identifier: TestIds.roomEmojiSuggestion(entry.shortcode),
      button: true,
      selected: selected,
      label: L10n.of(context)!.emojiSuggestionSemantics(entry.emoji, shortcode),
      excludeSemantics: true,
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
                  Text(entry.emoji, style: theme.textTheme.titleLarge),
                  SizedBox(width: tt.iconTextGap),
                  Expanded(
                    child: Text(
                      shortcode,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
