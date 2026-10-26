import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_trust_chain_person.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_trust_chain_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_trust_chain_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_store_fixture.dart';
import 'fixtures/constellation_reference_fixture.dart';

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

const _noChainText = 'No chain of trust you can see leads to this person.';

String _chainLineText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('constellation.trust_chain')),
        matching: find.byType(Text),
      ),
    )
    .data!;

ConstellationTrustChainPerson _p(String id, String name) =>
    ConstellationTrustChainPerson(id: id, displayName: name);

/// Ego → Alice → Xenia → Fay: Xenia is on no field.
final _chainToFay = [
  _p('ego', 'Ego'),
  _p('a', 'Alice'),
  _p('x', 'Xenia'),
  _p('f', 'Fay'),
];

/// Ego → Cleo → Yuri → Gus: Yuri is on no field.
final _chainToGus = [
  _p('ego', 'Ego'),
  _p('c', 'Cleo'),
  _p('y', 'Yuri'),
  _p('g', 'Gus'),
];

const _fayLine = 'Through Alice → Xenia';
const _gusLine = 'Through Cleo → Yuri';

void main() {
  group('trust chain line with a server chain', () {
    late _ControlledPort port;
    late ConstellationCubit cubit;

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> select(WidgetTester tester, String personId) async {
      cubit.selectPerson(personId);
      await settle(tester);
    }

    Future<void> answer(
      WidgetTester tester,
      String personId,
      List<ConstellationTrustChainPerson> chain,
    ) async {
      port.answer(personId, chain);
      await settle(tester);
    }

    Future<void> mount(WidgetTester tester) async {
      port = _ControlledPort();
      cubit = await _load(port);
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit, locale: const Locale('en'));
    }

    testWidgets('names the people of the server chain, one that is on no '
        'field among them', (tester) async {
      await mount(tester);
      await select(tester, 'f');

      expect(_chainLineText(tester), _noChainText);

      await answer(tester, 'f', _chainToFay);

      expect(_chainLineText(tester), _fayLine);
    });

    testWidgets('keeps the current text while the server has not answered', (
      tester,
    ) async {
      await mount(tester);
      await select(tester, 'f');
      await tester.pump(const Duration(seconds: 1));

      expect(port.fetched, ['f']);
      expect(_chainLineText(tester), _noChainText);
    });

    testWidgets('selecting another person whose chain is still loading shows '
        'their current text, not the previous person’s chain or nothing', (
      tester,
    ) async {
      await mount(tester);
      await select(tester, 'f');
      await answer(tester, 'f', _chainToFay);
      expect(_chainLineText(tester), _fayLine);

      await select(tester, 'g');

      expect(port.fetched, ['f', 'g']);
      expect(
        find.byKey(const Key('constellation.trust_chain')),
        findsOneWidget,
      );
      expect(_chainLineText(tester), _noChainText);
    });

    testWidgets('keeps the "no chain" text when the server fails', (
      tester,
    ) async {
      await mount(tester);
      await select(tester, 'f');

      port.pending['f']!.completeError(StateError('offline'));
      await settle(tester);

      expect(_chainLineText(tester), _noChainText);
    });

    testWidgets('a chain the field shows is named without asking the server', (
      tester,
    ) async {
      await mount(tester);
      await select(tester, 'b');

      expect(_chainLineText(tester), 'Through Alice');
      expect(port.fetched, isEmpty);
    });

    testWidgets('a late answer for a person no longer selected is not shown '
        'for the current one, whose own answer then replaces "no chain"', (
      tester,
    ) async {
      await mount(tester);
      await select(tester, 'f');
      await select(tester, 'g');

      await answer(tester, 'f', _chainToFay);
      expect(_chainLineText(tester), _noChainText);

      await answer(tester, 'g', _chainToGus);
      expect(_chainLineText(tester), _gusLine);
    });

    testWidgets('a late answer arriving after the current person’s own '
        'answer leaves that answer shown', (tester) async {
      await mount(tester);
      await select(tester, 'f');
      await select(tester, 'g');
      await answer(tester, 'g', _chainToGus);
      expect(_chainLineText(tester), _gusLine);

      await answer(tester, 'f', _chainToFay);

      expect(_chainLineText(tester), _gusLine);
    });

    testWidgets('selecting a person again shows their kept chain without '
        'asking the server again', (tester) async {
      await mount(tester);
      await select(tester, 'f');
      await answer(tester, 'f', _chainToFay);
      await select(tester, 'g');
      expect(_chainLineText(tester), _noChainText);

      await select(tester, 'f');

      expect(_chainLineText(tester), _fayLine);
      expect(port.fetched, ['f', 'g']);
    });

    testWidgets('an answer that arrived while its person was deselected is '
        'shown when they are selected again', (tester) async {
      await mount(tester);
      await select(tester, 'f');
      await select(tester, 'g');
      await answer(tester, 'f', _chainToFay);

      await select(tester, 'f');

      expect(_chainLineText(tester), _fayLine);
      expect(port.fetched, ['f', 'g']);
    });
  });
}
