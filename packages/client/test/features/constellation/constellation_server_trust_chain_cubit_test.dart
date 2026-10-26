import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_chain.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_trust_chain_person.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_trust_chain_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_trust_chain_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import '../../support/constellation_store_fixture.dart';

final _loadedAt = DateTime.utc(2026, 10, 26, 12);

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
final class _ControlledPort implements ConstellationTrustChainPort {
  final List<String> fetched = [];
  final Map<String, Completer<List<ConstellationTrustChainPerson>>> pending =
      {};

  @override
  Future<List<ConstellationTrustChainPerson>> fetchTrustChain(
    String personId,
  ) {
    fetched.add(personId);
    return (pending[personId] =
            Completer<List<ConstellationTrustChainPerson>>())
        .future;
  }

  void answer(String personId, List<ConstellationTrustChainPerson> chain) =>
      pending[personId]!.complete(chain);
}

ConstellationTrustChainPerson _p(String id, String name) =>
    ConstellationTrustChainPerson(id: id, displayName: name);

ConstellationTrustEdgeEntity _e(String src, String dst) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: 1);

/// ego trusts a and c directly; a trusts b, so b is reached locally through
/// a. f and g are on the field for what they hold, with no trust edge the
/// field can see leading to them. x and y are on no field.
final _field = ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: const [
    ConstellationPerson(id: 'a', displayName: 'Alice'),
    ConstellationPerson(id: 'b', displayName: 'Bea'),
    ConstellationPerson(id: 'c', displayName: 'Cleo'),
    ConstellationPerson(id: 'f', displayName: 'Fay'),
    ConstellationPerson(id: 'g', displayName: 'Gus'),
  ],
  edges: [_e('ego', 'a'), _e('a', 'ego'), _e('ego', 'c'), _e('a', 'b')],
  directContactIds: const ['a', 'c'],
  requests: const [
    ConstellationRequest(id: 'req-f', authorId: 'f', title: 'Lift', status: 0),
    ConstellationRequest(id: 'req-g', authorId: 'g', title: 'Tea', status: 0),
  ],
);

Future<ConstellationCubit> _load(_ControlledPort port) async {
  final store = ConstellationStoreFixture(
    _StubRepository(_field),
    accountId: 'ego',
  ).store;
  final cubit = ConstellationCubit(
    case_: store,
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
    trustChainCase: ConstellationTrustChainCase(
      port,
      env: const Env(),
      logger: Logger('test'),
    ),
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

NodeDetails _personNode(ConstellationCubit cubit, String id) => cubit
    .graphController
    .renderSnapshot
    .topology
    .nodesById
    .values
    .map((node) => node.payload)
    .firstWhere((node) => node is FieldPersonNode && node.id == id);

NodeDetails _beaconNode(ConstellationCubit cubit, String authorId) => cubit
    .graphController
    .renderSnapshot
    .topology
    .nodesById
    .values
    .map((node) => node.payload)
    .firstWhere((node) => node is FieldBeaconNode && node.userId == authorId);

/// Ego → Alice → Xenia → Fay: Xenia is on no field.
final _chainToFay = [
  _p('ego', 'Ego'),
  _p('a', 'Alice'),
  _p('x', 'Xenia'),
  _p('f', 'Fay'),
];

final _chainToGus = [
  _p('ego', 'Ego'),
  _p('c', 'Cleo'),
  _p('y', 'Yuri'),
  _p('g', 'Gus'),
];

void main() {
  group('server trust chain when the field holds none', () {
    late _ControlledPort port;
    late ConstellationCubit cubit;

    setUp(() async {
      port = _ControlledPort();
      cubit = await _load(port);
    });

    tearDown(() => cubit.close());

    test('a chain the field shows is used without asking the server', () async {
      cubit.selectPerson('b');
      await _flush();

      expect(cubit.selectedTrustChain, isA<ConstellationTrustChainFound>());
      expect(
        (cubit.selectedTrustChain! as ConstellationTrustChainFound).path,
        ['ego', 'a', 'b'],
      );
      expect(port.fetched, isEmpty);
    });

    test('a direct contact is used without asking the server', () async {
      cubit.selectPerson('a');
      await _flush();

      expect(cubit.selectedTrustChain, isA<ConstellationTrustChainDirect>());
      expect(port.fetched, isEmpty);
    });

    test(
      'selecting someone no chain reaches asks the server for their '
      'chain, and nothing is drawn but "no chain" until it answers',
      () async {
        cubit.selectPerson('f');
        await _flush();

        expect(port.fetched, ['f']);
        expect(cubit.selectedTrustChain, isA<ConstellationTrustChainNone>());
      },
    );

    test('the server chain replaces "no chain", intermediates included even '
        'when they are on no field', () async {
      cubit.selectPerson('f');
      port.answer('f', _chainToFay);
      await _flush();

      final chain = cubit.selectedTrustChain;
      expect(chain, isA<ConstellationTrustChainFound>());
      final found = chain! as ConstellationTrustChainFound;
      expect(found.path, ['ego', 'a', 'x', 'f']);
      expect(found.intermediaryIds, ['a', 'x']);
    });

    test('people on the field in the server chain stay undimmed, everyone '
        'else off the chain is dimmed', () async {
      cubit.selectPerson('f');
      port.answer('f', _chainToFay);
      await _flush();

      expect(cubit.isDimmedByTrustChain(_personNode(cubit, 'a')), isFalse);
      expect(cubit.isDimmedByTrustChain(_personNode(cubit, 'f')), isFalse);
      expect(cubit.isDimmedByTrustChain(_beaconNode(cubit, 'f')), isFalse);
      expect(cubit.isDimmedByTrustChain(_personNode(cubit, 'c')), isTrue);
      expect(cubit.isDimmedByTrustChain(_personNode(cubit, 'g')), isTrue);
    });

    test('an answer with no chain keeps "no chain"', () async {
      cubit.selectPerson('f');
      port.answer('f', const []);
      await _flush();

      expect(cubit.selectedTrustChain, isA<ConstellationTrustChainNone>());
    });

    test('a failed fetch keeps "no chain"', () async {
      cubit.selectPerson('f');
      port.pending['f']!.completeError(StateError('offline'));
      await _flush();

      expect(cubit.selectedTrustChain, isA<ConstellationTrustChainNone>());
    });

    test('a late answer for a person no longer selected is ignored', () async {
      cubit
        ..selectPerson('f')
        ..selectPerson('g');
      port.answer('f', _chainToFay);
      await _flush();

      expect(cubit.state.selectedPersonId, 'g');
      expect(port.fetched, ['f', 'g']);
      expect(cubit.selectedTrustChain, isA<ConstellationTrustChainNone>());

      port.answer('g', _chainToGus);
      await _flush();

      expect(
        (cubit.selectedTrustChain! as ConstellationTrustChainFound).path,
        ['ego', 'c', 'y', 'g'],
      );
    });

    test('an answer is kept for the session: selecting the person again '
        'shows it without asking again', () async {
      cubit.selectPerson('f');
      port.answer('f', _chainToFay);
      await _flush();

      cubit
        ..selectPerson('g')
        ..selectPerson('f');
      await _flush();

      expect(
        (cubit.selectedTrustChain! as ConstellationTrustChainFound).path,
        ['ego', 'a', 'x', 'f'],
      );
      expect(port.fetched, ['f', 'g']);
    });

    test('an answer that arrived after its person was deselected is shown '
        'when they are selected again', () async {
      cubit
        ..selectPerson('f')
        ..selectPerson('g');
      port.answer('f', _chainToFay);
      await _flush();

      cubit.selectPerson('f');
      await _flush();

      expect(
        (cubit.selectedTrustChain! as ConstellationTrustChainFound).path,
        ['ego', 'a', 'x', 'f'],
      );
      expect(port.fetched, ['f', 'g']);
    });
  });
}
