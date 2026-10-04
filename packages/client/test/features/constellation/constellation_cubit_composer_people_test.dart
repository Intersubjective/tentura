// The map composer must offer every reachable person as an addressee: both
// the field's own (possibly capped, for graph-rendering performance) peers
// and everyone else mutually visible via MeritRank / forward candidates —
// not just whoever currently has a rendered node on the graph.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show Offset;
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

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

/// Only `fetchForwardCandidates` is exercised here.
class _FakeForwardRepository implements ForwardRepository {
  _FakeForwardRepository(this.candidates);

  final List<Profile> candidates;
  String? lastContext;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async {
    lastContext = context;
    return candidates;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'composerPeople unions field peers with forward candidates beyond the '
    'capped graph, minus the viewer',
    () async {
      final field = ConstellationField(
        loadedAt: DateTime.utc(2026, 9, 9),
        context: 'ctx-1',
        // Simulates a capped graph: only one peer actually rendered.
        peers: const [ConstellationPerson(id: 'graph-peer')],
        requests: const [
          ConstellationRequest(
            id: 'active-request',
            authorId: 'graph-peer',
            title: 'Active',
            status: 0,
          ),
        ],
        peersCapped: true,
      );
      final forward = _FakeForwardRepository(const [
        Profile(id: 'graph-peer'),
        Profile(id: 'mr-reachable-1'),
        Profile(id: 'mr-reachable-2'),
        _ego, // mutual-visibility feed may echo the viewer back; must drop.
      ]);
      final cubit = ConstellationCubit(
        case_: ConstellationFieldCase(
          _StubRepository(field),
          env: const Env.fromEnvironment(),
          logger: Logger('ComposerPeopleTest'),
        ),
        viewer: _ego,
        forwardRepository: forward,
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);

      final snapshot = await cubit.composerPeople();

      expect(
        snapshot.eligible,
        {'graph-peer', 'mr-reachable-1', 'mr-reachable-2'},
      );
      expect(forward.lastContext, 'ctx-1');
      final normalIds = cubit.graphController.nodes
          .map((n) => n.graphNodeId)
          .toSet();
      expect(normalIds, contains('fr:active-request'));
      cubit.enterComposing(
        draftCentre: const Offset(200, 200),
        candidateIds: snapshot.eligible,
        selectedIds: {'mr-reachable-1'},
        onToggle: (_) {},
      );
      final composingIds = cubit.graphController.nodes
          .map((n) => n.graphNodeId)
          .toSet();
      expect(
        composingIds,
        containsAll(['fp:mr-reachable-1', 'fp:mr-reachable-2', 'fd:draft']),
      );
      expect(composingIds, isNot(contains('fr:active-request')));
      expect(
        cubit.graphController.getPositionOrNullForId('fp:mr-reachable-1'),
        isNot(
          cubit.graphController.getPositionOrNullForId('fp:mr-reachable-2'),
        ),
      );
      expect(
        cubit.state.field,
        field,
        reason: 'normal field is never overwritten',
      );
      cubit.enterComposing(
        draftCentre: const Offset(300, 300),
        candidateIds: snapshot.eligible,
        selectedIds: {'mr-reachable-1'},
        onToggle: (_) {},
      );
      expect(
        cubit.graphController.getPositionOrNullForId('fd:draft'),
        const Offset(300, 300),
      );
      await cubit.load();
      expect(cubit.state.placementPhase, ConstellationPlacementPhase.composing);
      final refreshedIds = cubit.graphController.nodes
          .map((n) => n.graphNodeId)
          .toSet();
      expect(
        refreshedIds,
        containsAll(['fp:mr-reachable-1', 'fp:mr-reachable-2']),
      );
      expect(refreshedIds, isNot(contains('fr:active-request')));
      cubit.exitComposing();
      expect(
        cubit.graphController.nodes.map((n) => n.graphNodeId).toSet(),
        normalIds,
      );
    },
  );

  test(
    'composerPeople falls back to field peers alone when forward candidates '
    'fail to load',
    () async {
      final field = ConstellationField(
        loadedAt: DateTime.utc(2026, 9, 9),
        context: '',
        peers: const [ConstellationPerson(id: 'graph-peer')],
      );
      final cubit = ConstellationCubit(
        case_: ConstellationFieldCase(
          _StubRepository(field),
          env: const Env.fromEnvironment(),
          logger: Logger('ComposerPeopleTest'),
        ),
        viewer: _ego,
        forwardRepository: _ThrowingForwardRepository(),
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);

      final snapshot = await cubit.composerPeople();

      expect(snapshot.eligible, {'graph-peer'});
    },
  );
}

class _ThrowingForwardRepository implements ForwardRepository {
  @override
  Future<Iterable<Profile>> fetchForwardCandidates({String context = ''}) =>
      Future.error(Exception('network down'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
