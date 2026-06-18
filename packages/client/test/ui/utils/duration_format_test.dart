import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/duration_format.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));

  test('less than minute', () {
    expect(
      formatCompactDurationRemaining(Duration.zero, l10n),
      '<1m',
    );
  });

  test('minutes only', () {
    expect(
      formatCompactDurationRemaining(const Duration(minutes: 45), l10n),
      '45m',
    );
  });

  test('hours and minutes', () {
    expect(
      formatCompactDurationRemaining(const Duration(hours: 2, minutes: 15), l10n),
      '2h 15m',
    );
  });

  test('days and hours', () {
    expect(
      formatCompactDurationRemaining(const Duration(days: 3, hours: 5), l10n),
      '3d 5h',
    );
  });
}
