import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));
  final now = DateTime(2026, 6, 12, 12, 0);

  group('compactRelativeTimeAgo', () {
    test('returns just now for under one minute', () {
      expect(
        compactRelativeTimeAgo(
          when: now.subtract(const Duration(seconds: 30)),
          now: now,
          l10n: l10n,
        ),
        'Just now',
      );
    });

    test('returns minutes for under one hour', () {
      expect(
        compactRelativeTimeAgo(
          when: now.subtract(const Duration(minutes: 5)),
          now: now,
          l10n: l10n,
        ),
        '5m ago',
      );
    });

    test('returns hours for under one day', () {
      expect(
        compactRelativeTimeAgo(
          when: now.subtract(const Duration(hours: 3)),
          now: now,
          l10n: l10n,
        ),
        '3h ago',
      );
    });

    test('returns calendar days for one day or more', () {
      expect(
        compactRelativeTimeAgo(
          when: DateTime(2026, 6, 10, 12, 0),
          now: now,
          l10n: l10n,
        ),
        '2d ago',
      );
    });

    test('returns just now for future timestamps', () {
      expect(
        compactRelativeTimeAgo(
          when: now.add(const Duration(minutes: 5)),
          now: now,
          l10n: l10n,
        ),
        'Just now',
      );
    });
  });
}
