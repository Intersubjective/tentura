import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_mutual_trust.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_mutual_trust_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_mutual_trust_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_arrangement_layout.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import '../../support/constellation_store_fixture.dart';
import 'fixtures/constellation_reference_fixture.dart';

final _loadedAt = DateTime.utc(2026, 10, 23, 12);

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

/// Answers each person's fetch with a completer the test settles.
final class _ControlledPort implements ConstellationMutualTrustPort {
  final List<String> fetched = [];
  final Map<String, Completer<Set<String>>> pending = {};

  @override
  Future<Set<String>> fetchMutualTrust(String personId) {
    fetched.add(personId);
    return (pending[personId] = Completer<Set<String>>()).future;
  }

  void answer(String personId, Set<String> ids) =>
      pending[personId]!.complete(ids);
}

ConstellationTrustEdgeEntity _e(String src, String dst, {int tier = 1}) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: tier);

/// ego trusts a, b, c and d directly and a trusts ego back. a and b trust
/// each other; a trusts c one way only; d trusts a, and a reaches d only by a
/// derived link; a and z trust each other, but z is not on the field. f is
/// reached through b only, and f and c trust each other.
final _field = ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: const [
    ConstellationPerson(id: 'a'),
    ConstellationPerson(id: 'b'),
    ConstellationPerson(id: 'c'),
    ConstellationPerson(id: 'd'),
    ConstellationPerson(id: 'f'),
  ],
  edges: [
    _e('ego', 'a'),
    _e('a', 'ego'),
    _e('ego', 'b'),
    _e('ego', 'c'),
    _e('ego', 'd'),
    _e('a', 'b'),
    _e('b', 'a'),
    _e('a', 'c'),
    _e('d', 'a'),
    _e('a', 'd', tier: 2),
    _e('a', 'z'),
    _e('z', 'a'),
    _e('b', 'f'),
    _e('f', 'c'),
    _e('c', 'f'),
  ],
  directContactIds: const ['a', 'b', 'c', 'd'],
  // People beyond the viewer's contacts are on the field for what they hold.
  requests: const [
    ConstellationRequest(id: 'req-f', authorId: 'f', title: 'Lift', status: 0),
    ConstellationRequest(id: 'req-a', authorId: 'a', title: 'Tea', status: 0),
  ],
);

/// The store behind the cubit [_load] made last.
late ConstellationFieldStoreCase _store;

Future<ConstellationCubit> _load(_ControlledPort port) async {
  _store = ConstellationStoreFixture(
    _StubRepository(_field),
    accountId: 'ego',
  ).store;
  final cubit = ConstellationCubit(
    case_: _store,
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
    mutualTrustCase: ConstellationMutualTrustCase(
      port,
      env: const Env(),
      logger: Logger('test'),
    ),
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

/// Mutual trust edges of the rendered scene, as `src->dst`.
Set<String> _mutualEdges(ConstellationCubit cubit) => {
  for (final edge
      in cubit.graphController.renderSnapshot.topology.edgesById.values)
    if (edge.payload.semanticId.endsWith('#mutualTrust'))
      edge.payload.semanticId
          .replaceAll('#mutualTrust', '')
          .replaceAll('fp:', ''),
};

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'condition not reached in time');
}

Map<GraphNodeId, ScenePoint?> _positions(ConstellationCubit cubit) {
  final snapshot = cubit.graphController.renderSnapshot;
  return {
    for (final id in snapshot.topology.nodesById.keys)
      id: snapshot.resolvePosition(id),
  };
}

NodeDetails _personNode(ConstellationCubit cubit, String id) => cubit
    .graphController
    .renderSnapshot
    .topology
    .nodesById
    .values
    .map((node) => node.payload)
    .firstWhere((node) => node is FieldPersonNode && node.id == id);

void main() {
  group('constellationFieldMutualTrustIds', () {
    test('counts an explicit edge each way, never a derived one', () {
      expect(constellationFieldMutualTrustIds(field: _field, personId: 'a'), {
        'ego',
        'b',
        'z',
      });
      expect(
        constellationFieldMutualTrustIds(field: _field, personId: 'f'),
        {'c'},
      );
      expect(
        constellationFieldMutualTrustIds(field: _field, personId: 'd'),
        isEmpty,
      );
    });

    test('reads the anchors support edges too', () {
      final field = _field.copyWith(
        edges: const [],
        anchorProjection: ConstellationAnchorProjection(
          revision: ConstellationAnchorProjection.empty.revision,
          anchors: const [],
          pinnedPeers: const [],
          pinnedRequests: const [],
          supportPeers: const [],
          supportEdges: [_e('a', 'b'), _e('b', 'a')],
          serverFilteredBeaconIds: const [],
          serverFilteredBeaconCount: 0,
        ),
      );
      expect(constellationFieldMutualTrustIds(field: field, personId: 'a'), {
        'b',
      });
    });
  });

  group('mutual trust edges of the selected person', () {
    late _ControlledPort port;
    late ConstellationCubit cubit;

    setUp(() async {
      port = _ControlledPort();
      cubit = await _load(port);
    });

    tearDown(() => cubit.close());

    test('none before anyone is selected', () {
      expect(_mutualEdges(cubit), isEmpty);
      expect(port.fetched, isEmpty);
    });

    test('selecting a person draws an edge to each person on the field they '
        'trust both ways, the viewer included', () async {
      cubit.selectPerson('a');

      // Not b's one-way c, not the derived d, not z (off the field).
      expect(_mutualEdges(cubit), {'a->ego', 'a->b'});
      expect(port.fetched, ['a']);
    });

    test('deselecting removes them at once', () async {
      cubit.selectPerson('a');
      expect(_mutualEdges(cubit), isNotEmpty);

      cubit.selectPerson(null);

      expect(_mutualEdges(cubit), isEmpty);
    });

    test('selecting someone else shows only their edges', () async {
      cubit
        ..selectPerson('a')
        ..selectPerson('b');

      expect(_mutualEdges(cubit), {'b->a'});
      expect(port.fetched, ['a', 'b']);
    });

    test('the server answer adds the edges the field does not hold', () async {
      cubit.selectPerson('a');
      // c trusts a back where the field cannot see it (e.g. c is pinned);
      // z is not on the field and stays undrawn.
      port.answer('a', {'ego', 'b', 'c', 'z'});
      await _until(() => _mutualEdges(cubit).contains('a->c'));

      expect(_mutualEdges(cubit), {'a->ego', 'a->b', 'a->c'});
    });

    test('a late answer for a person no longer selected changes nothing, and '
        'is reused when they are selected again', () async {
      cubit
        ..selectPerson('a')
        ..selectPerson('b');
      port.answer('a', {'c'});
      await _flush();

      expect(_mutualEdges(cubit), {'b->a'});

      cubit.selectPerson('a');

      expect(_mutualEdges(cubit), {'a->ego', 'a->b', 'a->c'});
      expect(port.fetched, ['a', 'b']);
    });

    test(
      'a changed field asks again, and the new answer replaces the old',
      () async {
        cubit.selectPerson('a');
        port.answer('a', {'ego', 'b'});
        await _flush();
        expect(_mutualEdges(cubit), {'a->ego', 'a->b'});

        // The viewer takes their trust in a back: the field is patched at once.
        _store.applyOwnTrust('a', trusts: false);
        await _flush();
        // a stays on the field (through b, with a Request of their own).
        expect(cubit.state.selectedPersonId, 'a');
        await _until(() => port.fetched.length == 2);
        expect(port.fetched, ['a', 'a']);

        port.answer('a', {'b'});
        await _until(() => !_mutualEdges(cubit).contains('a->ego'));

        expect(_mutualEdges(cubit), {'a->b'});
      },
    );

    test('a failed fetch keeps what the field shows', () async {
      cubit.selectPerson('a');
      port.pending['a']!.completeError(StateError('offline'));
      await _flush();

      expect(_mutualEdges(cubit), {'a->ego', 'a->b'});
    });

    test('off a trust chain, the selected person’s mutual partners stay '
        'undimmed', () async {
      cubit.selectPerson('f');

      expect(_mutualEdges(cubit), {'f->c'});
      // f is reached through b: the chain is ego → b → f.
      expect(cubit.isDimmedByTrustChain(_personNode(cubit, 'b')), isFalse);
      expect(cubit.isDimmedByTrustChain(_personNode(cubit, 'c')), isFalse);
      expect(cubit.isDimmedByTrustChain(_personNode(cubit, 'a')), isTrue);
      expect(cubit.isDimmedByTrustChain(_personNode(cubit, 'd')), isTrue);
    });
  });

  group('mutual trust edges on a mounted field', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Mutual trust overlays never move nodes when answers arrive or leave.
    testWidgets('arriving never moves a node or starts a layout', (
      tester,
    ) async {
      final port = _ControlledPort();
      final cubit = await _load(port);
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit);
      await settle(tester);
      cubit.selectPerson('a');
      await settle(tester);
      // Positive control: the field was laid out.
      expect(cubit.graphController.relayoutInvocationCount, greaterThan(0));
      final before = _positions(cubit);
      expect(before.values, everyElement(isNotNull));
      final reconciliations = cubit.layoutReconciliationCount;
      final layoutRuns = cubit.graphController.relayoutInvocationCount;
      expect(_mutualEdges(cubit), {'a->ego', 'a->b'});

      port.answer('a', {'c'});
      await settle(tester);

      expect(_mutualEdges(cubit), {'a->ego', 'a->b', 'a->c'});
      expect(cubit.layoutReconciliationCount, reconciliations);
      expect(cubit.graphController.relayoutInvocationCount, layoutRuns);
      expect(_positions(cubit), before);
    });

    testWidgets('an answer during a layout waits for it to settle', (
      tester,
    ) async {
      final port = _ControlledPort();
      final cubit = await _load(port);
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit);
      await settle(tester);

      // Selection preserves layout, so start an explicit moving layout.
      cubit.selectPerson('a');
      cubit.requestConstellationLayoutForTest(
        algorithm: ConstellationFixedLayout({
          for (final entry in _positions(cubit).entries)
            entry.key: ScenePoint(
              x: entry.value!.x + 40,
              y: entry.value!.y + 20,
            ),
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(cubit.graphController.isLayoutSettling, isTrue);
      port.answer('a', {'c'});
      await tester.pump(Duration.zero);

      expect(_mutualEdges(cubit), {'a->ego', 'a->b'});

      await settle(tester);
      await settle(tester);

      expect(cubit.graphController.isLayoutSettling, isFalse);
      expect(_mutualEdges(cubit), {'a->ego', 'a->b', 'a->c'});
      // The layout ran to its end: every node rests where it placed it.
      final snapshot = cubit.graphController.renderSnapshot;
      final layout = snapshot.layout!.positions;
      for (final id in snapshot.topology.nodesById.keys) {
        expect(snapshot.resolvePosition(id), layout[id]);
      }
    });
  });
}
