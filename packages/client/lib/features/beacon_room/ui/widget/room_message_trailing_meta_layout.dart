import 'package:flutter/material.dart';
import 'package:readmore/readmore.dart';

import 'package:tentura/consts.dart';

/// Max fraction of list row width for a room message bubble (see DEV_GUIDELINES).
const double kRoomMessageBubbleMaxWidthFraction = 0.75;

/// Layout metrics for trailing metadata (timestamp) on the last text line.
class TrailingMetaMetrics {
  const TrailingMetaMetrics({
    required this.reserveWidth,
    required this.reserveHeight,
    required this.bodyLineHeight,
    required this.trailingGap,
  });

  final double reserveWidth;
  final double reserveHeight;
  final double bodyLineHeight;
  final double trailingGap;
}

bool shouldUseInlineTrailingMeta({
  required bool hasDisplayText,
  required Map<String, int> reactionCounts,
}) =>
    hasDisplayText && reactionCounts.isEmpty;

bool shouldHugBubbleWidth({
  required bool hasMediaOrPoll,
  required bool hasDisplayText,
  required bool hasReactions,
  required bool hasFooterContent,
}) =>
    !hasMediaOrPoll &&
    (hasDisplayText || hasReactions || hasFooterContent);

TrailingMetaMetrics computeTrailingMetaMetrics({
  required String dateLine,
  required TextStyle metaStyle,
  required TextStyle bodyStyle,
  required double trailingGap,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final metaPainter = TextPainter(
    text: TextSpan(text: dateLine, style: metaStyle),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();

  final bodyPainter = TextPainter(
    text: TextSpan(text: 'Mg', style: bodyStyle),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();

  final metadataStripWidth = metaPainter.width;
  final reserveWidth = trailingGap + metadataStripWidth;

  return TrailingMetaMetrics(
    reserveWidth: reserveWidth,
    reserveHeight: metaPainter.height,
    bodyLineHeight: bodyPainter.height,
    trailingGap: trailingGap,
  );
}

double measureTightTextWidth({
  required InlineSpan span,
  required double maxWidth,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final painter = TextPainter(
    text: span,
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  return painter.size.width;
}

/// Tight width for body text with trailing metadata reserve on the last line.
///
/// [WidgetSpan] cannot be measured without a widget tree, so reserve width is
/// applied to the last line from [trailingReserveWidth] after laying out [bodySpan].
double measureTightBodyWidthWithTrailingReserve({
  required InlineSpan bodySpan,
  required double trailingReserveWidth,
  required double maxWidth,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final painter = TextPainter(
    text: bodySpan,
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);

  final lines = painter.computeLineMetrics();
  if (lines.isEmpty) {
    return trailingReserveWidth;
  }

  var widest = 0.0;
  for (var i = 0; i < lines.length; i++) {
    final lineWidth = lines[i].width;
    final effective = i == lines.length - 1
        ? lineWidth + trailingReserveWidth
        : lineWidth;
    if (effective > widest) {
      widest = effective;
    }
  }
  return widest > maxWidth ? maxWidth : widest;
}

List<Annotation> buildRoomMessageMentionAnnotations({
  required Map<String, String> handleToUserId,
  required Set<String> mentionedIds,
  required String selfUserId,
  required Color mentionColor,
  required Color selfMentionBackground,
}) {
  return [
    Annotation(
      regExp: RegExp(
        '@[a-zA-Z0-9_]{$kUserHandleMinLength,$kUserHandleMaxLength}',
      ),
      spanBuilder: ({required text, textStyle}) {
        final handle = text.substring(1).toLowerCase();
        final userId = handleToUserId[handle];
        final isMentioned = userId != null && mentionedIds.contains(userId);
        if (!isMentioned) {
          return TextSpan(text: text, style: textStyle);
        }
        final isSelfMention = userId == selfUserId;
        return TextSpan(
          text: text,
          style: textStyle?.copyWith(
            color: isSelfMention ? null : mentionColor,
            backgroundColor: isSelfMention ? selfMentionBackground : null,
            fontWeight: isSelfMention ? FontWeight.w600 : FontWeight.w700,
          ),
        );
      },
    ),
  ];
}

TextSpan buildRoomMessageAnnotatedBodySpan({
  required String data,
  required TextStyle? textStyle,
  required List<Annotation>? annotations,
}) {
  final regExp = _mergeMentionRegexPatterns(annotations);
  if (regExp == null || data.isEmpty) {
    return TextSpan(text: data, style: textStyle);
  }

  final contents = <TextSpan>[];

  data.splitMapJoin(
    regExp,
    onMatch: (Match regexMatch) {
      final matchedText = regexMatch.group(0)!;
      late final Annotation matchedAnnotation;

      if (annotations!.length == 1) {
        matchedAnnotation = annotations[0];
      } else {
        for (var i = 0; i < regexMatch.groupCount; i++) {
          if (matchedText == regexMatch.group(i + 1)) {
            matchedAnnotation = annotations[i];
            break;
          }
        }
      }

      final content = matchedAnnotation.spanBuilder(
        text: matchedText,
        textStyle: textStyle,
      );
      contents.add(content);
      return '';
    },
    onNonMatch: (String unmatchedText) {
      contents.add(TextSpan(text: unmatchedText));
      return '';
    },
  );

  return TextSpan(style: textStyle, children: contents);
}

InlineSpan buildTrailingMetaWidgetSpan({
  required String dateLine,
  required TextStyle metaStyle,
  required TrailingMetaMetrics metrics,
}) {
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: SizedBox(
      width: metrics.reserveWidth,
      height: metrics.bodyLineHeight,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: metrics.trailingGap),
          child: Text(dateLine, style: metaStyle),
        ),
      ),
    ),
  );
}

TextSpan buildMessageTextSpanWithTrailingMeta({
  required String display,
  required TextStyle bodyStyle,
  required List<Annotation>? mentionAnnotations,
  required String dateLine,
  required TextStyle metaStyle,
  required TrailingMetaMetrics metrics,
}) {
  final body = buildRoomMessageAnnotatedBodySpan(
    data: display,
    textStyle: bodyStyle,
    annotations: mentionAnnotations,
  );
  return TextSpan(
    style: bodyStyle,
    children: [
      body,
      buildTrailingMetaWidgetSpan(
        dateLine: dateLine,
        metaStyle: metaStyle,
        metrics: metrics,
      ),
    ],
  );
}

RegExp? _mergeMentionRegexPatterns(List<Annotation>? annotations) {
  if (annotations == null || annotations.isEmpty) {
    return null;
  }
  if (annotations.length == 1) {
    return annotations[0].regExp;
  }
  final nonCapturingGroupPattern = RegExp(r'\((?!\?:)');
  return RegExp(
    annotations
        .map(
          (a) =>
              '(${a.regExp.pattern.replaceAll(nonCapturingGroupPattern, '(?:')})',
        )
        .join('|'),
  );
}
