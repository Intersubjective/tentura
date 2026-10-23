@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_plan_rows.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

import '../beacon_plan/beacon_plan_test_support.dart';

/// #532 — the HUD's pending plan change («Olga · 2m ago: …») read its age off
/// the plan's boundary clock, which moves only at step edges, so it froze.
/// It follows the shared ticking clock.

/// The plan clock: step 2 (Ivan = ME) runs; the plan stays put.
final _planNow = DateTime.utc(2026, 10, 12, 10, 20);

/// `planJson` says the plan was last edited at 07:10 UTC.
final _editedAt = DateTime.utc(2026, 10, 12, 7, 10);

const _me = Profile(id: 'ME', displayName: 'Ivan');
const _olga = Profile(id: 'U2', displayName: 'Olga');

void main() {
  late DateTime clock;

  setUp(() {
    clock = _editedAt.add(const Duration(seconds: 30));
    RelativeTimestampTicker.debugClock = () => clock;
  });
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  testWidgets(
    'a pending plan change age keeps counting while the HUD is open',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final plan = BeaconPlan.decode(
        planJson(
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
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BeaconHudPinnedBlock(
                state: BeaconViewState(
                  beacon: Beacon.empty.copyWith(
                    id: 'B1',
                    updatedAt: DateTime.utc(2026),
                    author: _olga,
                    status: BeaconStatus.open,
                  ),
                  myProfile: _me,
                  admittedHelperRoster: const [_me],
                  admittedHelpersLoaded: true,
                ),
                now: _planNow,
                plan: BeaconHudPlanData(
                  plan: plan,
                  viewerId: 'ME',
                  now: _planNow,
                  people: PlanPeople(
                    admitted: const [_olga, _me],
                    names: plan.names,
                  ),
                  onToggleDone: (_) {},
                  onAck: () {},
                  onCantMake: (_) {},
                  onOpenStep: (_) {},
                  onOpenPlan: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      Finder inYou(String text) => find.descendant(
        of: find.byKey(BeaconHudPlanKeys.you),
        matching: find.textContaining(text),
      );
      expect(inYou('Olga · Just now'), findsOneWidget);

      clock = clock.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      expect(inYou('Olga · Just now'), findsNothing);
      expect(inYou('Olga · 2m ago'), findsOneWidget);
    },
  );
}
