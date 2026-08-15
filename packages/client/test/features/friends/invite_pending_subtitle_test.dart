import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/friends/ui/invite_pending_subtitle.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));
  final now = DateTime(2026, 6, 12, 12);

  test('joins Waiting with relative time', () {
    expect(
      invitePendingSubtitle(
        l10n: l10n,
        when: now.subtract(const Duration(hours: 1)),
        now: now,
      ),
      'Waiting · 1h ago',
    );
  });

  test('uses just now under one minute', () {
    expect(
      invitePendingSubtitle(
        l10n: l10n,
        when: now.subtract(const Duration(seconds: 30)),
        now: now,
      ),
      'Waiting · Just now',
    );
  });
}
