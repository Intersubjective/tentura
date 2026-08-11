import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/model/tab_attention_display.dart';

void main() {
  group('resolveTabAttentionDisplay', () {
    test('returns none when tab is visible', () {
      expect(
        resolveTabAttentionDisplay(unreadTotal: 5, isBackground: false),
        tabAttentionNone,
      );
    });

    test('returns none when unread is zero', () {
      expect(
        resolveTabAttentionDisplay(unreadTotal: 0, isBackground: true),
        tabAttentionNone,
      );
    });

    test('returns none when visible and unread is zero', () {
      expect(
        resolveTabAttentionDisplay(unreadTotal: 0, isBackground: false),
        tabAttentionNone,
      );
    });

    test('returns verbatim label for 1..99 while backgrounded', () {
      for (var n = 1; n <= kTabAttentionDisplayCap; n++) {
        final display = resolveTabAttentionDisplay(
          unreadTotal: n,
          isBackground: true,
        );
        expect(display.count, n);
        expect(display.label, '$n');
      }
    });

    test('caps label at 99+ while keeping raw count at 100', () {
      final display = resolveTabAttentionDisplay(
        unreadTotal: 100,
        isBackground: true,
      );
      expect(display.count, 100);
      expect(display.label, '99+');
    });

    test('caps label at 99+ while keeping raw count above cap', () {
      final display = resolveTabAttentionDisplay(
        unreadTotal: 250,
        isBackground: true,
      );
      expect(display.count, 250);
      expect(display.label, '99+');
    });

    test('label at cap boundary is verbatim', () {
      final display = resolveTabAttentionDisplay(
        unreadTotal: kTabAttentionDisplayCap,
        isBackground: true,
      );
      expect(display.count, kTabAttentionDisplayCap);
      expect(display.label, '$kTabAttentionDisplayCap');
    });

    test('100 and 101 produce different records with identical labels', () {
      final at100 = resolveTabAttentionDisplay(
        unreadTotal: 100,
        isBackground: true,
      );
      final at101 = resolveTabAttentionDisplay(
        unreadTotal: 101,
        isBackground: true,
      );
      expect(at100.label, at101.label);
      expect(at100, isNot(equals(at101)));
      expect(at100.count, 100);
      expect(at101.count, 101);
    });
  });

  group('composeTabTitle', () {
    const baseTitle = 'Tentura';

    test('returns base title when display is none', () {
      expect(
        composeTabTitle(baseTitle: baseTitle, display: tabAttentionNone),
        baseTitle,
      );
    });

    test('prefixes active display label', () {
      final display = resolveTabAttentionDisplay(
        unreadTotal: 3,
        isBackground: true,
      );
      expect(
        composeTabTitle(baseTitle: baseTitle, display: display),
        '(3) Tentura',
      );
    });

    test('prefixes capped label', () {
      final display = resolveTabAttentionDisplay(
        unreadTotal: 150,
        isBackground: true,
      );
      expect(
        composeTabTitle(baseTitle: baseTitle, display: display),
        '(99+) Tentura',
      );
    });
  });
}
