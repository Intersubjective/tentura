// When no chain of trust reaches a person, the panel says why they are on the
// Field anyway, from how the field holds them: a Request they forwarded, the
// viewer's own pin, or a Request they share. The generic "no chain" text is
// for people nothing is known about.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_visibility.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_trust_chain_person.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_trust_chain_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_trust_chain_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

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

const _noChainEn = 'No chain of trust you can see leads to this person.';
const _noChainRu =
    'Ни одна видимая вам цепочка доверия не ведёт к этому человеку.';
const _hiddenRu =
    'Среди показанных людей нет цепочки доверия к этому человеку. '
    'Часть людей скрыта.';
const _hiddenEn =
    'No chain of trust among the people shown leads to this person. '
    'Some people are hidden.';

const _forwardedRequest = ConstellationRequest(
  id: 'B-roof',
  authorId: 't',
  title: 'Fix the roof',
  status: 0,
);

const _sharedRequest = ConstellationRequest(
  id: 'B-shared',
  authorId: 'b',
  title: 'Move the piano',
  status: 0,
);

/// Holds a Request of their own and no trust edge leads to them.
final _sharedPost = ConstellationPost(
  id: 'P-shared',
  authorId: 'b',
  rootExcerpt: 'Garden notes',
  lastActivityAt: DateTime.utc(2026, 10, 20),
);

const _plainRequest = ConstellationRequest(
  id: 'B-plain',
  authorId: 'n',
  title: 'Borrow a ladder',
  status: 0,
);

ConstellationField _field({
  List<ConstellationPerson> people = const [],
  List<ConstellationRequest> requests = const [],
  List<ConstellationPost> posts = const [],
  ConstellationAnchorProjection? anchorProjection,
}) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: people,
  requests: requests,
  posts: posts,
  anchorProjection: anchorProjection,
);

ConstellationAnchorProjection _pinned(ConstellationPerson person) =>
    ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision.zero,
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.person(person.id),
          position: const ConstellationAnchorPosition(
            xUnits: 2,
            yUnits: 1,
            coordinateSpaceVersion: 1,
          ),
          revision: ConstellationAnchorRevision.zero,
          placedAt: DateTime.utc(2026, 10),
        ),
      ],
      pinnedPeers: [person],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    );

/// Answers each person's server chain fetch with a completer the test settles.
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
}

Future<ConstellationCubit> _load(
  ConstellationField field, {
  ConstellationTrustChainPort? port,
}) async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(field),
      accountId: 'ego',
    ).store,
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
    trustChainCase: port == null
        ? null
        : ConstellationTrustChainCase(
            port,
            env: const Env(),
            logger: Logger('test'),
          ),
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  addTearDown(cubit.close);
  return cubit;
}

String _chainLineText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('constellation.trust_chain')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  group('trust chain line when no chain reaches the person', () {
    Future<String> lineFor(
      WidgetTester tester,
      ConstellationField field,
      String personId, {
      String locale = 'en',
      ConstellationVisibility? visibility,
    }) async {
      final cubit = await _load(field);
      await pumpConstellationBody(tester, cubit, locale: Locale(locale));
      if (visibility != null) {
        cubit.setVisibility(visibility);
      }
      cubit.selectPerson(personId);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return _chainLineText(tester);
    }

    const forwarder = ConstellationPerson(
      id: 't',
      displayName: 'Tia',
      fieldMembership: ConstellationFieldMembership.temporary,
      temporaryBeaconId: 'B-roof',
    );
    const unnamedForwarder = ConstellationPerson(
      id: 't',
      fieldMembership: ConstellationFieldMembership.temporary,
      temporaryBeaconId: 'B-roof',
    );
    const pinnedPerson = ConstellationPerson(
      id: 'p',
      displayName: 'Pia',
      visible: false,
    );
    const requestBond = ConstellationPerson(
      id: 'b',
      displayName: 'Bea',
      fieldMembership: ConstellationFieldMembership.bond,
      bondContexts: [
        ConstellationBondContext(beaconId: 'B-shared', title: 'Move the piano'),
      ],
    );
    const postBond = ConstellationPerson(
      id: 'b',
      displayName: 'Bea',
      fieldMembership: ConstellationFieldMembership.bond,
      bondContexts: [
        ConstellationBondContext(beaconId: 'P-shared', title: 'Garden notes'),
      ],
    );
    final forwarderField = _field(
      people: const [forwarder],
      requests: const [_forwardedRequest],
    );
    final unnamedForwarderField = _field(
      people: const [unnamedForwarder],
      requests: const [_forwardedRequest],
    );
    final pinnedField = _field(anchorProjection: _pinned(pinnedPerson));
    final requestBondField = _field(
      people: const [requestBond],
      requests: const [_sharedRequest],
    );
    final postBondField = _field(
      people: const [postBond],
      posts: [_sharedPost],
    );
    const unlistedBond = ConstellationPerson(
      id: 'b',
      displayName: 'Bea',
      fieldMembership: ConstellationFieldMembership.bond,
      bondContexts: [
        ConstellationBondContext(beaconId: 'B-gone', title: 'Old project'),
      ],
    );
    final unlistedBondField = _field(people: const [unlistedBond]);
    final nothingKnownField = _field(
      people: const [ConstellationPerson(id: 'n', displayName: 'Nan')],
      requests: const [_plainRequest],
    );

    testWidgets('names the person who forwarded their Request to the viewer', (
      tester,
    ) async {
      expect(
        await lineFor(tester, forwarderField, 't'),
        'On your field because Tia forwarded you their Request',
      );
    });

    testWidgets('says someone forwarded their Request when the forwarder has '
        'no name', (tester) async {
      expect(
        await lineFor(tester, unnamedForwarderField, 't'),
        'On your field because someone forwarded you their Request',
      );
    });

    testWidgets('says someone forwarded their Request when the Request is not '
        'on the field and the forwarder has no name', (tester) async {
      expect(
        await lineFor(tester, _field(people: const [unnamedForwarder]), 't'),
        'On your field because someone forwarded you their Request',
      );
    });

    testWidgets('tells a person only the viewer pinned that they pinned them', (
      tester,
    ) async {
      expect(
        await lineFor(tester, pinnedField, 'p'),
        'You pinned them to your field',
      );
    });

    testWidgets('names the Request a bond person shares with the viewer', (
      tester,
    ) async {
      expect(
        await lineFor(tester, requestBondField, 'b'),
        'On your field because you share the Request “Move the piano”',
      );
    });

    testWidgets('names the Post a bond person shares with the viewer', (
      tester,
    ) async {
      expect(
        await lineFor(tester, postBondField, 'b'),
        'On your field because you share the Post “Garden notes”',
      );
    });

    testWidgets('names the shared item as a Request when a bond context is '
        'on neither the Requests nor the Posts of the field', (tester) async {
      expect(
        await lineFor(tester, unlistedBondField, 'b'),
        'On your field because you share the Request “Old project”',
      );
    });

    testWidgets('names the shared item as a Request in Russian when a bond '
        'context is on neither the Requests nor the Posts of the field', (
      tester,
    ) async {
      expect(
        await lineFor(tester, unlistedBondField, 'b', locale: 'ru'),
        'На вашем поле, потому что у вас общий запрос «Old project»',
      );
    });

    testWidgets('keeps the generic text for a person nothing is known about', (
      tester,
    ) async {
      expect(await lineFor(tester, nothingKnownField, 'n'), _noChainEn);
    });

    testWidgets('keeps the hidden-people text when switches hide people and '
        'nothing else is known', (tester) async {
      expect(
        await lineFor(
          tester,
          nothingKnownField,
          'n',
          visibility: const ConstellationVisibility(posts: false),
        ),
        _hiddenEn,
      );
    });

    testWidgets('keeps the hidden-people text in Russian', (tester) async {
      expect(
        await lineFor(
          tester,
          nothingKnownField,
          'n',
          locale: 'ru',
          visibility: const ConstellationVisibility(posts: false),
        ),
        _hiddenRu,
      );
    });

    testWidgets('names the forwarder in Russian', (tester) async {
      expect(
        await lineFor(tester, forwarderField, 't', locale: 'ru'),
        'На вашем поле, потому что Tia переслал(а) вам свой запрос',
      );
    });

    testWidgets('says someone forwarded their Request in Russian when the '
        'forwarder has no name', (tester) async {
      expect(
        await lineFor(tester, unnamedForwarderField, 't', locale: 'ru'),
        'На вашем поле, потому что кто-то переслал вам свой запрос',
      );
    });

    testWidgets('tells a person only the viewer pinned that they pinned them, '
        'in Russian', (tester) async {
      expect(
        await lineFor(tester, pinnedField, 'p', locale: 'ru'),
        'Вы закрепили этого человека на своём поле',
      );
    });

    testWidgets('names the shared Request of a bond person in Russian', (
      tester,
    ) async {
      expect(
        await lineFor(tester, requestBondField, 'b', locale: 'ru'),
        'На вашем поле, потому что у вас общий запрос «Move the piano»',
      );
    });

    testWidgets('names the shared Post of a bond person in Russian', (
      tester,
    ) async {
      expect(
        await lineFor(tester, postBondField, 'b', locale: 'ru'),
        'На вашем поле, потому что у вас общий пост «Garden notes»',
      );
    });

    testWidgets('keeps the generic Russian text for a person nothing is '
        'known about', (tester) async {
      expect(
        await lineFor(tester, nothingKnownField, 'n', locale: 'ru'),
        _noChainRu,
      );
    });
  });

  group('trust chain line against a server chain', () {
    ConstellationTrustChainPerson p(String id, String name) =>
        ConstellationTrustChainPerson(id: id, displayName: name);

    const forwarder = ConstellationPerson(
      id: 't',
      displayName: 'Tia',
      fieldMembership: ConstellationFieldMembership.temporary,
      temporaryBeaconId: 'B-roof',
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<(_ControlledPort, ConstellationCubit)> mount(
      WidgetTester tester,
      ConstellationField field, {
      String locale = 'en',
    }) async {
      final port = _ControlledPort();
      final cubit = await _load(field, port: port);
      await pumpConstellationBody(tester, cubit, locale: Locale(locale));
      return (port, cubit);
    }

    testWidgets('shows why the person is on the field while the server has '
        'not answered, then the server chain once it has', (tester) async {
      final (port, cubit) = await mount(
        tester,
        _field(people: const [forwarder], requests: const [_forwardedRequest]),
      );
      cubit.selectPerson('t');
      await settle(tester);

      expect(port.fetched, ['t']);
      expect(
        _chainLineText(tester),
        'On your field because Tia forwarded you their Request',
      );

      port.pending['t']!.complete([
        p('ego', 'Ego'),
        p('x', 'Xenia'),
        p('t', 'Tia'),
      ]);
      await settle(tester);

      expect(_chainLineText(tester), 'Through Xenia');
    });

    testWidgets('shows why the person is on the field when the server fails', (
      tester,
    ) async {
      final (port, cubit) = await mount(
        tester,
        _field(people: const [forwarder], requests: const [_forwardedRequest]),
      );
      cubit.selectPerson('t');
      await settle(tester);

      port.pending['t']!.completeError(StateError('offline'));
      await settle(tester);

      expect(
        _chainLineText(tester),
        'On your field because Tia forwarded you their Request',
      );
    });

    testWidgets('shows the local chain, not the reason, for a person the '
        'viewer reaches through a contact', (tester) async {
      final (port, cubit) = await mount(
        tester,
        ConstellationField(
          loadedAt: _loadedAt,
          context: '',
          peers: const [
            ConstellationPerson(id: 'a', displayName: 'Alice'),
            ConstellationPerson(
              id: 't',
              displayName: 'Tia',
              fieldMembership: ConstellationFieldMembership.temporary,
              temporaryBeaconId: 'B-roof',
            ),
          ],
          edges: const [
            ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
            ConstellationTrustEdgeEntity(src: 'a', dst: 't', tier: 1),
          ],
          directContactIds: const ['a'],
          requests: const [_forwardedRequest],
        ),
      );
      cubit.selectPerson('t');
      await settle(tester);

      expect(_chainLineText(tester), 'Through Alice');
      expect(port.fetched, isEmpty);
    });
  });
}
