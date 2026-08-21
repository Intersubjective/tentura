import 'package:flutter/material.dart';
import 'package:readmore/readmore.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/room_message_mention_span.dart';

/// Max fraction of list row width for a room message bubble (see DEV_GUIDELINES).
const double kRoomMessageBubbleMaxWidthFraction = 0.75;

/// Layout metrics for trailing metadata (timestamp) on the last text line.
class TrailingMetaMetrics {
  const TrailingMetaMetrics({
    required this.reserveWidth,
    required this.reserveHeight,
    required this.trailingGapH,
    required this.trailingGapV,
    required this.verticalTuckGap,
  });

  final double reserveWidth;
  final double reserveHeight;
  final double trailingGapH;
  final double trailingGapV;

  /// Space below the body text reserved for the date overlay; kept outside
  /// the shared paragraph because stretching that line's height pushes body
  /// glyphs and date down in lockstep, leaving their offset unchanged.
  final double verticalTuckGap;
}

bool shouldUseInlineTrailingMeta({
  required bool hasDisplayText,
  required Map<String, int> reactionCounts,
}) => hasDisplayText && reactionCounts.isEmpty;

bool shouldHugBubbleWidth({
  required bool hasMediaOrPoll,
  required bool hasDisplayText,
  required bool hasReactions,
  required bool hasFooterContent,
}) => hasMediaOrPoll || hasDisplayText || hasReactions || hasFooterContent;

TrailingMetaMetrics computeTrailingMetaMetrics({
  required String dateLine,
  required TextStyle metaStyle,
  required double trailingGapH,
  required double trailingGapV,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final metaPainter = TextPainter(
    text: TextSpan(text: dateLine, style: metaStyle),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();

  final metadataStripWidth = metaPainter.width.ceilToDouble();
  final reserveWidth = trailingGapH + metadataStripWidth;

  return TrailingMetaMetrics(
    reserveWidth: reserveWidth,
    reserveHeight: metaPainter.height,
    trailingGapH: trailingGapH,
    trailingGapV: trailingGapV,
    verticalTuckGap: trailingGapV + metaPainter.height,
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
        return TextSpan(
          text: text,
          style: roomMessageMentionTextStyle(
            textStyle: textStyle,
            isSelfMention: userId == selfUserId,
            mentionColor: mentionColor,
            selfMentionBackground: selfMentionBackground,
          ),
        );
      },
    ),
  ];
}

TextStyle? roomMessageMentionTextStyle({
  required TextStyle? textStyle,
  required bool isSelfMention,
  required Color mentionColor,
  required Color selfMentionBackground,
}) => textStyle?.copyWith(
  color: isSelfMention ? null : mentionColor,
  backgroundColor: isSelfMention ? selfMentionBackground : null,
  fontWeight: isSelfMention ? FontWeight.w600 : FontWeight.w700,
);

List<RoomMessageMentionSpan> usableRoomMessageMentionSpans({
  required List<RoomMessageMentionSpan> spans,
  required String body,
}) {
  final sorted = [...spans]..sort((a, b) => a.offset.compareTo(b.offset));
  final usable = <RoomMessageMentionSpan>[];
  var lastEnd = 0;
  for (final span in sorted) {
    final end = span.offset + span.length;
    if (span.length <= 0 ||
        span.offset < lastEnd ||
        span.offset < 0 ||
        end > body.length) {
      continue;
    }
    usable.add(span);
    lastEnd = end;
  }
  return usable;
}

TextSpan buildRoomMessageBodySpanWithExplicitMentions({
  required String data,
  required TextStyle? textStyle,
  required List<Annotation>? plainTextAnnotations,
  required List<RoomMessageMentionSpan> explicitSpans,
  required TextStyle? Function(String userId) explicitMentionStyle,
}) {
  if (explicitSpans.isEmpty) {
    return buildRoomMessageAnnotatedBodySpan(
      data: data,
      textStyle: textStyle,
      annotations: plainTextAnnotations,
    );
  }
  final children = <TextSpan>[];
  var cursor = 0;
  for (final span in explicitSpans) {
    if (cursor < span.offset) {
      children.add(
        buildRoomMessageAnnotatedBodySpan(
          data: data.substring(cursor, span.offset),
          textStyle: textStyle,
          annotations: plainTextAnnotations,
        ),
      );
    }
    final end = span.offset + span.length;
    children.add(
      TextSpan(
        text: data.substring(span.offset, end),
        style: explicitMentionStyle(span.userId),
      ),
    );
    cursor = end;
  }
  if (cursor < data.length) {
    children.add(
      buildRoomMessageAnnotatedBodySpan(
        data: data.substring(cursor),
        textStyle: textStyle,
        annotations: plainTextAnnotations,
      ),
    );
  }
  return TextSpan(style: textStyle, children: children);
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
    onMatch: (regexMatch) {
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
    onNonMatch: (unmatchedText) {
      contents.add(TextSpan(text: unmatchedText));
      return '';
    },
  );

  return TextSpan(style: textStyle, children: contents);
}

InlineSpan buildTrailingMetaWidgetSpan({
  required TrailingMetaMetrics metrics,
}) {
  return WidgetSpan(
    alignment: PlaceholderAlignment.bottom,
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: SizedBox(
          width: metrics.reserveWidth,
          height: metrics.reserveHeight,
        ),
      ),
    ),
  );
}

TextSpan buildMessageTextSpanWithTrailingMeta({
  required String display,
  required TextStyle bodyStyle,
  required List<Annotation>? mentionAnnotations,
  required TrailingMetaMetrics metrics,
  List<RoomMessageMentionSpan> explicitSpans = const [],
  TextStyle? Function(String userId)? explicitMentionStyle,
}) {
  final body = explicitSpans.isEmpty
      ? buildRoomMessageAnnotatedBodySpan(
          data: display,
          textStyle: bodyStyle,
          annotations: mentionAnnotations,
        )
      : buildRoomMessageBodySpanWithExplicitMentions(
          data: display,
          textStyle: bodyStyle,
          plainTextAnnotations: mentionAnnotations,
          explicitSpans: explicitSpans,
          explicitMentionStyle: explicitMentionStyle!,
        );
  return TextSpan(
    style: bodyStyle,
    children: [
      body,
      buildTrailingMetaWidgetSpan(metrics: metrics),
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
