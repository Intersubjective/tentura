import 'package:flutter/material.dart';
import 'package:readmore/readmore.dart';

import 'package:tentura/features/beacon_threads/ui/widget/room_message_trailing_meta_layout.dart';

/// Message body with trailing inline metadata (timestamp) on the last line.
///
/// No read-more trim — full body is shown when inline trailing meta is active.
class RoomMessageTextBody extends StatelessWidget {
  const RoomMessageTextBody({
    required this.display,
    required this.dateLine,
    required this.bodyStyle,
    required this.metaStyle,
    required this.metrics,
    this.mentionAnnotations,
    this.textAlign = TextAlign.start,
    super.key,
  });

  final String display;
  final String dateLine;
  final TextStyle bodyStyle;
  final TextStyle metaStyle;
  final TrailingMetaMetrics metrics;
  final List<Annotation>? mentionAnnotations;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);

    final span = buildMessageTextSpanWithTrailingMeta(
      display: display,
      bodyStyle: bodyStyle,
      mentionAnnotations: mentionAnnotations,
      metrics: metrics,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Text.rich(
          span,
          textAlign: textAlign,
          textDirection: textDirection,
          softWrap: true,
          textScaler: textScaler,
          locale: locale,
        ),
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: Text(
            dateLine,
            style: metaStyle,
            textDirection: textDirection,
            textScaler: textScaler,
            locale: locale,
          ),
        ),
      ],
    );
  }
}
