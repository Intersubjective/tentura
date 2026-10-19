import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/activity_list.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_details_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/schedule_date_format.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'beacon_view_screen_harness.dart';

// #450: the same request date read "Oct 17 – Oct 18" in the editor,
// "10/17/2026 - 10/18/2026" in the public view (showcase + Details sheet)
// and "10/17/2026 14:30" in the Log, whatever the app locale. One
// locale-aware format everywhere; never a numeric M/d/y (or d.M.y) date.

/// Any all-numeric calendar date: 10/17/2026, 17.10.2026, 10-17-26 ...
final _numericDate = RegExp(r'\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b');

const _locales = [Locale('en'), Locale('ru')];

/// Midnight of today plus [days], at [hour] local, sent as UTC like the API.
DateTime _localAt(int days, int hour, [int minute = 0]) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days, hour, minute).toUtc();
}

List<String> _textsUnder(WidgetTester tester, Finder scope) => tester
    .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .toList();

void _expectNoNumericDates(List<String> texts) {
  for (final t in texts) {
    expect(
      _numericDate.hasMatch(t),
      isFalse,
      reason: 'numeric date leaked into "$t"',
    );
  }
}

/// Editor parity: the request editor summarises a window with
/// `formatScheduleRange` (info_tab.dart `_timingSummary`).
String _editorRange(DateTime start, DateTime end, Locale locale) =>
    formatScheduleRange(
      start,
      end,
      localeName: lookupL10n(locale).localeName,
      now: DateTime.now(),
    );

String _editorDate(DateTime d, Locale locale) => formatScheduleDate(
  d,
  localeName: lookupL10n(locale).localeName,
  now: DateTime.now(),
);

String _editorDeadline(DateTime d, Locale locale) =>
    lookupL10n(locale).beaconCardScheduleDeadlineBy(_editorDate(d, locale));

Future<void> _pumpShowcase(
  WidgetTester tester, {
  required Locale locale,
  DateTime? startAt,
  DateTime? endAt,
}) async {
  final author = beaconViewHarnessAuthorState();
  final state = author.copyWith(
    beacon: author.beacon.copyWith(
      accessLevel: BeaconAccessLevel.observer,
      viewerCanForward: true,
      startAt: startAt,
      endAt: endAt,
    ),
    myProfile: const Profile(id: 'outsider', displayName: 'Outsider'),
    roomParticipants: const [],
  );
  await pumpBeaconViewHarness(
    tester,
    size: kBeaconViewHarnessCompact,
    beaconState: state,
    threadsState: beaconViewHarnessThreadsState(),
    locale: locale,
  );
  expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
}

Future<void> _openDetailsSheet(
  WidgetTester tester, {
  required Locale locale,
  required Beacon beacon,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showBeaconViewDetailsSheet(ctx, beacon: beacon),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpLog(
  WidgetTester tester, {
  required Locale locale,
  required DateTime createdAt,
}) async {
  final beacon = Beacon(
    id: 'b-450',
    title: 'Garden beds',
    author: const Profile(id: 'author-450', displayName: 'Author'),
    createdAt: createdAt,
    updatedAt: createdAt,
  );
  final event = BeaconActivityEvent(
    id: 'ev-published-450',
    beaconId: 'b-450',
    visibility: BeaconActivityEventVisibilityBits.public,
    type: BeaconActivityEventTypeBits.beaconPublished,
    createdAt: createdAt,
    actorId: 'author-450',
    diffJson: jsonEncode({'title': 'Garden beds'}),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: BeaconActivityList(
            timeline: const [],
            beacon: beacon,
            isAuthorView: true,
            roomActivityEvents: [event],
            coordinationLogOnly: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  group('public view (showcase)', () {
    tearDown(unregisterBeaconViewHarnessGetIt);

    for (final locale in _locales) {
      testWidgets(
        'event window reads like the editor (${locale.languageCode})',
        (
          tester,
        ) async {
          final start = _localAt(10, 10);
          final end = _localAt(11, 18);
          await _pumpShowcase(
            tester,
            locale: locale,
            startAt: start,
            endAt: end,
          );

          final texts = _textsUnder(tester, find.byType(BeaconShowcaseSurface));
          expect(texts, contains(_editorRange(start, end, locale)));
          _expectNoNumericDates(texts);
        },
      );
    }

    for (final locale in _locales) {
      testWidgets(
        'a start-only event reads exactly like the editor '
        '(${locale.languageCode})',
        (tester) async {
          final start = _localAt(10, 10);
          await _pumpShowcase(tester, locale: locale, startAt: start);

          final texts = _textsUnder(tester, find.byType(BeaconShowcaseSurface));
          // Editor (_timingSummary): start only -> formatScheduleDate alone,
          // no dangling " - ".
          expect(texts, contains(_editorDate(start, locale)));
          _expectNoNumericDates(texts);
        },
      );

      testWidgets(
        'a deadline reads exactly like the editor (${locale.languageCode})',
        (tester) async {
          final end = _localAt(12, 18);
          await _pumpShowcase(tester, locale: locale, endAt: end);

          final texts = _textsUnder(tester, find.byType(BeaconShowcaseSurface));
          // Editor (_timingSummary): end only -> "by {date}" / "до {date}",
          // no leading " - ".
          expect(texts, contains(_editorDeadline(end, locale)));
          _expectNoNumericDates(texts);
        },
      );
    }
  });

  group('Details sheet', () {
    for (final locale in _locales) {
      testWidgets(
        'event window reads like the editor (${locale.languageCode})',
        (
          tester,
        ) async {
          final start = _localAt(10, 10);
          final end = _localAt(11, 18);
          final beacon = Beacon(
            id: 'b-450',
            title: 'Garden beds',
            createdAt: DateTime.utc(2026, 10),
            updatedAt: DateTime.utc(2026, 10),
            startAt: start,
            endAt: end,
          );
          await _openDetailsSheet(tester, locale: locale, beacon: beacon);

          final texts = _textsUnder(tester, find.byType(MaterialApp));
          expect(texts, contains(_editorRange(start, end, locale)));
          _expectNoNumericDates(texts);
        },
      );
    }

    testWidgets('a start-only event reads exactly like the editor (ru)', (
      tester,
    ) async {
      const locale = Locale('ru');
      final start = _localAt(10, 10);
      final beacon = Beacon(
        id: 'b-450',
        title: 'Garden beds',
        createdAt: DateTime.utc(2026, 10),
        updatedAt: DateTime.utc(2026, 10),
        startAt: start,
      );
      await _openDetailsSheet(tester, locale: locale, beacon: beacon);

      final texts = _textsUnder(tester, find.byType(MaterialApp));
      // No trailing '-' for a missing end: exactly the editor's single date.
      expect(texts, contains(_editorDate(start, locale)));
      for (final t in texts) {
        expect(t.trim(), isNot(endsWith('-')), reason: 'texts: $texts');
      }
      _expectNoNumericDates(texts);
    });
  });

  group('Log', () {
    for (final locale in _locales) {
      testWidgets(
        'row timestamp uses the same date format (${locale.languageCode})',
        (
          tester,
        ) async {
          final created = _localAt(-3, 14, 30);
          await _pumpLog(tester, locale: locale, createdAt: created);

          final localeName = lookupL10n(locale).localeName;
          final date = _editorDate(created, locale);
          final time = DateFormat.Hm(localeName).format(created.toLocal());
          final texts = _textsUnder(tester, find.byType(BeaconActivityList));
          expect(
            texts.where((t) => t.contains(date) && t.contains(time)),
            hasLength(1),
            reason: 'texts: $texts',
          );
          _expectNoNumericDates(texts);
        },
      );
    }
  });
}
