import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/features/friends/ui/invite_accepted_subtitle.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));
  final now = DateTime(2026, 6, 12, 12);

  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  test('under 7 days uses relative time', () {
    expect(
      inviteAcceptedSubtitle(
        l10n: l10n,
        acceptedAt: now.subtract(const Duration(hours: 3)),
        now: now,
      ),
      'Joined 3h ago',
    );
  });

  test('just under the 7-day boundary still uses relative time', () {
    expect(
      inviteAcceptedSubtitle(
        l10n: l10n,
        acceptedAt: now.subtract(const Duration(days: 6, hours: 23)),
        now: now,
      ),
      startsWith('Joined'),
    );
    expect(
      inviteAcceptedSubtitle(
        l10n: l10n,
        acceptedAt: now.subtract(const Duration(days: 6, hours: 23)),
        now: now,
      ),
      isNot(contains('on ')),
      reason: 'still relative, not yet the absolute-date form',
    );
  });

  test('at/after 7 days switches to an absolute date so it never decays '
      "into a meaningless 'N days ago'", () {
    expect(
      inviteAcceptedSubtitle(
        l10n: l10n,
        acceptedAt: now.subtract(const Duration(days: 7)),
        now: now,
      ),
      'Joined on Jun 5',
    );
  });

  test('far in the past includes the year', () {
    expect(
      inviteAcceptedSubtitle(
        l10n: l10n,
        acceptedAt: DateTime(2024, 3),
        now: now,
      ),
      'Joined on Mar 1, 2024',
    );
  });
}
