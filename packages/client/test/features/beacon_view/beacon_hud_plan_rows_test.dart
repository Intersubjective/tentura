@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_plan_rows.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_plan/beacon_plan_test_support.dart';

/// 10:20 UTC: step 2 (Ivan = ME, 10:00–10:30) runs, step 3 (11:30) is next.
final _now = DateTime.utc(2026, 10, 12, 10, 20);

const _me = Profile(id: 'ME', displayName: 'Ivan');
const _olga = Profile(id: 'U2', displayName: 'Olga');

BeaconViewState _state({
  Profile author = _olga,
  BeaconRoomState? cue,
  List<TimelineHelpOffer> offers = const [],
  BeaconStatus status = BeaconStatus.open,
}) => BeaconViewState(
  beacon: Beacon.empty.copyWith(
    id: 'B1',
    updatedAt: DateTime.utc(2026),
    author: author,
    status: status,
  ),
  myProfile: _me,
  admittedHelperRoster: const [_me],
  admittedHelpersLoaded: true,
  beaconRoomCue: cue,
  helpOffers: offers,
);

BeaconPlan _plan({Map<String, Object?>? viewerPending}) =>
    BeaconPlan.decode(planJson(viewerPending: viewerPending));

class _Calls {
  final done = <String>[];
  int acks = 0;
  final cantMake = <String>[];
  int openPlan = 0;
}

BeaconHudPlanData _data(BeaconPlan plan, _Calls calls, {DateTime? now}) =>
    BeaconHudPlanData(
      plan: plan,
      viewerId: 'ME',
      now: now ?? _now,
      people: PlanPeople(admitted: const [_olga, _me], names: plan.names),
      onToggleDone: calls.done.add,
      onAck: () => calls.acks++,
      onCantMake: (s) => calls.cantMake.add(s.id),
      onOpenStep: (_) {},
      onOpenPlan: () => calls.openPlan++,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

Finder _inRow(Key row, Finder f) =>
    find.descendant(of: find.byKey(row), matching: f);

void main() {
  testWidgets('YOU shows the current step with Done; NEXT the next step', (
    tester,
  ) async {
    final calls = _Calls();
    await _pump(
      tester,
      BeaconHudPinnedBlock(
        state: _state(),
        now: _now,
        plan: _data(_plan(), calls),
      ),
    );

    expect(
      _inRow(BeaconHudPlanKeys.you, find.textContaining('Bring boards')),
      findsOneWidget,
    );
    // Description of the current step as a muted second line.
    expect(
      _inRow(BeaconHudPlanKeys.you, find.text('to the school gate')),
      findsOneWidget,
    );
    expect(
      _inRow(BeaconHudPlanKeys.next, find.textContaining('Build frame')),
      findsOneWidget,
    );
    expect(
      _inRow(BeaconHudPlanKeys.next, find.textContaining('in ')),
      findsOneWidget,
    );
    expect(
      _inRow(BeaconHudPlanKeys.next, find.byType(FilledButton)),
      findsNothing,
    );
    expect(find.byKey(BeaconHudPlanKeys.byPlan), findsNothing);

    await tester.tap(find.byKey(BeaconHudPlanKeys.done));
    expect(calls.done, ['PS000000000002']);
    await tester.tap(find.byKey(BeaconHudPlanKeys.cantMake));
    expect(calls.cantMake, ['PS000000000002']);

    // Counter: 1 of 4 done; tap opens the Plan tab.
    expect(find.text('plan 1/4'), findsOneWidget);
    await tester.tap(find.byKey(BeaconHudPlanKeys.counter));
    expect(calls.openPlan, 1);
    expect(find.byKey(BeaconHudPlanKeys.overdue), findsNothing);
  });

  testWidgets('overdue: danger «+N» and the due time, ⏰ counter', (
    tester,
  ) async {
    final calls = _Calls();
    final late = DateTime.utc(2026, 10, 12, 10, 45);
    await _pump(
      tester,
      BeaconHudPinnedBlock(
        state: _state(),
        now: late,
        plan: _data(_plan(), calls, now: late),
      ),
    );
    expect(
      _inRow(BeaconHudPlanKeys.you, find.textContaining('⏰ +15m')),
      findsOneWidget,
    );
    expect(
      _inRow(BeaconHudPlanKeys.you, find.textContaining('was due by')),
      findsOneWidget,
    );
    expect(find.byKey(BeaconHudPlanKeys.overdue), findsOneWidget);
    expect(find.text('⏰ 1'), findsOneWidget);
  });

  testWidgets('NOW: the plan step that started last, «by plan · step n/N»', (
    tester,
  ) async {
    await _pump(
      tester,
      BeaconHudPinnedBlock(
        state: _state(
          cue: BeaconRoomState(
            beaconId: 'B1',
            updatedAt: DateTime.utc(2026, 10, 12, 9),
            currentLine: 'Waiting for boards',
            updatedBy: 'U2',
          ),
        ),
        now: _now,
        plan: _data(_plan(), _Calls()),
      ),
    );
    final now = find.byKey(beaconHudPlanNowKey);
    expect(now, findsOneWidget);
    expect(
      find.descendant(of: now, matching: find.textContaining('NOW')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: now,
        matching: find.textContaining('Ivan: Bring boards'),
      ),
      findsOneWidget,
    );
    expect(find.text('by plan · step 2/4'), findsOneWidget);
    expect(find.textContaining('Waiting for boards'), findsNothing);
  });

  testWidgets('NOW: a manual line written after the step started wins', (
    tester,
  ) async {
    await _pump(
      tester,
      BeaconHudPinnedBlock(
        state: _state(
          cue: BeaconRoomState(
            beaconId: 'B1',
            updatedAt: DateTime.utc(2026, 10, 12, 10, 7),
            currentLine: 'Stuck in traffic',
            updatedBy: 'U2',
          ),
        ),
        now: _now,
        plan: _data(_plan(), _Calls()),
      ),
    );
    expect(find.byKey(beaconHudPlanNowKey), findsNothing);
    expect(find.textContaining('Stuck in traffic'), findsOneWidget);
    // With a plan the row is labelled NOW, not NEXT STEP.
    expect(find.textContaining('NOW'), findsOneWidget);
    expect(find.text('by plan · step 2/4'), findsNothing);
  });

  testWidgets('pending change takes YOU with Got it; current goes BY PLAN', (
    tester,
  ) async {
    final calls = _Calls();
    final plan = _plan(
      viewerPending: {
        'fromSeq': 3,
        'headSeq': 4,
        'actorIds': ['U2'],
        'changes': [
          {
            'seq': 4,
            'op': 'retimed',
            'stepId': 'PS000000000003',
            'title': 'Build frame',
            'fromStartAt': '2026-10-12T11:00:00.000Z',
            'toStartAt': '2026-10-12T11:30:00.000Z',
            'fromEndAt': null,
            'toEndAt': null,
          },
        ],
      },
    );
    await _pump(
      tester,
      BeaconHudPinnedBlock(
        state: _state(),
        now: _now,
        plan: _data(plan, calls),
      ),
    );
    expect(
      _inRow(BeaconHudPlanKeys.you, find.textContaining('Olga · ')),
      findsOneWidget,
    );
    expect(
      _inRow(BeaconHudPlanKeys.you, find.textContaining('«Build frame»')),
      findsOneWidget,
    );
    expect(
      _inRow(BeaconHudPlanKeys.byPlan, find.textContaining('Bring boards')),
      findsOneWidget,
    );
    expect(
      _inRow(BeaconHudPlanKeys.byPlan, find.textContaining('BY PLAN')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(BeaconHudPlanKeys.ack));
    expect(calls.acks, 1);
  });

  testWidgets('a system situation keeps YOU; the step moves to BY PLAN', (
    tester,
  ) async {
    await _pump(
      tester,
      BeaconHudPinnedBlock(
        state: _state(
          author: _me,
          offers: [
            TimelineHelpOffer(
              user: const Profile(id: 'H1', displayName: 'Helper'),
              message: 'help',
              createdAt: DateTime.utc(2026, 10, 12),
              updatedAt: DateTime.utc(2026, 10, 12),
            ),
          ],
        ),
        now: _now,
        plan: _data(_plan(), _Calls()),
        onReviewAuthorOffers: () {},
      ),
    );
    expect(find.byKey(BeaconHudPlanKeys.you), findsNothing);
    expect(
      _inRow(BeaconHudPlanKeys.byPlan, find.textContaining('Bring boards')),
      findsOneWidget,
    );
    expect(
      _inRow(BeaconHudPlanKeys.byPlan, find.byKey(BeaconHudPlanKeys.done)),
      findsOneWidget,
    );
    expect(
      _inRow(BeaconHudPlanKeys.next, find.textContaining('Build frame')),
      findsOneWidget,
    );
  });

  testWidgets('free until the next step when nothing runs', (tester) async {
    final early = DateTime.utc(2026, 10, 12, 10, 40);
    final plan = _plan().withStepDone(
      'PS000000000002',
      done: true,
      actorId: 'ME',
      now: early,
    );
    await _pump(
      tester,
      BeaconHudPinnedBlock(
        state: _state(),
        now: early,
        plan: _data(plan, _Calls(), now: early),
      ),
    );
    expect(
      _inRow(BeaconHudPlanKeys.you, find.textContaining('Free until')),
      findsOneWidget,
    );
    expect(
      _inRow(BeaconHudPlanKeys.next, find.textContaining('Build frame')),
      findsOneWidget,
    );
    expect(find.text('plan 2/4'), findsOneWidget);
  });

  testWidgets('a finished Request hides plan rows', (tester) async {
    await _pump(
      tester,
      BeaconHudPinnedBlock(
        state: _state(status: BeaconStatus.cancelled),
        now: _now,
        plan: _data(_plan(), _Calls()),
      ),
    );
    expect(find.byKey(BeaconHudPlanKeys.you), findsNothing);
    expect(find.byKey(BeaconHudPlanKeys.next), findsNothing);
  });

  testWidgets('without a plan the HUD is unchanged (NEXT STEP label)', (
    tester,
  ) async {
    await _pump(
      tester,
      BeaconHudPinnedBlock(
        state: _state(
          cue: BeaconRoomState(
            beaconId: 'B1',
            updatedAt: DateTime.utc(2026, 10, 12, 9),
            currentLine: 'Frame on Saturday',
            updatedBy: 'U2',
          ),
        ),
        now: _now,
      ),
    );
    expect(find.textContaining('NEXT STEP'), findsOneWidget);
    expect(find.byKey(BeaconHudPlanKeys.counter), findsNothing);
  });

  test('plan JSON fixture is valid', () {
    expect(jsonDecode(planJson()), isA<Map<String, Object?>>());
  });
}
