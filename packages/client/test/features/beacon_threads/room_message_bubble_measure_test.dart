import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_bubble_measure.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_reply_quote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const countStyle = TextStyle(fontSize: 12);

  double measure({required int count, required bool hasUnread}) =>
      measureLifecycleThreadMarkWidth(
        count: count,
        hasUnread: hasUnread,
        countStyle: countStyle,
        itemGap: 8,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      );

  group('measureLifecycleThreadMarkWidth', () {
    test('reserves room for the forum mark even with no replies', () {
      expect(measure(count: 0, hasUnread: false), greaterThan(0));
    });

    test('grows when a reply count is shown', () {
      expect(
        measure(count: 3, hasUnread: false),
        greaterThan(measure(count: 0, hasUnread: false)),
      );
    });

    test('grows further when an unread dot is shown', () {
      expect(
        measure(count: 3, hasUnread: true),
        greaterThan(measure(count: 3, hasUnread: false)),
      );
    });
  });

  group('measureRoomReplyQuoteMinContentWidth', () {
    late TenturaTokens tt;
    const nameStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    const excerptStyle = TextStyle(fontSize: 13);
    const availableWidth = 280.0;

    setUp(() {
      tt = TenturaTokens.light.applyWindowClass(WindowClass.compact);
    });

    test('long quote wider than short body is reflected in min width', () {
      const shortBodyWidth = 40.0;
      final quoteWidth = measureRoomReplyQuoteMinContentWidth(
        authorName: 'Anna',
        excerpt:
            'abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ wider quote',
        availableWidth: availableWidth,
        nameStyle: nameStyle,
        excerptStyle: excerptStyle,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        tt: tt,
      );

      expect(quoteWidth, greaterThan(shortBodyWidth));
    });

    test('second excerpt line wider than first increases min width', () {
      final firstLineWide = measureRoomReplyQuoteMinContentWidth(
        authorName: 'Anna',
        excerpt: 'short\nWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW',
        availableWidth: availableWidth,
        nameStyle: nameStyle,
        excerptStyle: excerptStyle,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        tt: tt,
      );
      final singleShortLine = measureRoomReplyQuoteMinContentWidth(
        authorName: 'Anna',
        excerpt: 'short line only',
        availableWidth: availableWidth,
        nameStyle: nameStyle,
        excerptStyle: excerptStyle,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        tt: tt,
      );

      expect(firstLineWide, greaterThan(singleShortLine));
    });

    test('RTL direction is honored', () {
      final rtl = measureRoomReplyQuoteMinContentWidth(
        authorName: 'آنا',
        excerpt: 'هل يمكنك إحضار السلم غداً',
        availableWidth: availableWidth,
        nameStyle: nameStyle,
        excerptStyle: excerptStyle,
        textDirection: TextDirection.rtl,
        textScaler: TextScaler.noScaling,
        tt: tt,
      );
      final ltr = measureRoomReplyQuoteMinContentWidth(
        authorName: 'Anna',
        excerpt: 'can you bring the ladder tomorrow',
        availableWidth: availableWidth,
        nameStyle: nameStyle,
        excerptStyle: excerptStyle,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        tt: tt,
      );

      expect(rtl, greaterThan(0));
      expect(ltr, greaterThan(0));
    });

    test('1.6x text scaler widens measured quote chrome + text', () {
      const shortExcerpt = 'Hi';
      final scaled = measureRoomReplyQuoteMinContentWidth(
        authorName: 'Anna',
        excerpt: shortExcerpt,
        availableWidth: availableWidth,
        nameStyle: nameStyle,
        excerptStyle: excerptStyle,
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(1.6),
        tt: tt,
      );
      final base = measureRoomReplyQuoteMinContentWidth(
        authorName: 'Anna',
        excerpt: shortExcerpt,
        availableWidth: availableWidth,
        nameStyle: nameStyle,
        excerptStyle: excerptStyle,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        tt: tt,
      );

      expect(scaled, greaterThan(base));
    });

    test('includes fixed accent, gap, and inner padding chrome', () {
      final width = measureRoomReplyQuoteMinContentWidth(
        authorName: '',
        excerpt: 'x',
        availableWidth: availableWidth,
        nameStyle: nameStyle,
        excerptStyle: excerptStyle,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        tt: tt,
        showAuthor: false,
      );
      final innerPadding = roomReplyQuoteInnerPadding(tt);
      final excerptOnly = TextPainter(
        text: const TextSpan(text: 'x', style: excerptStyle),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 2,
      )..layout();
      final expectedChrome =
          kRoomReplyQuoteAccentWidth + tt.iconTextGap + innerPadding.horizontal;

      expect(width, closeTo(excerptOnly.width + expectedChrome, 1));
    });
  });
}
