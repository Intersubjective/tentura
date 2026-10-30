import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_shown_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_trust_chain_person.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_trust_chain_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_trust_chain_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import '../../support/constellation_store_fixture.dart';
import 'fixtures/constellation_reference_fixture.dart';

// #641 (QA on 7.56.6): with the 2nd degree switched off, the selected
// person's panel still said "Through Bob → Alice", naming hidden Alice, and
// a partial dotted chain was drawn. The field's own chain already skips
// hidden people; the server chain (#779) that stands in for "no chain" did
// not, so it brought the hidden people back.

final _loadedAt = DateTime.utc(2026, 10, 30, 12);

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

ConstellationTrustEdgeEntity _e(String src, String dst) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: 1);

ConstellationTrustChainPerson _p(String id, String name) =>
    ConstellationTrustChainPerson(id: id, displayName: name);

/// The QA field: ego trusts Bob; Bob trusts Alice and Dave; Alice trusts
/// New member and Dave. Cleo is another direct contact, and Fay is on the
/// field for her Request with no trust edge the field shows leading to her.
final _field = ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: const [
    ConstellationPerson(id: 'b', displayName: 'Bob'),
    ConstellationPerson(id: 'a', displayName: 'Alice'),
    ConstellationPerson(id: 'd', displayName: 'Dave'),
    ConstellationPerson(id: 'n', displayName: 'New member'),
    ConstellationPerson(id: 'c', displayName: 'Cleo'),
    ConstellationPerson(id: 'f', displayName: 'Fay'),
  ],
  edges: [
    _e('ego', 'b'),
    _e('b', 'a'),
    _e('b', 'd'),
    _e('a', 'n'),
    _e('a', 'd'),
    _e('ego', 'c'),
  ],
  directContactIds: const ['b', 'c'],
  requests: const [
    ConstellationRequest(id: 'req-f', authorId: 'f', title: 'Lift', status: 0),
  ],
);

/// What the server names for New member: the same chain the field showed
/// with every degree on.
final _chainToNew = [
  _p('ego', 'Ego'),
  _p('b', 'Bob'),
  _p('a', 'Alice'),
  _p('n', 'New member'),
];

/// Ego → Cleo → Fay: only a first-degree person in between.
final _chainToFay = [_p('ego', 'Ego'), _p('c', 'Cleo'), _p('f', 'Fay')];

/// Ego → Cleo → Xenia → Fay: Xenia is on no field, two steps from ego.
final _chainToFayViaOffField = [
  _p('ego', 'Ego'),
  _p('c', 'Cleo'),
  _p('x', 'Xenia'),
  _p('f', 'Fay'),
];

const _noSecondDegree = ConstellationVisibility(secondDegree: false);

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

Iterable<NodeDetails> _nodes(ConstellationCubit cubit) => cubit
    .graphController
    .renderSnapshot
    .topology
    .nodesById
    .values
    .map((node) => node.payload);

const _hiddenText =
    'No chain of trust among the people shown leads to this person. '
    'Some people are hidden.';

String _chainLineText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('constellation.trust_chain')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  group('server chain while the switches hide people (#641)', () {
    late _ControlledPort port;
    late ConstellationCubit cubit;

    setUp(() async {
      port = _ControlledPort();
      cubit = await _load(port);
    });

    tearDown(() => cubit.close());

    test('guard: with every degree on, the field names Bob → Alice', () async {
      cubit.selectPerson('n');
      await _flush();

      final chain = cubit.selectedTrustChain;
      expect(chain, isA<ConstellationTrustChainFound>());
      expect((chain! as ConstellationTrustChainFound).path, [
        'ego',
        'b',
        'a',
        'n',
      ]);
    });

    test('2nd degree off: a server chain through hidden Alice is not used, '
        'so nothing partial is drawn and nothing is dimmed', () async {
      cubit.selectPerson('n');
      await _flush();
      cubit.setVisibility(_noSecondDegree);
      await _flush();

      expect(
        _nodes(cubit).any((n) => n is FieldPersonNode && n.id == 'a'),
        isFalse,
        reason: 'precondition: the switch hides Alice',
      );
      expect(port.fetched, ['n']);
      port.answer('n', _chainToNew);
      await _flush();

      expect(cubit.selectedTrustChain, isA<ConstellationTrustChainNone>());
      expect(_nodes(cubit).where(cubit.isDimmedByTrustChain), isEmpty);
    });

    test('selecting again with the switch already off gives the same '
        'answer', () async {
      cubit.setVisibility(_noSecondDegree);
      await _flush();
      cubit.selectPerson('n');
      await _flush();
      port.answer('n', _chainToNew);
      await _flush();

      expect(cubit.selectedTrustChain, isA<ConstellationTrustChainNone>());
    });

    test(
      'the kept server chain comes back once the degree is shown again',
      () async {
        cubit.setVisibility(_noSecondDegree);
        await _flush();
        cubit.selectPerson('f');
        await _flush();
        port.answer('f', _chainToFayViaOffField);
        await _flush();
        expect(cubit.selectedTrustChain, isA<ConstellationTrustChainNone>());

        cubit.setVisibility(ConstellationVisibility.all);
        await _flush();

        expect(
          (cubit.selectedTrustChain! as ConstellationTrustChainFound).path,
          ['ego', 'c', 'x', 'f'],
        );
      },
    );

    test(
      'guard: a server chain through shown people only still stands in',
      () async {
        cubit.setVisibility(_noSecondDegree);
        await _flush();
        cubit.selectPerson('f');
        await _flush();
        port.answer('f', _chainToFay);
        await _flush();

        expect(
          (cubit.selectedTrustChain! as ConstellationTrustChainFound).path,
          ['ego', 'c', 'f'],
        );
      },
    );
  });

  testWidgets('the panel says some people are hidden instead of naming '
      'hidden Alice', (tester) async {
    final port = _ControlledPort();
    final cubit = await _load(port);
    addTearDown(cubit.close);
    await pumpConstellationBody(tester, cubit, locale: const Locale('en'));

    cubit.selectPerson('n');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_chainLineText(tester), 'Through Bob → Alice');

    cubit.setVisibility(_noSecondDegree);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    port.answer('n', _chainToNew);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_chainLineText(tester), _hiddenText);
  });
}
