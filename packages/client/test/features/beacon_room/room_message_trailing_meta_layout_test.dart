import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readmore/readmore.dart';

import 'package:tentura/features/beacon_room/ui/widget/room_message_bubble_measure.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_trailing_meta_layout.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';

({String text, Color? color, bool hasRecognizer}) _leaf(TextSpan s) =>
    (text: s.text!, color: s.style?.color, hasRecognizer: s.recognizer != null);

List<({String text, Color? color, bool hasRecognizer})> _flattenLeaves(
  InlineSpan span,
) {
  final result = <({String text, Color? color, bool hasRecognizer})>[];
  void visit(InlineSpan s) {
    if (s is! TextSpan) return;
    if (s.text != null && s.text!.isNotEmpty) {
      result.add(_leaf(s));
    }
    s.children?.forEach(visit);
  }

  visit(span);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const textDirection = TextDirection.ltr;
  const textScaler = TextScaler.noScaling;

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

  group('shouldHugBubbleWidth', () {
    test('true for text with reactions when no media', () {
      expect(
        shouldHugBubbleWidth(
          hasMediaOrPoll: false,
          hasDisplayText: true,
          hasReactions: true,
          hasFooterContent: false,
        ),
        isTrue,
      );
    });

    test('true when media or poll needs a capped bubble', () {
      expect(
        shouldHugBubbleWidth(
          hasMediaOrPoll: true,
          hasDisplayText: true,
          hasReactions: true,
          hasFooterContent: false,
        ),
        isTrue,
      );
    });

    test('true for reactions-only footer', () {
      expect(
        shouldHugBubbleWidth(
          hasMediaOrPoll: false,
          hasDisplayText: false,
          hasReactions: true,
          hasFooterContent: false,
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
        trailingGap: 4,
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
        trailingGap: 4,
        textDirection: textDirection,
        textScaler: textScaler,
      );
      final edited = computeTrailingMetaMetrics(
        dateLine: '12:34 · edited',
        metaStyle: metaStyle,
        bodyStyle: bodyStyle,
        trailingGap: 4,
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
        trailingGap: 4,
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

  group('measureReactionTimeRowMinWidth', () {
    test('single chip plus time is wider than bare text', () {
      const emojiStyle = TextStyle(fontSize: 16, height: 1);
      const countStyle = TextStyle(fontSize: 14, height: 1);
      const display = 'Hi';

      final bodySpan = buildRoomMessageAnnotatedBodySpan(
        data: display,
        textStyle: bodyStyle,
        annotations: null,
      );
      final bodyWidth = measureTightTextWidth(
        span: bodySpan,
        maxWidth: 400,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      final rowWidth = measureReactionTimeRowMinWidth(
        reactionEntries: const [MapEntry('👍', 2)],
        reactorCountsByEmoji: const {},
        dateLine: '12:34',
        emojiStyle: emojiStyle,
        countStyle: countStyle,
        timeStyle: metaStyle,
        chipSpacing: 8,
        trailingGap: 4,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      expect(rowWidth, greaterThan(bodyWidth));
    });

    test('chip width includes border allowance', () {
      const emojiStyle = TextStyle(fontSize: 16, height: 1);
      const countStyle = TextStyle(fontSize: 14, height: 1);

      final withBorder = measureReactionChipWidth(
        emoji: '👍',
        count: 1,
        reactorCount: 0,
        emojiStyle: emojiStyle,
        countStyle: countStyle,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      expect(withBorder, greaterThan(kReactionChipHorizontalChrome));
    });

    test('angry emoji with reactors is wider than emoji-only baseline', () {
      const emojiStyle = TextStyle(fontSize: 16, height: 1);
      const countStyle = TextStyle(fontSize: 14, height: 1);
      const angry = '😠';

      final emojiOnly = measureReactionChipWidth(
        emoji: angry,
        count: 1,
        reactorCount: 0,
        emojiStyle: emojiStyle,
        countStyle: countStyle,
        textDirection: textDirection,
        textScaler: textScaler,
      );
      final withReactors = measureReactionChipWidth(
        emoji: angry,
        count: 2,
        reactorCount: 2,
        emojiStyle: emojiStyle,
        countStyle: countStyle,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      expect(withReactors, greaterThan(emojiOnly));
      expect(
        withReactors,
        greaterThan(reactorAvatarStripWidth(2) + kReactionChipHorizontalChrome),
      );
    });
  });

  group('ensureHugWidthFitsReactionFooter', () {
    test('widens when body text wins but chip band is too narrow', () {
      const emojiStyle = TextStyle(fontSize: 16, height: 1);
      const countStyle = TextStyle(fontSize: 14, height: 1);
      const entries = [MapEntry('👍', 2)];

      final footerRow = measureReactionTimeRowMinWidth(
        reactionEntries: entries,
        reactorCountsByEmoji: const {},
        dateLine: '12:34',
        emojiStyle: emojiStyle,
        countStyle: countStyle,
        timeStyle: metaStyle,
        chipSpacing: 8,
        trailingGap: 4,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      final bodySpan = buildRoomMessageAnnotatedBodySpan(
        data: 'Nice work everyone',
        textStyle: bodyStyle,
        annotations: null,
      );
      final bodyWidth = measureTightTextWidth(
        span: bodySpan,
        maxWidth: 400,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      final ensured = ensureHugWidthFitsReactionFooter(
        contentWidth: bodyWidth,
        reactionEntries: entries,
        reactorCountsByEmoji: const {},
        dateLine: '12:34',
        emojiStyle: emojiStyle,
        countStyle: countStyle,
        timeStyle: metaStyle,
        chipSpacing: 8,
        trailingGap: 4,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      expect(ensured, greaterThanOrEqualTo(footerRow));
      if (bodyWidth > footerRow) {
        expect(ensured, greaterThanOrEqualTo(bodyWidth));
      }
    });

    test('chip band leaves room for angry emoji reactors beside timestamp', () {
      const emojiStyle = TextStyle(fontSize: 16, height: 1);
      const countStyle = TextStyle(fontSize: 14, height: 1);
      const entries = [MapEntry('😠', 2)];
      const dateLine = '12:34';

      final timePainter = TextPainter(
        text: const TextSpan(text: dateLine, style: metaStyle),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final timeBand = (4 + timePainter.width).ceilToDouble();

      var chipsWidth = 0.0;
      for (final entry in entries) {
        chipsWidth += measureReactionChipWidth(
          emoji: entry.key,
          count: entry.value,
          reactorCount: 2,
          emojiStyle: emojiStyle,
          countStyle: countStyle,
          textDirection: textDirection,
          textScaler: textScaler,
        );
      }

      final ensured = ensureHugWidthFitsReactionFooter(
        contentWidth: 40,
        reactionEntries: entries,
        reactorCountsByEmoji: const {'😠': 2},
        dateLine: dateLine,
        emojiStyle: emojiStyle,
        countStyle: countStyle,
        timeStyle: metaStyle,
        chipSpacing: 8,
        trailingGap: 4,
        textDirection: textDirection,
        textScaler: textScaler,
      );

      expect(ensured - timeBand, greaterThanOrEqualTo(chipsWidth));
      expect(ensured, greaterThanOrEqualTo(chipsWidth + timeBand));
    });
  });

  group('measureLifecycleTapRowMinWidth', () {
    test('wider than trailing meta reserve alone', () {
      final metrics = computeTrailingMetaMetrics(
        dateLine: '12:34',
        metaStyle: metaStyle,
        bodyStyle: bodyStyle,
        trailingGap: 4,
        textDirection: textDirection,
        textScaler: textScaler,
      );
      final rowWidth = measureLifecycleTapRowMinWidth(
        label: 'Coordination need',
        time: '12:34',
        labelStyle: metaStyle.copyWith(fontWeight: FontWeight.w600),
        timeStyle: metaStyle,
        itemGap: 4,
        showChevron: true,
        textDirection: textDirection,
        textScaler: textScaler,
      );
      expect(rowWidth, greaterThan(metrics.reserveWidth));
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

    test('with media uses natural content width when it is under cap', () {
      const contentMax = 300.0;
      const cardPaddingH = 24.0;
      final r = measureBubble(
        contentMaxWidth: contentMax,
        cardPaddingH: cardPaddingH,
        tightTextWidth: null,
        hasMediaOrPoll: true,
        mediaContentWidth: 180,
      );
      expect(r.innerWidth, 180 + cardPaddingH);
    });

    test('does not allow tiny text bubbles below the minimum width', () {
      final r = measureBubble(
        contentMaxWidth: 300,
        cardPaddingH: 24,
        tightTextWidth: 18,
        hasMediaOrPoll: false,
        bubbleMinWidth: 160,
      );
      expect(r.innerWidth, 184);
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

  group('findUrlRanges', () {
    String matched(String text, TextRange r) => text.substring(r.start, r.end);

    test('finds a bare URL with no trailing punctuation', () {
      const text = 'See https://example.com for details';
      final ranges = findUrlRanges(text);
      expect(ranges, hasLength(1));
      expect(matched(text, ranges.single), 'https://example.com');
    });

    test('strips a trailing period', () {
      const text = 'Visit https://example.com.';
      final ranges = findUrlRanges(text);
      expect(matched(text, ranges.single), 'https://example.com');
    });

    test('strips a trailing comma', () {
      const text = 'Try https://example.com, thanks!';
      final ranges = findUrlRanges(text);
      expect(matched(text, ranges.single), 'https://example.com');
    });

    test('keeps a balanced closing paren from the URL path', () {
      const text = 'See https://en.wikipedia.org/wiki/Foo_(bar) now';
      final ranges = findUrlRanges(text);
      expect(
        matched(text, ranges.single),
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      );
    });

    test('strips an unbalanced wrapping paren and trailing period', () {
      const text = '(see https://en.wikipedia.org/wiki/Foo_(bar)).';
      final ranges = findUrlRanges(text);
      expect(
        matched(text, ranges.single),
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      );
    });

    test('rejects a match with no host', () {
      expect(findUrlRanges('https:///no-host-here'), isEmpty);
    });
  });

  group('buildUrlAnnotations + mention merge', () {
    const linkColor = Colors.blue;
    const mentionColor = Colors.purple;

    List<Annotation> mergedAnnotations() => [
      ...buildUrlAnnotations(linkColor: linkColor, onTapLink: (_) async {}),
      ...buildRoomMessageMentionAnnotations(
        handleToUserId: const {'alice': 'u1'},
        mentionedIds: const {'u1'},
        selfUserId: 'me',
        mentionColor: mentionColor,
        selfMentionBackground: Colors.yellow,
      ),
    ];

    test(
      'URL containing an @handle-shaped path segment is not mention-styled',
      () {
        final span = buildRoomMessageAnnotatedBodySpan(
          data: 'Check https://twitter.com/@alice today',
          textStyle: bodyStyle,
          annotations: mergedAnnotations(),
        );

        final leaves = _flattenLeaves(span);
        final linkLeaf = leaves.firstWhere((l) => l.hasRecognizer);
        expect(linkLeaf.text, 'https://twitter.com/@alice');
        expect(linkLeaf.color, linkColor);
        expect(leaves.any((l) => l.color == mentionColor), isFalse);
      },
    );

    test('a separate @mention elsewhere is still mention-styled', () {
      final span = buildRoomMessageAnnotatedBodySpan(
        data: 'Hi @alice, see https://example.com for context',
        textStyle: bodyStyle,
        annotations: mergedAnnotations(),
      );

      final leaves = _flattenLeaves(span);
      expect(
        leaves.any((l) => l.text == '@alice' && l.color == mentionColor),
        isTrue,
      );
      expect(
        leaves.any(
          (l) => l.hasRecognizer && l.text == 'https://example.com',
        ),
        isTrue,
      );
    });

    test('trailing punctuation is excluded from the recognizer span', () {
      const data = 'Try https://example.com, thanks!';
      final span = buildRoomMessageAnnotatedBodySpan(
        data: data,
        textStyle: bodyStyle,
        annotations: mergedAnnotations(),
      );

      final leaves = _flattenLeaves(span);
      final linkLeaf = leaves.firstWhere((l) => l.hasRecognizer);
      expect(linkLeaf.text, 'https://example.com');
      // Nothing lost/duplicated across leaves, and the comma stays outside
      // any tappable span.
      expect(leaves.map((l) => l.text).join(), data);
      expect(
        leaves.any((l) => l.hasRecognizer && l.text.contains(',')),
        isFalse,
      );
    });
  });
}
