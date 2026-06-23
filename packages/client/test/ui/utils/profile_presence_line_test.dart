import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';
import 'package:tentura_root/domain/enums.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  final l10n = lookupL10n(const Locale('en'));
  const locale = Locale('en');

  test('returns online label when status is online', () {
    expect(
      profilePresenceDisplayLine(
        l10n: l10n,
        locale: locale,
        status: UserPresenceStatus.online,
        lastSeenAt: DateTime.now(),
      ),
      l10n.chatPresenceOnline,
    );
  });

  test('returns empty when last seen is missing or epoch', () {
    expect(
      profilePresenceDisplayLine(l10n: l10n, locale: locale),
      '',
    );
    expect(
      profilePresenceDisplayLine(
        l10n: l10n,
        locale: locale,
        lastSeenAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      '',
    );
  });

  test('returns just now for under one minute ago', () {
    expect(
      profilePresenceDisplayLine(
        l10n: l10n,
        locale: locale,
        lastSeenAt: DateTime.now().subtract(const Duration(seconds: 30)),
      ),
      l10n.chatPresenceLastSeenJustNow,
    );
  });

  test('returns minutes for under one hour ago', () {
    expect(
      profilePresenceDisplayLine(
        l10n: l10n,
        locale: locale,
        lastSeenAt: DateTime.now().subtract(const Duration(minutes: 12)),
      ),
      l10n.chatPresenceLastSeenMinutes(12),
    );
  });

  test('returns hours for under one day ago', () {
    expect(
      profilePresenceDisplayLine(
        l10n: l10n,
        locale: locale,
        lastSeenAt: DateTime.now().subtract(const Duration(hours: 4)),
      ),
      l10n.chatPresenceLastSeenHours(4),
    );
  });

  test('returns days for one to six calendar days ago', () {
    final now = DateTime.now();
    final twoDaysAgo = DateTime(now.year, now.month, now.day - 2, 10);
    expect(
      profilePresenceDisplayLine(
        l10n: l10n,
        locale: locale,
        lastSeenAt: twoDaysAgo,
      ),
      l10n.chatPresenceLastSeenDays(2),
    );
  });

  test('returns formatted date for seven or more calendar days ago', () {
    final now = DateTime.now();
    final eightDaysAgo = DateTime(now.year, now.month, now.day - 8, 10);
    final formatted =
        profilePresenceDisplayLine(
          l10n: l10n,
          locale: locale,
          lastSeenAt: eightDaysAgo,
        );
    expect(formatted, startsWith('Last seen '));
    expect(formatted, isNot(l10n.chatPresenceLastSeenDays(8)));
  });
}
