// Dropping a dragged person node on a chip of the Field's tag row adds that
// own tag to the person (a manual edit) instead of pinning the node. The bar
// that confirms it offers Undo, which takes the tag away again. Dropping on
// empty space keeps pinning as before.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_row.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_tag_lens_body_harness.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

/// A server that records writes and never answers them.
final class _SilentAnchorRepository implements ConstellationWriteFake {
  final applyCalls = <List<ConstellationAnchorApplyOp>>[];

  @override
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  }) => throw UnimplementedError('snapshots are not used by this test');

  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) => throw UnimplementedError('restore is not used by this test');

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) => throw UnimplementedError('reset is not used by this test');

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    applyCalls.add(List.of(ops));
    return Completer<ConstellationAnchorApplyResult>().future;
  }

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) => throw StateError('Placement must use batched apply');

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) => throw StateError('Unpin must use batched apply');
}

typedef _Mounted = ({TagLensBodyHarness body, _SilentAnchorRepository server});

Future<_Mounted> _mount(WidgetTester tester) async {
  final server = _SilentAnchorRepository();
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  final body = await mountTagLensBody(
    tester,
    placementFor: (store) => ConstellationPlacementCase(
      server,
      store,
      FakeClockPort(),
      FakeWakeUpPort(),
      realtime: sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationTagChipDropTest'),
    ),
  );
  return (body: body, server: server);
}

Finder _node(String personId) =>
    find.byKey(TestIds.key(TestIds.graphNode(personId)));

/// The chip of tag [name] in the Field's tag row.
Finder _chip(String name) => find.descendant(
  of: find.byType(ConstellationTagRow),
  matching: find.ancestor(
    of: find.text(name),
    matching: find.byType(PersonTagChip),
  ),
);

/// Drags person [personId] to [target] (global) and lets go.
Future<void> _dragTo(
  WidgetTester tester,
  String personId,
  Offset target,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(_node(personId)),
    kind: PointerDeviceKind.mouse,
  );
  final delta = target - tester.getCenter(_node(personId));
  const steps = 12;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(delta / steps.toDouble());
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _dropOnChip(
  WidgetTester tester,
  String personId,
  String tagName,
) async {
  expect(_chip(tagName), findsOneWidget, reason: 'the chip is on the Field');
  await _dragTo(tester, personId, tester.getCenter(_chip(tagName)));
}

void main() {
  group('dropping a person node on a tag chip', () {
    testWidgets('adds the tag to the person as a manual edit', (tester) async {
      final m = await _mount(tester);

      await _dropOnChip(tester, 'dan', 'Workshop');

      expect(m.body.rig.repository.appliedOps, [
        [
          const PersonTagMemberOp(
            tagId: 'T-workshop',
            personId: 'dan',
            add: true,
            // Spelled out: a drop is a manual edit.
            // ignore: avoid_redundant_argument_values
            source: 0,
          ),
        ],
      ]);
      expect(m.body.rig.peopleTags.peopleInTag('T-workshop'), contains('dan'));
    });

    testWidgets('does not pin the node', (tester) async {
      final m = await _mount(tester);

      await _dropOnChip(tester, 'dan', 'Workshop');

      expect(m.server.applyCalls, isEmpty, reason: 'nothing is written');
      expect(
        m.body.field.isAnchored(ConstellationAnchorTarget.person('dan')),
        isFalse,
      );
      expect(
        m.body.field.state.placementPhase,
        ConstellationPlacementPhase.idle,
      );
    });

    testWidgets('confirms with the tag name and a shared Undo bar', (
      tester,
    ) async {
      await _mount(tester);

      await _dropOnChip(tester, 'dan', 'Workshop');

      final bar = find.byType(SnackBar);
      expect(bar, findsOneWidget);
      final snack = tester.widget<SnackBar>(bar);
      final shown = [
        for (final text in tester.widgetList<Text>(
          find.descendant(of: bar, matching: find.byType(Text)),
        ))
          text.data ?? '',
      ];
      expect(
        shown.where((t) => t.contains('Workshop')),
        isNotEmpty,
        reason: 'the bar names the tag the person was added to',
      );
      // The shared Undo bar: its label, its length, and no pinning.
      expect(snack.action?.label, 'Undo');
      expect(snack.duration, kUndoSnackBarDuration);
      expect(snack.persist, isFalse);
    });

    testWidgets('Undo takes the tag away again', (tester) async {
      final m = await _mount(tester);
      await _dropOnChip(tester, 'dan', 'Workshop');
      expect(
        m.body.rig.peopleTags.peopleInTag('T-workshop'),
        contains('dan'),
        reason: 'positive control',
      );

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(m.body.rig.repository.appliedOps, [
        [
          const PersonTagMemberOp(
            tagId: 'T-workshop',
            personId: 'dan',
            add: true,
          ),
        ],
        [
          const PersonTagMemberOp(
            tagId: 'T-workshop',
            personId: 'dan',
            add: false,
          ),
        ],
      ]);
      expect(
        m.body.rig.peopleTags.peopleInTag('T-workshop'),
        isNot(contains('dan')),
      );
      expect(m.server.applyCalls, isEmpty, reason: 'Undo does not pin either');
    });

    testWidgets('the person lands in the tag it was dropped on, not another', (
      tester,
    ) async {
      final m = await _mount(tester);

      await _dropOnChip(tester, 'dan', 'Garden');

      final tags = {
        for (final op in m.body.rig.repository.appliedOps.expand((o) => o))
          op.tagId,
      };
      expect(tags, {'T-garden'});
    });
  });

  group('dropping a person node away from the chips', () {
    testWidgets('still pins it and adds no tag', (tester) async {
      final m = await _mount(tester);
      expect(_chip('Workshop'), findsOneWidget, reason: 'positive control');
      final start = tester.getCenter(_node('dan'));
      final away = start + const Offset(60, 60);
      expect(
        tester.getRect(find.byType(ConstellationTagRow)).contains(away),
        isFalse,
        reason: 'the drop is away from the chips',
      );

      await _dragTo(tester, 'dan', away);

      expect(m.body.rig.repository.appliedOps, isEmpty);
      final writes = [for (final call in m.server.applyCalls) ...call];
      expect(
        [
          for (final op in writes)
            if (op.kind == ConstellationAnchorOpKind.upsert) op.target,
        ],
        [ConstellationAnchorTarget.person('dan')],
        reason: 'the drop pins the dropped person and nothing else',
      );
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
