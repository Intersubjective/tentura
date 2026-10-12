import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_viewer_slice.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_plan_rows.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_plan_step_rows.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

/// Request plan («либретто», #220 §5.8): plan subcards in a My Work card.
final _now = DateTime.utc(2030, 1, 10, 10);

String _iso(DateTime t) => t.toUtc().toIso8601String();

PlanViewerSlice _slice({
  bool current = true,
  bool overdue = false,
  bool next = true,
  bool pending = false,
  bool finished = false,
}) {
  final json = <String, Object?>{
    'current': finished || !current
        ? null
        : {
            'stepId': 'PSa',
            'title': 'Bring boards',
            'description': 'Gate on Elm\nsecond line',
            'startAt': _iso(_now.subtract(const Duration(minutes: 40))),
            'endAt': _iso(
              overdue
                  ? _now.subtract(const Duration(minutes: 20))
                  : _now.add(const Duration(minutes: 20)),
            ),
          },
    'alsoActive': const <Object?>[],
    'next': finished || !next
        ? null
        : {
            'stepId': 'PSb',
            'title': 'Build the frame',
            'startAt': _iso(_now.add(const Duration(days: 2))),
          },
    'pendingAck': finished || !pending
        ? null
        : {
            'fromSeq': 3,
            'headSeq': 4,
            'changeCount': 1,
            'actorIds': ['Uolga'],
            'actorNames': {'Uolga': 'Olga'},
            'stepIds': ['PSa'],
            'lastAt': _iso(_now.subtract(const Duration(minutes: 2))),
            'sample': {
              'op': 'retitled',
              'stepId': 'PSa',
              'title': 'Bring boards',
              'fromTitle': 'Bring wood',
              'from': 'Bring wood',
              'to': 'Bring boards',
            },
          },
  };
  return PlanViewerSlice.tryDecode(jsonEncode(json))!;
}

MyWorkCardViewModel _vm(PlanViewerSlice slice) => MyWorkCardViewModel(
  beaconId: 'beacon-1',
  role: MyWorkCardRole.helpOffered,
  kind: MyWorkCardKind.helpOfferedActive,
  beacon: Beacon.empty.copyWith(id: 'beacon-1', title: 'Garden'),
  planSlice: slice,
);

Future<({List<String> done, List<int> acks, List<String> opened})> _pumpRows(
  WidgetTester tester,
  PlanViewerSlice slice,
) async {
  final done = <String>[];
  final acks = <int>[];
  final opened = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: MyWorkPlanStepRows(
            slice: slice,
            now: _now,
            viewerId: 'Uviewer',
            nameOf: (id) => id ?? '',
            onDone: done.add,
            onAck: acks.add,
            onOpenStep: opened.add,
          ),
        ),
      ),
    ),
  );
  return (done: done, acks: acks, opened: opened);
}

void main() {
  group('PlanViewerSlice', () {
    test('decodes the §4.9 shape and rebuilds the viewer schedule', () {
      final slice = _slice(pending: true);
      expect(slice.current!.stepId, 'PSa');
      expect(slice.current!.description, startsWith('Gate on Elm'));
      expect(slice.next!.stepId, 'PSb');
      expect(slice.pendingAck!.headSeq, 4);
      expect(slice.pendingAck!.actorNames, {'Uolga': 'Olga'});
      expect(slice.pendingAck!.sample!.fromTitle, 'Bring wood');
      final input = slice.youInput(_now);
      expect(input.schedule.current!.id, 'PSa');
      expect(input.pendingAck, isTrue);
      expect(input.pendingStepIds, {'PSa'});
    });

    test('malformed or empty wire values decode to null', () {
      expect(PlanViewerSlice.tryDecode(null), isNull);
      expect(PlanViewerSlice.tryDecode(''), isNull);
      expect(PlanViewerSlice.tryDecode('{oops'), isNull);
      expect(PlanViewerSlice.tryDecode('[1]'), isNull);
    });

    test('a finished Request slice has no viewer rows', () {
      final slice = _slice(finished: true);
      expect(slice.hasViewerRows, isFalse);
      expect(deriveMyWorkPlanRows(slice, _now), isEmpty);
    });

    test('a local «Готово» drops the step', () {
      final after = _slice().withoutStep('PSa');
      expect(after.current, isNull);
      expect(after.next!.stepId, 'PSb');
    });
  });

  group('deriveMyWorkPlanRows (the HUD ladder)', () {
    test('current step, then the muted next one', () {
      final rows = deriveMyWorkPlanRows(_slice(), _now);
      expect(rows.map((r) => r.kind), [
        MyWorkPlanRowKind.current,
        MyWorkPlanRowKind.next,
      ]);
      expect(rows.first.overdueBy, isNull);
    });

    test('an overdue step carries how late it is', () {
      final rows = deriveMyWorkPlanRows(_slice(overdue: true), _now);
      expect(rows.first.overdueBy, const Duration(minutes: 20));
    });

    test('a pending change comes first and touches the current step', () {
      final rows = deriveMyWorkPlanRows(_slice(pending: true), _now);
      expect(rows.first.kind, MyWorkPlanRowKind.pending);
      expect(rows.first.canTickStep?.id, 'PSa');
      expect(rows.length, lessThanOrEqualTo(3));
    });

    test('only future steps: one muted row, no actions', () {
      final rows = deriveMyWorkPlanRows(_slice(current: false), _now);
      expect(rows.map((r) => r.kind), [MyWorkPlanRowKind.next]);
    });
  });

  group('MyWorkPlanStepRows', () {
    testWidgets('current step offers «Done» and «Can’t make it»; next is '
        'muted with no buttons', (tester) async {
      final calls = await _pumpRows(tester, _slice());
      expect(find.byKey(MyWorkPlanKeys.current), findsOneWidget);
      expect(find.byKey(MyWorkPlanKeys.next), findsOneWidget);
      expect(find.textContaining('Bring boards'), findsOneWidget);
      expect(find.text('Gate on Elm'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(MyWorkPlanKeys.next),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(MyWorkPlanKeys.done));
      expect(calls.done, ['PSa']);
      await tester.tap(find.byKey(MyWorkPlanKeys.cantMake));
      expect(calls.opened, ['PSa']);
    });

    testWidgets('overdue step reads in the danger tone', (tester) async {
      await _pumpRows(tester, _slice(overdue: true));
      expect(find.textContaining('⏰'), findsOneWidget);
    });

    testWidgets('pending change: «Got it» confirms up to the head', (
      tester,
    ) async {
      final calls = await _pumpRows(tester, _slice(pending: true));
      expect(find.byKey(MyWorkPlanKeys.pending), findsOneWidget);
      expect(find.textContaining('Olga'), findsOneWidget);
      await tester.tap(find.byKey(MyWorkPlanKeys.ack));
      expect(calls.acks, [4]);
    });

    testWidgets('finished Request: nothing rendered', (tester) async {
      await _pumpRows(tester, _slice(finished: true));
      expect(find.byKey(MyWorkPlanKeys.rows), findsNothing);
    });
  });

  group('MyWorkObligationBlock with plan rows', () {
    testWidgets('plan rows render first and the block shows with no other '
        'receipts', (tester) async {
      final cubit = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(),
      );
      addTearDown(cubit.close);
      final slice = _slice();
      final vm = _vm(slice);
      expect(
        myWorkObligationBlockVisible(
          vm: vm,
          obligations: const [],
          hasPlanRows: true,
        ),
        isTrue,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: BlocProvider<MyWorkCubit>.value(
                value: cubit,
                child: MyWorkObligationBlock(
                  vm: vm,
                  obligations: const [],
                  planRows: MyWorkPlanStepRows(
                    slice: slice,
                    now: _now,
                    viewerId: 'Uviewer',
                    nameOf: (id) => id ?? '',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(MyWorkPlanKeys.rows), findsOneWidget);
    });

    test('plan step receipts are recognised as plan rows', () {
      AttentionReceipt receipt(String key) => AttentionReceipt(
        id: key,
        category: 'asksOfMe',
        kind: key,
        priority: 'normal',
        title: 'Plan',
        body: '',
        actionUrl: '/#/',
        createdAt: DateTime.utc(2030),
        collapsedCount: 1,
        presentationKey: key,
        presentationPayloadJson: '{}',
        surface: AttentionSurface.myWork,
        beaconId: 'beacon-1',
        requiresAction: true,
      );
      expect(myWorkReceiptShownAsPlanRow(receipt('plan_step_due')), isTrue);
      expect(
        myWorkReceiptShownAsPlanRow(receipt('plan_change_pending')),
        isTrue,
      );
      expect(myWorkReceiptShownAsPlanRow(receipt('plan_step_late')), isFalse);
      expect(
        myWorkReceiptShownAsPlanRow(receipt('help_offer_submitted')),
        isFalse,
      );
    });
  });
}
