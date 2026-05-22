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
