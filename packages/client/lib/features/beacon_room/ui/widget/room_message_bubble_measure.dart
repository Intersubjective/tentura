import 'package:flutter/material.dart';

/// Avatar / icon sizes for lifecycle footer tap rows (see [_MessageLifecycleFooter]).
const double kLifecycleFooterAvatarSize = 16;
const double kLifecycleFooterIconSize = 12;

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
