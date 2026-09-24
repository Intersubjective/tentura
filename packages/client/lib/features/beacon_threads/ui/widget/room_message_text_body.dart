import 'package:flutter/material.dart';
import 'package:readmore/readmore.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/room_message_mention_span.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_trailing_meta_layout.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';

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
    this.explicitSpans = const [],
    this.explicitMentionStyle,
    this.textAlign = TextAlign.start,
    this.trailingGlyph,
    super.key,
  });

  final String display;
  final String dateLine;
  final TextStyle bodyStyle;
  final TextStyle metaStyle;
  final TrailingMetaMetrics metrics;
  final List<Annotation>? mentionAnnotations;
  final List<RoomMessageMentionSpan> explicitSpans;
  final TextStyle? Function(String userId)? explicitMentionStyle;
  final TextAlign textAlign;
  final Widget? trailingGlyph;

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
      explicitSpans: explicitSpans,
      explicitMentionStyle: explicitMentionStyle,
    );

    // A single line of text reports only its own tight width, so force full
    // width or the date anchors to the text's edge, not the bubble's.
    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TenturaSelectionArea(
                child: Text.rich(
                  span,
                  textAlign: textAlign,
                  textDirection: textDirection,
                  softWrap: true,
                  textScaler: textScaler,
                  locale: locale,
                ),
              ),
              SizedBox(height: metrics.verticalTuckGap),
            ],
          ),
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: trailingGlyph == null
                ? Text(
                    dateLine,
                    style: metaStyle,
                    textDirection: textDirection,
                    textScaler: textScaler,
                    locale: locale,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        dateLine,
                        style: metaStyle,
                        textDirection: textDirection,
                        textScaler: textScaler,
                        locale: locale,
                      ),
                      SizedBox(width: context.tt.tightGap),
                      trailingGlyph!,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
