import 'dart:math' show min;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

const double _kReactionPickerCellExtent = 40;

/// Anchored Telegram-style emoji reaction strip (curated subset only).
///
/// Caller supplies [semanticLabel] for the popup container (SR).
Future<void> showRoomReactionPicker({
  required BuildContext anchorContext,
  required Set<String> selected,
  required ValueChanged<String> onPick,
  required String semanticLabel,
}) async {
  final rb = anchorContext.findRenderObject();
  if (rb is! RenderBox || !rb.attached || !rb.hasSize) {
    return;
  }

  final topLeft = rb.localToGlobal(Offset.zero);
  final anchorRect = topLeft & rb.size;

  await showDialog<void>(
    context: anchorContext,
    barrierColor: Colors.transparent,
    builder: (dialogContext) {
      final mq = MediaQuery.of(dialogContext);

      return CustomSingleChildLayout(
        delegate: _ReactionPickerLayoutDelegate(anchorRect: anchorRect),
        child: _RoomReactionPopupContent(
          selected: selected,
          semanticLabel: semanticLabel,
          reduceMotion: mq.disableAnimations,
          onEmojiTap: (emoji) {
            Navigator.of(dialogContext).pop();
            onPick(emoji);
          },
        ),
      );
    },
  );
}

class _ReactionPickerLayoutDelegate extends SingleChildLayoutDelegate {
  _ReactionPickerLayoutDelegate({required this.anchorRect});

  final Rect anchorRect;

  static const double _edge = kSpacingSmall;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Use [size] from layout, not MediaQuery.size: on web (e.g. Firefox) they can
    // diverge, which breaks horizontal clamping and clips the strip off-screen.
    final openAbove = anchorRect.center.dy > size.height * 0.6;

    var left = anchorRect.center.dx - childSize.width / 2;
    left = left.clamp(
      _edge,
      size.width - childSize.width - _edge,
    );

    final topRaw = openAbove
        ? anchorRect.top - childSize.height - _edge
        : anchorRect.bottom + _edge;

    final top = topRaw.clamp(
      _edge,
      size.height - childSize.height - _edge,
    );

    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _ReactionPickerLayoutDelegate oldDelegate) =>
      anchorRect != oldDelegate.anchorRect;
}

class _RoomReactionPopupContent extends StatelessWidget {
  const _RoomReactionPopupContent({
    required this.selected,
    required this.semanticLabel,
    required this.reduceMotion,
    required this.onEmojiTap,
  });

  final Set<String> selected;

  final String semanticLabel;

  final bool reduceMotion;

  final ValueChanged<String> onEmojiTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final cols = mq.size.width >= 360 ? 8 : 4;
    const cell = _kReactionPickerCellExtent;
    const emojis = BeaconRoomMessageReaction.quickPickerEmojis;

    final rows = <List<String>>[];
    for (var i = 0; i < emojis.length; i += cols) {
      rows.add(emojis.sublist(i, min(i + cols, emojis.length)));
    }

    final table = Material(
      elevation: 4,
      shadowColor: theme.shadowColor.withValues(alpha: 0.2),
      color: theme.colorScheme.surfaceContainerHigh,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: kPaddingAllS,
        child: Table(
          defaultColumnWidth: const FixedColumnWidth(cell),
          children: [
            for (final row in rows)
              TableRow(
                children: [
                  for (final e in row)
                    SizedBox(
                      width: cell,
                      height: cell,
                      child: _ReactionEmojiTile(
                        emoji: e,
                        selected: selected.contains(e),
                        onTap: () => onEmojiTap(e),
                      ),
                    ),
                  for (var j = row.length; j < cols; j++)
                    const SizedBox(
                      width: _kReactionPickerCellExtent,
                      height: _kReactionPickerCellExtent,
                    ),
                ],
              ),
          ],
        ),
      ),
    );

    Widget content;

    if (reduceMotion) {
      content = table;
    } else {
      content = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) {
          final scale = lerpDouble(0.85, 1, v)!;
          final opacity = v.clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              alignment: Alignment.topCenter,
              scale: scale,
              child: child,
            ),
          );
        },
        child: table,
      );
    }

    return Semantics(
      container: true,
      label: semanticLabel,
      child: content,
    );
  }
}

class _ReactionEmojiTile extends StatelessWidget {
  const _ReactionEmojiTile({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;

  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
            ),
            color: selected ? scheme.primaryContainer : Colors.transparent,
          ),
          child: Center(
            child: ExcludeSemantics(
              child: Text(emoji, style: theme.textTheme.titleMedium),
            ),
          ),
        ),
      ),
    );
  }
}
