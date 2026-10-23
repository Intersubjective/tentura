@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_viewer_slice.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_last_event.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_last_event_row.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_latest_message_line.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_plan_step_rows.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// #532 — the Requests desk card lines («Time to sum up · 2m ago», «Nina:
/// Parking sorted? · 1m», «Olga · 2m ago: …») read their age off the clock
/// when the card was built, or on a per-card timer of their own. Each follows
/// the shared ticking clock, with no data change.
final _at = DateTime.utc(2026, 10, 14, 12);

const _author = Profile(id: 'author1', displayName: 'Alice Author');

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('en'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 400, child: child),
      ),
    ),
  ),
);

PlanViewerSlice _pendingSlice() => PlanViewerSlice.tryDecode(
  jsonEncode({
    'current': {
      'stepId': 'PSa',
      'title': 'Bring boards',
      'startAt': _at.subtract(const Duration(minutes: 40)).toIso8601String(),
      'endAt': _at.add(const Duration(hours: 2)).toIso8601String(),
    },
    'alsoActive': const <Object?>[],
    'next': null,
    'pendingAck': {
      'fromSeq': 3,
      'headSeq': 4,
      'changeCount': 1,
      'actorIds': ['Uolga'],
      'actorNames': {'Uolga': 'Olga'},
      'stepIds': ['PSa'],
      'lastAt': _at.toIso8601String(),
      'sample': {
        'op': 'retitled',
        'stepId': 'PSa',
        'title': 'Bring boards',
        'fromTitle': 'Bring wood',
        'from': 'Bring wood',
        'to': 'Bring boards',
      },
    },
  }),
)!;

MyWorkCardViewModel _vm({
  Beacon? beacon,
  MyWorkLastEvent? lastActivityEvent,
  DateTime? roomLatestMessageAt,
}) {
  final b =
      beacon ??
      Beacon.empty.copyWith(id: 'b1', title: 'Moving day', author: _author);
  return MyWorkCardViewModel(
    beaconId: b.id,
    role: MyWorkCardRole.authored,
    kind: MyWorkCardKind.authoredActive,
    beacon: b,
    lastActivityEvent: lastActivityEvent,
    roomLatestMessageText: 'Parking sorted?',
    roomLatestMessageAuthorId: 'u-nina',
    roomLatestMessageAuthorName: 'Nina',
    roomLatestMessageAt: roomLatestMessageAt,
  );
}

void main() {
  late DateTime clock;

  setUp(() {
    // 30 s after the event, on a :30 boundary of the shared clock.
    clock = _at.add(const Duration(seconds: 30));
    RelativeTimestampTicker.debugClock = () => clock;
  });
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  Future<void> advance(WidgetTester tester, Duration by) async {
    clock = clock.add(by);
    await tester.pump(by);
  }

  testWidgets('the last-event line age keeps counting while the card is open', (
    tester,
  ) async {
    final last = MyWorkLastEvent(
      event: BeaconActivityEvent(
        id: 'e1',
        beaconId: 'b1',
        visibility: 0,
        type: BeaconActivityEventTypeBits.beaconPublished,
        createdAt: _at,
        actorId: _author.id,
      ),
      actor: _author,
    );
    await tester.pumpWidget(
      _host(
        MyWorkLastEventBody(
          beacon: _vm().beacon,
          viewModel: _vm(lastActivityEvent: last),
          currentUserId: 'viewer',
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Just now'), findsOneWidget);

    await advance(tester, const Duration(minutes: 2));
    expect(find.textContaining('Just now'), findsNothing);
    expect(find.textContaining('2m ago'), findsOneWidget);
  });

  testWidgets('the «updated» placeholder age keeps counting too', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b1',
      createdAt: _at.subtract(const Duration(days: 1)),
      updatedAt: _at,
    );
    await tester.pumpWidget(
      _host(
        MyWorkLastEventBody(
          beacon: beacon,
          viewModel: _vm(beacon: beacon),
          currentUserId: 'viewer',
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Just now'), findsOneWidget);

    await advance(tester, const Duration(minutes: 2));
    expect(find.textContaining('2m ago'), findsOneWidget);
  });

  testWidgets('the latest-message line age keeps counting while open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MyWorkLatestMessageLine(
          vm: _vm(roomLatestMessageAt: _at),
          currentUserId: 'u-me',
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Nina: Parking sorted? · now'), findsOneWidget);

    await advance(tester, const Duration(minutes: 2));
    expect(find.textContaining('Nina: Parking sorted? · 2m'), findsOneWidget);
  });

  testWidgets('a latest-message line given a fixed clock keeps it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MyWorkLatestMessageLine(
          vm: _vm(roomLatestMessageAt: _at),
          currentUserId: 'u-me',
          now: _at.add(const Duration(minutes: 5)),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Nina: Parking sorted? · 5m'), findsOneWidget);

    await advance(tester, const Duration(minutes: 2));
    expect(find.textContaining('Nina: Parking sorted? · 5m'), findsOneWidget);
  });

  testWidgets('a plan change row age keeps counting while the card is open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MyWorkPlanStepRows(
          slice: _pendingSlice(),
          // The clock the card was built against stays put: no data change.
          now: clock,
          viewerId: 'Uviewer',
          nameOf: (id) => id ?? '',
          onAck: (_) {},
        ),
      ),
    );
    await tester.pump();
    final row = find.byKey(MyWorkPlanKeys.pending);
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining('Olga · Just now'),
      ),
      findsOneWidget,
    );

    await advance(tester, const Duration(minutes: 2));
    expect(
      find.descendant(of: row, matching: find.textContaining('Olga · 2m ago')),
      findsOneWidget,
    );
  });
}
