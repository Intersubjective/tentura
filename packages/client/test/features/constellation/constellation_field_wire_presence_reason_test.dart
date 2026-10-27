// A field response as the server sends it carries why each person is on the
// Field (`presence`, `temporaryBeaconId`, `bondContexts`). Those fields must
// survive the real fetch-and-map path, so that the trust chain line can say
// why a person with no chain of trust is there; hand-built entities do not
// prove the client ever reads them.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_store_fixture.dart';
import 'fixtures/constellation_reference_fixture.dart';

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

Map<String, Object?> _peer(
  String id, {
  String? displayName,
  String presence = 'visible',
  String? temporaryBeaconId,
  List<Map<String, String>> bondContexts = const [],
}) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'contactOnly': false,
  'displayName': displayName,
  'handle': null,
  'image': null,
  'presence': presence,
  'temporaryBeaconId': temporaryBeaconId,
  'bondContexts': [
    for (final context in bondContexts)
      {'__typename': 'v2_ConstellationBondContext', ...context},
  ],
};

Map<String, Object?> _post(String id, String excerpt) => {
  '__typename': 'v2_ConstellationPost',
  'id': id,
  'authorId': 'Uauthor000001',
  'lastActivityAt': '2026-10-25T12:00:00.000Z',
  'rootExcerpt': excerpt,
  'isPinned': false,
  'hiddenReachCount': 0,
  'expiresAt': null,
  'status': 0,
};

/// [pinnedPeer] is a person only the viewer pinned: the field lists them
/// under the anchor projection, not among the peers.
Map<String, Object?> _fieldResponse({
  List<Map<String, Object?>> peers = const [],
  List<Map<String, Object?>> posts = const [],
  Map<String, Object?>? pinnedPeer,
}) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-10-26T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': <String>[],
    'peers': peers,
    'edges': <dynamic>[],
    'requests': <dynamic>[],
    'posts': posts,
    'memberWebs': <dynamic>[],
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': pinnedPeer == null ? '0' : '1',
      'anchors': [
        if (pinnedPeer != null)
          {
            '__typename': 'v2_ConstellationAnchor',
            'targetKind': 'PERSON',
            'targetId': pinnedPeer['id'],
            'xUnits': 2.0,
            'yUnits': 1.0,
            'coordinateSpaceVersion': 1,
            'revision': '1',
            'placedAt': '2026-10-26T11:00:00.000Z',
          },
      ],
      'pinnedPeers': [
        if (pinnedPeer != null) {...pinnedPeer, 'visible': false},
      ],
      'pinnedRequests': <dynamic>[],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <String>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

ConstellationField _mapped(Map<String, Object?> response) =>
    mapConstellationFieldFromFieldFetch(
      GConstellationFieldFetchData.fromJson(response)!.constellationField,
    );

ConstellationPerson _personOf(ConstellationField field, String id) =>
    field.peers.firstWhere((peer) => peer.id == id);

void main() {
  group('field response mapping of why a person is on the field', () {
    test('maps a temporary peer with the Request that forwarded them', () {
      final field = _mapped(
        _fieldResponse(
          peers: [
            _peer(
              'Uann000000001',
              displayName: 'QA779 Ann',
              presence: 'temporary',
              temporaryBeaconId: 'B3bdd82502fb2',
            ),
          ],
        ),
      );

      final person = _personOf(field, 'Uann000000001');
      expect(person.fieldMembership, ConstellationFieldMembership.temporary);
      expect(person.temporaryBeaconId, 'B3bdd82502fb2');
    });

    test('maps a bond peer with the Requests shared with the viewer', () {
      final field = _mapped(
        _fieldResponse(
          peers: [
            _peer(
              'Ubea000000001',
              displayName: 'Bea',
              presence: 'bond',
              bondContexts: [
                {'beaconId': 'B-shared', 'title': 'Move the piano'},
                {'beaconId': 'B-second', 'title': 'Paint the fence'},
              ],
            ),
          ],
        ),
      );

      final person = _personOf(field, 'Ubea000000001');
      expect(person.fieldMembership, ConstellationFieldMembership.bond);
      expect(person.bondContexts, const [
        ConstellationBondContext(beaconId: 'B-shared', title: 'Move the piano'),
        ConstellationBondContext(
          beaconId: 'B-second',
          title: 'Paint the fence',
        ),
      ]);
    });

    test('maps a contact-only peer as contact-only', () {
      final field = _mapped(
        _fieldResponse(
          peers: [_peer('Ucon000000001', presence: 'contactOnly')],
        ),
      );

      expect(
        _personOf(field, 'Ucon000000001').fieldMembership,
        ConstellationFieldMembership.contactOnly,
      );
    });

    test('maps a pinned-only peer listed among the peers', () {
      final field = _mapped(
        _fieldResponse(
          peers: [
            _peer(
              'Upia000000001',
              displayName: 'Pia',
              presence: 'pinnedOnly',
            ),
          ],
        ),
      );

      final person = _personOf(field, 'Upia000000001');
      expect(person.fieldMembership.name, 'pinnedOnly');
      expect(person.temporaryBeaconId, isNull);
      expect(person.bondContexts, isEmpty);
    });

    test('keeps an ordinary visible peer free of presence details', () {
      final field = _mapped(
        _fieldResponse(peers: [_peer('Uvis000000001', displayName: 'Vic')]),
      );

      final person = _personOf(field, 'Uvis000000001');
      expect(person.fieldMembership, ConstellationFieldMembership.visible);
      expect(person.temporaryBeaconId, isNull);
      expect(person.bondContexts, isEmpty);
    });

    test('maps the presence of a person only the viewer pinned', () {
      final field = _mapped(
        _fieldResponse(
          pinnedPeer: _peer(
            'Upia000000001',
            displayName: 'Pia',
            presence: 'pinnedOnly',
          ),
        ),
      );

      final pinned = field.resolvedAnchorProjection.pinnedPeers.single;
      expect(pinned.id, 'Upia000000001');
      expect(pinned.visible, isFalse);
      // The domain mirrors the wire presence value one to one.
      expect(pinned.fieldMembership.name, 'pinnedOnly');
      expect(pinned.temporaryBeaconId, isNull);
      expect(pinned.bondContexts, isEmpty);
    });

    test('maps temporary presence details on a pinned person', () {
      final field = _mapped(
        _fieldResponse(
          pinnedPeer: _peer(
            'Upia000000001',
            presence: 'temporary',
            temporaryBeaconId: 'B3bdd82502fb2',
          ),
        ),
      );

      final pinned = field.resolvedAnchorProjection.pinnedPeers.single;
      expect(pinned.fieldMembership, ConstellationFieldMembership.temporary);
      expect(pinned.temporaryBeaconId, 'B3bdd82502fb2');
    });

    test('maps bond presence details on a pinned person', () {
      final field = _mapped(
        _fieldResponse(
          pinnedPeer: _peer(
            'Upia000000001',
            presence: 'bond',
            bondContexts: [
              {'beaconId': 'B-shared', 'title': 'Move the piano'},
            ],
          ),
        ),
      );

      final pinned = field.resolvedAnchorProjection.pinnedPeers.single;
      expect(pinned.fieldMembership, ConstellationFieldMembership.bond);
      expect(pinned.bondContexts, const [
        ConstellationBondContext(beaconId: 'B-shared', title: 'Move the piano'),
      ]);
    });
  });

  group('field fetch operation requests why a person is on the field', () {
    final source = File(
      'lib/features/constellation/data/gql/constellation_field_fetch.graphql',
    ).readAsStringSync();

    /// The selection set that follows [fieldName] `{` in the operation.
    String selectionOf(String fieldName) {
      final start = RegExp('\\b$fieldName\\s*\\{').firstMatch(source);
      expect(start, isNotNull, reason: '$fieldName is selected');
      var depth = 1;
      var i = start!.end;
      while (depth > 0 && i < source.length) {
        final char = source[i++];
        if (char == '{') depth++;
        if (char == '}') depth--;
      }
      return source.substring(start.end, i - 1);
    }

    for (final fieldName in ['peers', 'pinnedPeers']) {
      test('selects presence, forwarding Request and bond contexts of '
          '$fieldName', () {
        final selection = selectionOf(fieldName);

        expect(selection, matches(RegExp(r'\bpresence\b')));
        expect(selection, matches(RegExp(r'\btemporaryBeaconId\b')));
        expect(
          selection,
          matches(
            RegExp(
              r'\bbondContexts\s*\{[^}]*\bbeaconId\b[^}]*\btitle\b[^}]*\}',
            ),
          ),
        );
      });
    }
  });

  group('trust chain line for people loaded from a field response', () {
    Future<String> lineFor(
      WidgetTester tester,
      Map<String, Object?> response,
      String personId, {
      String locale = 'en',
    }) async {
      final cubit = ConstellationCubit(
        case_: ConstellationStoreFixture(
          _StubRepository(_mapped(response)),
          accountId: 'ego',
        ).store,
        viewer: const Profile(id: 'ego', displayName: 'Ego'),
      );
      await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit, locale: Locale(locale));
      cubit.selectPerson(personId);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('constellation.trust_chain')),
              matching: find.byType(Text),
            ),
          )
          .data!;
    }

    final temporaryField = _fieldResponse(
      peers: [
        _peer(
          'Uann000000001',
          displayName: 'QA779 Ann',
          presence: 'temporary',
          temporaryBeaconId: 'B3bdd82502fb2',
        ),
      ],
    );
    final unnamedTemporaryField = _fieldResponse(
      peers: [
        _peer(
          'Uann000000001',
          presence: 'temporary',
          temporaryBeaconId: 'B3bdd82502fb2',
        ),
      ],
    );
    final pinnedField = _fieldResponse(
      pinnedPeer: _peer(
        'Upia000000001',
        displayName: 'Pia',
        presence: 'pinnedOnly',
      ),
    );
    final requestBondField = _fieldResponse(
      peers: [
        _peer(
          'Ubea000000001',
          displayName: 'Bea',
          presence: 'bond',
          bondContexts: [
            {'beaconId': 'B-shared', 'title': 'Move the piano'},
          ],
        ),
      ],
    );
    final postBondField = _fieldResponse(
      peers: [
        _peer(
          'Ubea000000001',
          displayName: 'Bea',
          presence: 'bond',
          bondContexts: [
            {'beaconId': 'Ppost0000001', 'title': 'Garden notes'},
          ],
        ),
      ],
      posts: [_post('Ppost0000001', 'Garden notes')],
    );
    final nothingKnownField = _fieldResponse(
      peers: [_peer('Unan000000001', displayName: 'Nan')],
    );

    testWidgets('says the person forwarded their Request to the viewer', (
      tester,
    ) async {
      expect(
        await lineFor(tester, temporaryField, 'Uann000000001'),
        'On your field because QA779 Ann forwarded you their Request',
      );
    });

    testWidgets('says someone forwarded their Request when the forwarder has '
        'no name', (tester) async {
      expect(
        await lineFor(tester, unnamedTemporaryField, 'Uann000000001'),
        'On your field because someone forwarded you their Request',
      );
    });

    testWidgets('says the person forwarded their Request, in Russian', (
      tester,
    ) async {
      expect(
        await lineFor(tester, temporaryField, 'Uann000000001', locale: 'ru'),
        'На вашем поле, потому что QA779 Ann переслал(а) вам свой запрос',
      );
    });

    testWidgets('tells a person only the viewer pinned that they pinned them', (
      tester,
    ) async {
      expect(
        await lineFor(tester, pinnedField, 'Upia000000001'),
        'You pinned them to your field',
      );
    });

    testWidgets('tells a person only the viewer pinned that they pinned them, '
        'in Russian', (tester) async {
      expect(
        await lineFor(tester, pinnedField, 'Upia000000001', locale: 'ru'),
        'Вы закрепили этого человека на своём поле',
      );
    });

    testWidgets('tells a pinned-only peer without a placed anchor that '
        'they pinned them', (tester) async {
      expect(
        await lineFor(
          tester,
          _fieldResponse(
            peers: [
              _peer(
                'Upia000000001',
                displayName: 'Pia',
                presence: 'pinnedOnly',
              ),
            ],
          ),
          'Upia000000001',
        ),
        'You pinned them to your field',
      );
    });

    testWidgets('says a pinned person was forwarded when the pinned entry '
        'carries the forwarding Request', (tester) async {
      expect(
        await lineFor(
          tester,
          _fieldResponse(
            pinnedPeer: _peer(
              'Upia000000001',
              displayName: 'Pia',
              presence: 'temporary',
              temporaryBeaconId: 'B3bdd82502fb2',
            ),
          ),
          'Upia000000001',
        ),
        'On your field because Pia forwarded you their Request',
      );
    });

    testWidgets('names the shared Request of a pinned person when the pinned '
        'entry carries bond contexts', (tester) async {
      expect(
        await lineFor(
          tester,
          _fieldResponse(
            pinnedPeer: _peer(
              'Upia000000001',
              displayName: 'Pia',
              presence: 'bond',
              bondContexts: [
                {'beaconId': 'B-shared', 'title': 'Move the piano'},
              ],
            ),
          ),
          'Upia000000001',
        ),
        'On your field because you share the Request “Move the piano”',
      );
    });

    testWidgets('names the Request a bond person shares with the viewer', (
      tester,
    ) async {
      expect(
        await lineFor(tester, requestBondField, 'Ubea000000001'),
        'On your field because you share the Request “Move the piano”',
      );
    });

    testWidgets('names the Request a bond person shares, in Russian', (
      tester,
    ) async {
      expect(
        await lineFor(tester, requestBondField, 'Ubea000000001', locale: 'ru'),
        'На вашем поле, потому что у вас общий запрос «Move the piano»',
      );
    });

    testWidgets('names the Post a bond person shares with the viewer', (
      tester,
    ) async {
      expect(
        await lineFor(tester, postBondField, 'Ubea000000001'),
        'On your field because you share the Post “Garden notes”',
      );
    });

    testWidgets('names the Post a bond person shares, in Russian', (
      tester,
    ) async {
      expect(
        await lineFor(tester, postBondField, 'Ubea000000001', locale: 'ru'),
        'На вашем поле, потому что у вас общий пост «Garden notes»',
      );
    });

    testWidgets('keeps the generic text only when no reason is known', (
      tester,
    ) async {
      expect(
        await lineFor(tester, nothingKnownField, 'Unan000000001'),
        'No chain of trust you can see leads to this person.',
      );
    });

    testWidgets('keeps the generic Russian text only when no reason is known', (
      tester,
    ) async {
      expect(
        await lineFor(tester, nothingKnownField, 'Unan000000001', locale: 'ru'),
        'Ни одна видимая вам цепочка доверия не ведёт к этому человеку.',
      );
    });
  });
}
