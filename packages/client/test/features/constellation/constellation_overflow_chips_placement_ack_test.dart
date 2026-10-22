@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show debugOnRebuildDirtyWidget;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _authorCount = 30;
const _requestsPerAuthor = 6;

final _person = ConstellationAnchorTarget.person('p0');

const _pinnedAt = ConstellationAnchorPosition(
  xUnits: 0.2,
  yUnits: 0.3,
  coordinateSpaceVersion: 1,
);

ConstellationAnchor _anchor(
  ConstellationAnchorPosition position,
  int revision,
) => ConstellationAnchor(
  target: _person,
  position: position,
  revision: ConstellationAnchorRevision(BigInt.from(revision)),
  placedAt: DateTime.utc(2026, 9, 9),
);

/// Many authors that each have more requests than the label budget draws, so
/// the overlay mounts a "more requests" chip per author.
ConstellationField _crowdedField() {
  final peers = [
    for (var i = 0; i < _authorCount; i++)
      ConstellationPerson(id: 'p$i', displayName: 'Person $i'),
  ];
  final requests = [
    for (var i = 0; i < _authorCount; i++)
      for (var j = 0; j < _requestsPerAuthor; j++)
        ConstellationRequest(
          id: 'req-p$i-$j',
          authorId: 'p$i',
          title: 'Request $j of person $i',
          status: 0,
        ),
  ];
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 9, 9, 12),
    context: '',
    peers: peers,
    edges: [
      for (final peer in peers)
        ConstellationTrustEdgeEntity(src: 'ego', dst: peer.id, tier: 1),
    ],
    requests: requests,
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.one),
      anchors: [_anchor(_pinnedAt, 1)],
      pinnedPeers: [peers.first],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

final class _FieldRepository implements ConstellationRepositoryPort {
  _FieldRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

/// Holds every apply until the test acknowledges it, like a slow server.
final class _AnchorRepository implements ConstellationWriteFake {
  @override
  Future<ConstellationAnchorResetResult> reset({required String clientOpId}) =>
      throw UnimplementedError('reset is not used by this test');

  _AnchorRepository(this._confirmedBase);

  final ConstellationAnchorProjection _confirmedBase;
  final calls =
      <
        ({
          List<ConstellationAnchorApplyOp> ops,
          Completer<ConstellationAnchorApplyResult> reply,
        })
      >[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    final reply = Completer<ConstellationAnchorApplyResult>();
    calls.add((ops: List.of(ops), reply: reply));
    return reply.future;
  }

  /// Acknowledges call [index] with the projection the server would hold
  /// afterwards: the same field content, revision 2, the ops applied.
  void ack(int index) {
    final call = calls[index];
    final revision = ConstellationAnchorRevision(BigInt.two);
    call.reply.complete(
      ConstellationAnchorApplyResult(
        beforeRevision: _confirmedBase.revision,
        afterRevision: revision,
        results: [
          for (final op in call.ops)
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: revision,
              target: op.target,
              anchor: _anchor(op.position!, 2),
            ),
        ],
      ),
    );
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

Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Counts builds of every overflow chip's cubit builder from now on. A chip
/// that is mounted and not replaced by its parent only builds again because
/// its `buildWhen` let a state change through.
({int Function() builds, Map<String, int> Function() byAuthor})
_countChipBuilderBuilds() {
  final byAuthor = <String, int>{};
  final previous = debugOnRebuildDirtyWidget;
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    if (element.widget is BlocBuilder<ConstellationCubit, ConstellationState>) {
      String? authorId;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is ConstellationOverflowGroup) authorId = widget.authorId;
        return authorId == null;
      });
      if (authorId != null) {
        byAuthor[authorId!] = (byAuthor[authorId] ?? 0) + 1;
      }
    }
  };
  return (
    builds: () => byAuthor.values.fold(0, (a, b) => a + b),
    byAuthor: () => Map.of(byAuthor),
  );
}

Future<void> _testRetention(WidgetTester tester, {required bool drop}) async {
  final field = _crowdedField();
  final server = _AnchorRepository(field.resolvedAnchorProjection);
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    _FieldRepository(field),
    accountId: 'ego',
    realtime: sync.case_,
  ).store;
  final placement = ConstellationPlacementCase(
    server,
    store,
    FakeClockPort(),
    FakeWakeUpPort(),
    realtime: sync.case_,
    env: const Env.fromEnvironment(),
    logger: Logger('OverlayElementRetentionTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    placementCase: placement,
    viewer: kRefEgo,
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  // A selected person's label is always placed, even in this crowded field.
  // Ensure grabbing really inserts a plate before the chip slots.
  cubit.selectPerson('p0');
  final holder = ConstellationPresentationFrameHolder();
  await pumpConstellationBody(
    tester,
    cubit,
    size: const Size(1600, 1000),
    presentationFrameHolder: holder,
  );
  await tester.pumpAndSettle();

  expect(holder.frame!.labels, contains('fp:p0'));

  final chips = find.byType(ConstellationOverflowGroup);
  expect(chips, findsAtLeastNWidgets(8));
  Set<Element> chipElements() => {
    for (final chip in chips.evaluate()) ..._subtree(chip),
  };
  final original = chipElements();
  final renderObjects = {
    for (final e in original.whereType<RenderObjectElement>()) e.renderObject,
  };
  final renderCounts = <Type, int>{};
  for (final object in renderObjects) {
    renderCounts.update(object.runtimeType, (n) => n + 1, ifAbsent: () => 1);
  }
  final overlay = tester.element(find.byType(ConstellationViewportOverlay));
  final layersBefore = _layerCounts(overlay);
  final boundariesBefore = _boundaryCount(overlay);
  expect(boundariesBefore, greaterThan(0));
  expect(layersBefore, isNotEmpty);
  final authorsBefore = holder.frame!.chips.keys.toSet();
  final inflatedElements = <Element>{};
  final paints = <Type, int>{};
  final oldBuild = debugOnRebuildDirtyWidget;
  final oldPaint = debugOnProfilePaint;
  addTearDown(() {
    debugOnRebuildDirtyWidget = oldBuild;
    debugOnProfilePaint = oldPaint;
  });
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    oldBuild?.call(element, builtOnce);
    // This SDK only updates builtOnce when debugPrintRebuildDirtyWidgets is
    // enabled. Element identity distinguishes a mount from a retained rebuild.
    if (original.contains(element)) return;
    var isChip = element.widget is ConstellationOverflowGroup;
    element.visitAncestorElements((ancestor) {
      isChip = isChip || ancestor.widget is ConstellationOverflowGroup;
      return !isChip;
    });
    if (isChip) inflatedElements.add(element);
  };
  debugOnProfilePaint = (object) {
    oldPaint?.call(object);
    if (renderObjects.contains(object)) {
      paints.update(object.runtimeType, (n) => n + 1, ifAbsent: () => 1);
    }
  };

  Future<void> checkFrame({bool expectPaint = false}) async {
    await tester.pump();
    expect(
      inflatedElements.length,
      0,
      reason: 'no chip subtree may be inflated afresh',
    );
    // Chip descendants have no GlobalKeys: removed elements cannot be
    // reactivated under another slot. Count removals as well as mounts.
    final deactivations = original.where((e) => !e.debugIsActive).length;
    expect(deactivations, 0);
    expect(chipElements(), original, reason: 'retain Material/InkWell/Bloc');
    expect(holder.frame!.chips.keys.toSet(), authorsBefore);
    expect(_boundaryCount(overlay), boundariesBefore);
    expect(_layerCounts(overlay), layersBefore);
    if (expectPaint) {
      expect(
        paints,
        isNotEmpty,
        reason: 'paint instrumentation must observe work',
      );
    }
    // Each retained render object may paint at most once in this frame.
    // Pin the budget per render type, with no wall-clock threshold.
    for (final entry in paints.entries) {
      expect(entry.value, lessThanOrEqualTo(renderCounts[entry.key]!));
    }
    paints.clear();
  }

  cubit.beginDragExisting(target: _person);
  await checkFrame(expectPaint: true);
  final dragged = find.byKey(const ValueKey('constellation.dragged.fp:p0'));
  expect(dragged, findsOneWidget, reason: 'grab must add a dragged plate');
  final draggedElement = tester.element(dragged);
  final start = cubit.graphController.getPositionForId('fp:p0');
  final labelBefore = holder.frame!.labels['fp:p0']!;
  cubit.updateDragPresentation(
    nodeId: 'fp:p0',
    sceneCentre: start + const Offset(20, 12),
  );
  await checkFrame();
  expect(tester.element(dragged), same(draggedElement));
  final moved = cubit.graphController.getPositionForId('fp:p0') - start;
  expect(moved.distance, greaterThan(0));
  expect(
    (holder.frame!.labels['fp:p0']!.center -
            labelBefore.center -
            moved * cubit.graphController.cameraScale)
        .distance,
    lessThan(1),
    reason: 'label must follow the node',
  );
  if (drop) {
    await cubit.onExistingNodeDrop(
      target: _person,
      sceneCentre: cubit.graphController.getPositionForId('fp:p0'),
    );
    await checkFrame();
    expect(server.calls, hasLength(1));
    server.ack(0);
    await checkFrame();
  } else {
    cubit.cancelPlacement();
    await checkFrame();
  }
  await tester.pumpAndSettle();
  paints.clear();
  await checkFrame();
  expect(dragged, findsNothing, reason: 'release must remove dragged plate');
  // Rendering debug hooks must be unset before the test body ends: the
  // binding checks them before tear-downs run.
  debugOnRebuildDirtyWidget = oldBuild;
  debugOnProfilePaint = oldPaint;
}

Set<Element> _subtree(Element root) {
  final elements = <Element>{};
  void visit(Element element) {
    elements.add(element);
    element.visitChildren(visit);
  }

  visit(root);
  return elements;
}

int _boundaryCount(Element root) => _subtree(root)
    .whereType<RenderObjectElement>()
    .where((e) => e.renderObject.isRepaintBoundary)
    .length;

Map<Type, int> _layerCounts(Element root) {
  final layers = <Layer>{};
  void visit(Layer layer) {
    if (!layers.add(layer)) return;
    if (layer is ContainerLayer) {
      var child = layer.firstChild;
      while (child != null) {
        visit(child);
        child = child.nextSibling;
      }
    }
  }

  for (final e in _subtree(root).whereType<RenderObjectElement>()) {
    final layer = e.renderObject.debugLayer;
    if (layer != null) visit(layer);
  }
  final counts = <Type, int>{};
  for (final layer in layers) {
    counts.update(layer.runtimeType, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

void main() {
  for (final drop in [false, true]) {
    testWidgets(
      'chip elements survive grab, move and ${drop ? 'drop' : 'cancel'}',
      (tester) => _testRetention(tester, drop: drop),
    );
  }
  group('Overflow chips on a server acknowledgement of a placement', () {
    testWidgets('no mounted chip rebuilds when a drop is acknowledged '
        'unchanged', (tester) async {
      final field = _crowdedField();
      final server = _AnchorRepository(field.resolvedAnchorProjection);
      final sync = buildTestRealtimeSync();
      final store = ConstellationStoreFixture(
        _FieldRepository(field),
        accountId: 'ego',
        realtime: sync.case_,
      ).store;
      final placement = ConstellationPlacementCase(
        server,
        store,
        FakeClockPort(),
        FakeWakeUpPort(),
        realtime: sync.case_,
        env: const Env.fromEnvironment(),
        logger: Logger('OverflowChipsPlacementAckTest'),
      );
      final cubit = ConstellationCubit(
        case_: store,
        placementCase: placement,
        viewer: kRefEgo,
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1600, 1000),
      );
      await tester.pumpAndSettle();

      final chipCount = find
          .byType(ConstellationOverflowGroup)
          .evaluate()
          .length;
      expect(
        chipCount,
        greaterThanOrEqualTo(8),
        reason:
            'fixture must mount many overflow chips to make the ack '
            'fan-out measurable',
      );

      const dropCentre = Offset(240, 180);
      cubit
        ..beginDragExisting(target: _person)
        ..updateDragPresentation(nodeId: 'fp:p0', sceneCentre: dropCentre);
      await cubit.onExistingNodeDrop(target: _person, sceneCentre: dropCentre);
      await _settleFrames(tester);
      expect(server.calls, hasLength(1));
      final sent = server.calls.single.ops.single.position!;
      expect(sent, isNot(_pinnedAt));

      // Positive control: the drop itself (before the ack) is allowed to
      // rebuild chips; only the ack is pinned below.
      final reconciliations = cubit.layoutReconciliationCount;
      final layoutRuns = cubit.graphController.relayoutInvocationCount;
      final counter = _countChipBuilderBuilds();

      server.ack(0);
      await _settleFrames(tester);

      expect(
        cubit.state.confirmedProjection!.revision,
        ConstellationAnchorRevision(BigInt.two),
        reason: 'the acknowledgement must have been consumed',
      );
      expect(
        cubit.layoutReconciliationCount,
        reconciliations,
        reason: 'an unchanged ack must not recompose the scene',
      );
      expect(cubit.graphController.relayoutInvocationCount, layoutRuns);
      expect(
        find.byType(ConstellationOverflowGroup).evaluate().length,
        chipCount,
        reason: 'the ack must not change which chips are mounted',
      );
      expect(
        counter.byAuthor(),
        isEmpty,
        reason: 'no overflow chip builder may fire on an unchanged ack',
      );
      expect(counter.builds(), 0);
    });
  });
}
