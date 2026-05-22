import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_room/ui/widget/room_message_bubble_measure.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_trailing_meta_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const textDirection = TextDirection.ltr;
  const textScaler = TextScaler.linear(1);

  const bodyStyle = TextStyle(fontSize: 15, height: 1.4);
  const metaStyle = TextStyle(fontSize: 12, height: 1.2);

  group('shouldUseInlineTrailingMeta', () {
    test('false when body empty', () {
      expect(
        shouldUseInlineTrailingMeta(
          hasDisplayText: false,
          reactionCounts: const {},
        ),
        isFalse,
      );
    });

    test('false when reactions present', () {
      expect(
        shouldUseInlineTrailingMeta(
          hasDisplayText: true,
          reactionCounts: const {'👍': 1},
        ),
        isFalse,
      );
    });

    test('true for text-only without reactions', () {
      expect(
        shouldUseInlineTrailingMeta(
          hasDisplayText: true,
          reactionCounts: const {},
        ),
        isTrue,
      );
    });
  });

  group('computeTrailingMetaMetrics', () {
    test('reserve dimensions are positive', () {
      final m = computeTrailingMetaMetrics(
        dateLine: '12:34',
        metaStyle: metaStyle,
        bodyStyle: bodyStyle,
        trailingGap: 4.0,
        textDirection: textDirection,
        textScaler: textScaler,
      );
      expect(m.reserveWidth, greaterThan(0));
      expect(m.reserveHeight, greaterThan(0));
      expect(m.bodyLineHeight, greaterThan(0));
      expect(m.trailingGap, 4.0);
    });

    test('edited suffix widens reserve', () {
      final bare = computeTrailingMetaMetrics(
        dateLine: '12:34',
        metaStyle: metaStyle,
        bodyStyle: bodyStyle,
        trailingGap: 4.0,
        textDirection: textDirection,
        textScaler: textScaler,
      );
      final edited = computeTrailingMetaMetrics(
        dateLine: '12:34 · edited',
        metaStyle: metaStyle,
        bodyStyle: bodyStyle,
        trailingGap: 4.0,
        textDirection: textDirection,
        textScaler: textScaler,
      );
      expect(edited.reserveWidth, greaterThan(bare.reserveWidth));
    });
  });

  group('measureTightTextWidth', () {
    test('short text width includes trailing reserve', () {
      const display = 'Hi';
      const dateLine = '12:34';
      const trailingGap = 4.0;
      final metrics = computeTrailingMetaMetrics(
        dateLine: dateLine,
        metaStyle: metaStyle,
        bodyStyle: bodyStyle,
        trailingGap: trailingGap,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      final bodyOnly = buildRoomMessageAnnotatedBodySpan(
        data: display,
        textStyle: bodyStyle,
        annotations: null,
      );
      final bodyWidth = measureTightTextWidth(
        span: bodyOnly,
        maxWidth: 400,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      final fullWidth = measureTightBodyWidthWithTrailingReserve(
        bodySpan: bodyOnly,
        trailingReserveWidth: metrics.reserveWidth,
        maxWidth: 400,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      expect(fullWidth, greaterThan(bodyWidth));
      expect(fullWidth - bodyWidth, closeTo(metrics.reserveWidth, 2));
    });

    test('long wrapping text width is at least body-only width', () {
      const display =
          'This is a longer message that should wrap across multiple '
          'lines when constrained to a modest max width.';
      const dateLine = '09:15';
      final metrics = computeTrailingMetaMetrics(
        dateLine: dateLine,
        metaStyle: metaStyle,
        bodyStyle: bodyStyle,
        trailingGap: 4.0,
        textDirection: textDirection,
        textScaler: textScaler,
      );
      const maxWidth = 180.0;

      final bodySpan = buildRoomMessageAnnotatedBodySpan(
        data: display,
        textStyle: bodyStyle,
        annotations: null,
      );
      final width = measureTightBodyWidthWithTrailingReserve(
        bodySpan: bodySpan,
        trailingReserveWidth: metrics.reserveWidth,
        maxWidth: maxWidth,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      expect(width, greaterThan(0));
      expect(width, lessThanOrEqualTo(maxWidth + 1));
    });
  });

  group('measureBubble', () {
    test('text-only hugs tight width plus padding', () {
      const contentMax = 300.0;
      const cardPaddingH = 24.0;
      const tight = 120.0;
      final r = measureBubble(
        contentMaxWidth: contentMax,
        cardPaddingH: cardPaddingH,
        tightTextWidth: tight,
        hasMediaOrPoll: false,
      );
      expect(r.innerWidth, tight + cardPaddingH);
    });

    test('with media floors at content max plus padding', () {
      const contentMax = 300.0;
      const cardPaddingH = 24.0;
      final r = measureBubble(
        contentMaxWidth: contentMax,
        cardPaddingH: cardPaddingH,
        tightTextWidth: 80,
        hasMediaOrPoll: true,
      );
      expect(r.innerWidth, contentMax + cardPaddingH);
    });

    test('clamps text width to content max plus padding', () {
      const contentMax = 200.0;
      const cardPaddingH = 24.0;
      final r = measureBubble(
        contentMaxWidth: contentMax,
        cardPaddingH: cardPaddingH,
        tightTextWidth: 500,
        hasMediaOrPoll: false,
      );
      expect(r.innerWidth, contentMax + cardPaddingH);
    });

    test('null tight width uses content max', () {
      final r = measureBubble(
        contentMaxWidth: 200,
        cardPaddingH: 24,
        tightTextWidth: null,
        hasMediaOrPoll: false,
      );
      expect(r.innerWidth, 224);
    });
  });
}
