import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

final _loadedAt = DateTime.utc(2026, 10, 3, 12);

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

const _pinnedPeer = 'p000';

String _padded(int i) => 'p${i.toString().padLeft(3, '0')}';

/// One peer more than the render cap, so exactly one peer is not drawn.
ConstellationField _fieldOverRenderCap() {
  final ids = [
    for (var i = 0; i <= kConstellationRenderPeerCap; i++) _padded(i),
  ];
  return ConstellationField(
    loadedAt: _loadedAt,
    context: '',
    peers: [for (final id in ids) ConstellationPerson(id: id)],
    edges: [
      for (final id in ids)
        ConstellationTrustEdgeEntity(src: 'ego', dst: id, tier: 1),
    ],
    requests: const [],
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.one),
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.person(_pinnedPeer),
          position: const ConstellationAnchorPosition(
            xUnits: 300,
            yUnits: 200,
            coordinateSpaceVersion: 1,
          ),
          revision: ConstellationAnchorRevision(BigInt.one),
          placedAt: DateTime.utc(2026, 10, 3),
        ),
      ],
      pinnedPeers: [const ConstellationPerson(id: _pinnedPeer)],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

Future<ConstellationCubit> _load() async {
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _StubRepository(_fieldOverRenderCap()),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationComposingPhaseTest'),
    ),
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

Set<String> _nodeIds(ConstellationCubit cubit) =>
    cubit.graphController.nodes.map((n) => n.graphNodeId).toSet();

Set<String> _draftEdgeIds(ConstellationCubit cubit) => cubit
    .graphController
    .edges
    .map((e) => e.semanticId)
    .where((id) => id.endsWith('#draftRecipient'))
    .toSet();

Set<String> _edgeIds(ConstellationCubit cubit) =>
    cubit.graphController.edges.map((e) => e.semanticId).toSet();

/// Displayed centre of every node currently in the graph.
Map<String, Offset?> _positions(ConstellationCubit cubit) => {
  for (final id in _nodeIds(cubit))
    id: cubit.graphController.getPositionOrNullForId(id),
};

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late ConstellationCubit cubit;
  late String hiddenPeer;
  late String shownPeer;
  late List<String> toggled;

  setUp(() async {
    cubit = await _load();
    final kept = cubit.state.keptPeerIds;
    shownPeer = kept.first;
    hiddenPeer = [
      for (var i = 0; i <= kConstellationRenderPeerCap; i++) _padded(i),
    ].firstWhere((id) => !kept.contains(id));
    toggled = [];
  });

  tearDown(() => cubit.close());

  Future<void> enter({Set<String> selected = const {}}) async {
    cubit.enterComposing(
      draftCentre: const Offset(40, 40),
      candidateIds: {shownPeer, hiddenPeer, 'not-a-field-peer'},
      selectedIds: selected,
      onToggle: toggled.add,
    );
    await _settle();
  }

  group('composing phase on the graph', () {
    test('entering adds the draft node and the widened candidate peers',
        () async {
      expect(_nodeIds(cubit), isNot(contains('fd:draft')));
      expect(cubit.state.keptPeerIds, isNot(contains(hiddenPeer)));
      final before = _positions(cubit);
      expect(before, contains('fp:$_pinnedPeer'));

      await enter();

      expect(cubit.state.placementPhase, ConstellationPlacementPhase.composing);
      expect(_nodeIds(cubit), contains('fd:draft'));
      expect(cubit.state.keptPeerIds, contains(hiddenPeer));
      expect(_nodeIds(cubit), contains('fp:$hiddenPeer'));
      expect(_nodeIds(cubit), isNot(contains('fp:not-a-field-peer')));
      expect(cubit.state.keptPeerIds, isNot(contains('not-a-field-peer')));
      expect(
        cubit.graphController.getPositionOrNullForId('fd:draft'),
        const Offset(40, 40),
      );
      final after = _positions(cubit);
      for (final entry in before.entries) {
        expect(
          after[entry.key],
          entry.value,
          reason: 'existing node ${entry.key} (pinned or not) must not move',
        );
      }
    });

    test('selected people get draft edges from the draft node', () async {
      await enter(selected: {shownPeer, hiddenPeer});

      expect(_draftEdgeIds(cubit), {
        'fd:draft->fp:$shownPeer#draftRecipient',
        'fd:draft->fp:$hiddenPeer#draftRecipient',
      });

    });

    test('tapping a person adds then removes its draft edge', () async {
      await enter();
      final node =
          cubit.graphController.nodePayloadForId('fp:$shownPeer')!;
      final edge = 'fd:draft->fp:$shownPeer#draftRecipient';
      final before = _positions(cubit);

      cubit.selectMapNode(node);
      await _settle();

      expect(_draftEdgeIds(cubit), {edge});
      expect(toggled, [shownPeer]);
      expect(_positions(cubit), before, reason: 'toggling must not relayout');

      cubit.selectMapNode(node);
      await _settle();

      expect(_draftEdgeIds(cubit), isEmpty);
      expect(toggled, [shownPeer, shownPeer]);
      expect(_positions(cubit), before, reason: 'toggling must not relayout');
    });

    test('tapping a pre-selected person removes its draft edge', () async {
      await enter(selected: {shownPeer});
      final node =
          cubit.graphController.nodePayloadForId('fp:$shownPeer')!;

      cubit.selectMapNode(node);
      await _settle();

      expect(_draftEdgeIds(cubit), isEmpty);
    });

    test('dragging a person to pin is disabled', () async {
      await enter();
      final node = cubit.graphController.nodePayloadForId('fp:$shownPeer');

      expect(cubit.canDragNode(node!), isFalse);
    });

    test('exiting removes the draft node and restores the composition',
        () async {
      final keptBefore = cubit.state.keptPeerIds;
      final nodesBefore = _nodeIds(cubit);
      final edgesBefore = _edgeIds(cubit);
      await enter(selected: {shownPeer});

      cubit.exitComposing();
      await _settle();

      expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
      expect(_nodeIds(cubit), isNot(contains('fd:draft')));
      expect(_nodeIds(cubit), nodesBefore);
      expect(_edgeIds(cubit), edgesBefore);
      expect(cubit.state.keptPeerIds, keptBefore);
      expect(_draftEdgeIds(cubit), isEmpty);
    });
  });
}
