import 'package:flutter/material.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

/// Avatar / icon sizes for lifecycle footer tap rows (see [_MessageLifecycleFooter]).
const double kLifecycleFooterAvatarSize = 16;
const double kLifecycleFooterIconSize = 12;

/// Reaction chip horizontal chrome: [kPaddingSmallH] on [InkWell] + inner chip padding.
const double kReactionChipHorizontalChrome = kSpacingSmall * 4;

/// Selected chip outline ([Border.all] on the pill) is not part of chrome padding.
const double kReactionChipBorderAllowance = 2;

/// Gap between emoji and count / avatar strip inside a reaction chip.
const double kReactionChipEmojiGap = 4;

/// Reactor avatar strip layout (mirrors [_ReactorAvatarStrip]).
const double kReactorAvatarStripSize = 16;
const double kReactorAvatarStripOverlap = 4;
const double kReactorAvatarStripMaxVisible = 3;

/// Width of the overlapping reactor avatar strip for [reactorCount] profiles.
double reactorAvatarStripWidth(int reactorCount) {
  if (reactorCount <= 0) {
    return 0;
  }
  const step = kReactorAvatarStripSize - kReactorAvatarStripOverlap;
  final overflow =
      reactorCount > kReactorAvatarStripMaxVisible
          ? reactorCount - kReactorAvatarStripMaxVisible.toInt()
          : 0;
  final visible = reactorCount > kReactorAvatarStripMaxVisible
      ? kReactorAvatarStripMaxVisible.toInt()
      : reactorCount;
  final extraSlots = overflow > 0 ? 1 : 0;
  return kReactorAvatarStripSize + (visible + extraSlots - 1) * step;
}

/// Minimum width of one reaction chip (emoji + count or avatar strip + chrome).
double measureReactionChipWidth({
  required String emoji,
  required int count,
  required int reactorCount,
  required TextStyle emojiStyle,
  required TextStyle countStyle,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final emojiPainter = TextPainter(
    text: TextSpan(text: emoji, style: emojiStyle),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();

  final double trailingWidth;
  if (reactorCount > 0) {
    trailingWidth = reactorAvatarStripWidth(reactorCount);
  } else {
    final countPainter = TextPainter(
      text: TextSpan(text: '$count', style: countStyle),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    trailingWidth = countPainter.width;
  }

  return kReactionChipHorizontalChrome +
      kReactionChipBorderAllowance +
      emojiPainter.width +
      kReactionChipEmojiGap +
      trailingWidth;
}

/// Minimum width for a single-line reactions + timestamp footer row.
double measureReactionTimeRowMinWidth({
  required List<MapEntry<String, int>> reactionEntries,
  required Map<String, int> reactorCountsByEmoji,
  required String dateLine,
  required TextStyle emojiStyle,
  required TextStyle countStyle,
  required TextStyle timeStyle,
  required double chipSpacing,
  required double trailingGap,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  var width = 0.0;
  for (var i = 0; i < reactionEntries.length; i++) {
    final entry = reactionEntries[i];
    if (i > 0) {
      width += chipSpacing;
    }
    width += measureReactionChipWidth(
      emoji: entry.key,
      count: entry.value,
      reactorCount: reactorCountsByEmoji[entry.key] ?? 0,
      emojiStyle: emojiStyle,
      countStyle: countStyle,
      textDirection: textDirection,
      textScaler: textScaler,
    );
  }

  if (dateLine.isNotEmpty) {
    final timePainter = TextPainter(
      text: TextSpan(text: dateLine, style: timeStyle),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    width += trailingGap + timePainter.width;
  }

  return width;
}

/// Fixed width of a lifecycle tap row excluding [label] and [time] text.
double lifecycleTapRowChromeWidth({
  required double itemGap,
  required bool showChevron,
}) {
  var width = kLifecycleFooterAvatarSize + kLifecycleFooterIconSize;
  width += itemGap * (showChevron ? 4 : 3);
  if (showChevron) {
    width += kLifecycleFooterIconSize;
  }
  return width;
}

/// Minimum content width for a right-aligned lifecycle tap row.
double measureLifecycleTapRowMinWidth({
  required String label,
  required String time,
  required TextStyle labelStyle,
  required TextStyle timeStyle,
  required double itemGap,
  required bool showChevron,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final labelPainter = TextPainter(
    text: TextSpan(text: label, style: labelStyle),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final timePainter = TextPainter(
    text: TextSpan(text: time, style: timeStyle),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();

  return lifecycleTapRowChromeWidth(
        itemGap: itemGap,
        showChevron: showChevron,
      ) +
      labelPainter.width +
      timePainter.width;
}

/// Minimum content width for the semantic "done" footer row.
double measureMarkDoneRowMinWidth({
  required String label,
  required TextStyle labelStyle,
  required double itemGap,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final labelPainter = TextPainter(
    text: TextSpan(text: label, style: labelStyle),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();

  return kLifecycleFooterAvatarSize +
      kLifecycleFooterIconSize +
      itemGap * 2 +
      labelPainter.width;
}

/// Result of measuring a room message bubble's inner content width.
class RoomMessageBubbleMeasureResult {
  const RoomMessageBubbleMeasureResult({required this.innerWidth});

  /// Width for the bubble shell including horizontal [cardPaddingH].
  final double innerWidth;
}

RoomMessageBubbleMeasureResult measureBubble({
  required double contentMaxWidth,
  required double cardPaddingH,
  required double? tightTextWidth,
  required bool hasMediaOrPoll,
}) {
  final cappedContent = contentMaxWidth + cardPaddingH;
  if (hasMediaOrPoll || tightTextWidth == null) {
    return RoomMessageBubbleMeasureResult(innerWidth: cappedContent);
  }
  final hugged = tightTextWidth + cardPaddingH;
  return RoomMessageBubbleMeasureResult(
    innerWidth: hugged < cappedContent ? hugged : cappedContent,
  );
}
