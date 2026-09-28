import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Human-readable meaning of a quick-picker reaction emoji, or `null` for
/// emojis outside [BeaconRoomMessageReaction.quickPickerEmojis].
String? reactionEmojiMeaning(L10n l10n, String emoji) => switch (emoji) {
  '❤️' => l10n.beaconRoomReactionMeaningLove,
  '\u{1F64F}' => l10n.beaconRoomReactionMeaningThanks,
  '\u{1F91D}' => l10n.beaconRoomReactionMeaningDeal,
  '\u{1F4AA}' => l10n.beaconRoomReactionMeaningStrength,
  '\u{1F64C}' => l10n.beaconRoomReactionMeaningHooray,
  '\u{1F60A}' => l10n.beaconRoomReactionMeaningGlad,
  '\u{1F60C}' => l10n.beaconRoomReactionMeaningRelief,
  '\u{1F604}' => l10n.beaconRoomReactionMeaningFunny,
  '\u{1F62E}' => l10n.beaconRoomReactionMeaningWow,
  '\u{1F914}' => l10n.beaconRoomReactionMeaningThinking,
  '\u{1F615}' => l10n.beaconRoomReactionMeaningUnclear,
  '\u{1F61F}' => l10n.beaconRoomReactionMeaningWorried,
  '\u{1F622}' => l10n.beaconRoomReactionMeaningSad,
  '\u{1F620}' => l10n.beaconRoomReactionMeaningAngry,
  '\u{1F62C}' => l10n.beaconRoomReactionMeaningAwkward,
  '\u{1F614}' => l10n.beaconRoomReactionMeaningDisappointed,
  _ => null,
};

/// Slack-style reaction grid: hovering (desktop), focusing (keyboard) or
/// long-pressing (touch) an emoji previews its meaning in the line below;
/// a tap reacts.
class ReactionQuickPicker extends StatefulWidget {
  const ReactionQuickPicker({
    required this.selected,
    required this.onPick,
    super.key,
  });

  /// Emojis the viewer has already reacted with (outlined).
  final Set<String> selected;

  final ValueChanged<String> onPick;

  @override
  State<ReactionQuickPicker> createState() => _ReactionQuickPickerState();
}

class _ReactionQuickPickerState extends State<ReactionQuickPicker> {
  String? _preview;

  void _show(String emoji) {
    if (_preview != emoji) {
      setState(() => _preview = emoji);
    }
  }

  void _hide(String emoji) {
    if (_preview == emoji) {
      setState(() => _preview = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final preview = _preview;
    final previewMeaning = preview == null
        ? null
        : reactionEmojiMeaning(l10n, preview);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: tt.rowGap,
          runSpacing: tt.rowGap,
          children: [
            for (final emoji in BeaconRoomMessageReaction.quickPickerEmojis)
              Semantics(
                button: true,
                selected: widget.selected.contains(emoji),
                label: reactionEmojiMeaning(l10n, emoji) ?? emoji,
                excludeSemantics: true,
                child: MouseRegion(
                  onEnter: (_) => _show(emoji),
                  onExit: (_) => _hide(emoji),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => widget.onPick(emoji),
                    onLongPress: () => _show(emoji),
                    onFocusChange: (focused) =>
                        focused ? _show(emoji) : _hide(emoji),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.selected.contains(emoji)
                              ? tt.skyBorder
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(tt.rowGap),
                        child: Text(
                          emoji,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(top: tt.rowGap),
          child: ExcludeSemantics(
            child: Text(
              previewMeaning == null
                  ? l10n.beaconRoomReactionPickerHint
                  : '$preview  $previewMeaning',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Same text style both ways so the line never changes height.
              style: theme.textTheme.bodyMedium?.copyWith(
                color: previewMeaning == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
