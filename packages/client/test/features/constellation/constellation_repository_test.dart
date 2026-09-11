import 'dart:io';

import 'package:ferry/ferry.dart'
    show Client, DataSource, FetchPolicy, Link, NextLink, OperationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;
import 'package:logging/logging.dart';
import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_anchors_fetch.req.gql.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.req.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';

class _FakeLink extends Link {
  _FakeLink(this.response);

  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(response);
}

const _fetchPolicies = {
  OperationType.query: FetchPolicy.NoCache,
  OperationType.mutation: FetchPolicy.NoCache,
};

final _forbiddenWirePattern = RegExp(
  r'score|weight|_mr$|meritrank|rank',
  caseSensitive: false,
);

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      field;
}

Map<String, Object?> _fieldPayload({
  bool includeAnchorProjection = false,
  int edgeTier = 1,
}) => {
      '__typename': 'v2_ConstellationField',
      'loadedAt': '2026-09-09T12:00:00.000Z',
      'context': '',
      'peersCapped': true,
      'requestsCapped': false,
      'peers': [
        {
          '__typename': 'v2_ConstellationPeer',
          'id': 'peer-a',
          'displayName': 'Alice',
          'handle': '@alice',
          'image': {
            '__typename': 'v2_image',
            'id': 'img-1',
            'hash': 'hash-1',
            'height': 100,
            'width': 200,
            'author_id': 'peer-a',
            'created_at': '2026-09-01',
          },
        },
      ],
      'edges': [
        {
          '__typename': 'v2_ConstellationEdge',
          'src': 'ego',
          'dst': 'peer-a',
          'tier': edgeTier,
        },
      ],
      'requests': [
        {
          '__typename': 'v2_ConstellationRequest',
          'id': 'req-1',
          'authorId': 'peer-a',
          'title': 'Need a drill',
          'status': 0,
          'needs': ['tools'],
          'primaryNeedSlug': 'tools',
          'startAt': '2026-09-10T10:00:00.000Z',
          'endAt': null,
          'addressLabel': 'Workshop',
          'hasCoordinates': true,
          'isMine': false,
          'viewerHasActiveHelpOffer': true,
          'viewerIsRoomParticipant': false,
          'viewerHasForwardEdge': false,
          'helpOfferCount': 2,
          'coverSource': 0,
          'coverThumb': null,
        },
      ],
      if (includeAnchorProjection)
        'anchorProjection': {
          '__typename': 'v2_ConstellationAnchorProjection',
          'revision': '9007199254740993',
          'anchors': [
            {
              '__typename': 'v2_ConstellationAnchor',
              'targetKind': 'PERSON',
              'targetId': 'peer-a',
              'xUnits': 1.5,
              'yUnits': -2.25,
              'coordinateSpaceVersion': 1,
              'revision': '9007199254740993',
              'placedAt': '2026-09-09T11:00:00.000Z',
            },
          ],
          'pinnedPeers': [],
          'pinnedRequests': [],
          'supportPeers': [],
          'supportEdges': [],
          'serverFilteredBeaconIds': ['B_hidden'],
          'serverFilteredBeaconCount': 1,
        }
      else
        'anchorProjection': {
          '__typename': 'v2_ConstellationAnchorProjection',
          'revision': '0',
          'anchors': [],
          'pinnedPeers': [],
          'pinnedRequests': [],
          'supportPeers': [],
          'supportEdges': [],
          'serverFilteredBeaconIds': [],
          'serverFilteredBeaconCount': 0,
        },
    };

void main() {
  group('ConstellationRepository mapping', () {
    test('maps constellationField payload to domain entities', () async {
      final client = Client(
        link: _FakeLink(
          Response(
            data: {
              '__typename': 'query_root',
              'constellationField': _fieldPayload(),
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: _fetchPolicies,
      );

      final response = await client
          .request(
            GConstellationFieldFetchReq((b) {
              b.vars
                ..showClosed = false
                ..participatedOnly = false
                ..projection = Gv2_ConstellationProjection.FULL;
            }),
          )
          .firstWhere((event) => event.dataSource == DataSource.Link);
      final field = mapConstellationFieldFromFieldFetch(
        response.dataOrThrow(label: 'test').constellationField,
      );

      expect(field.loadedAt, DateTime.utc(2026, 9, 9, 12));
      expect(field.context, '');
      expect(field.peersCapped, isTrue);
      expect(field.requestsCapped, isFalse);
      expect(field.peers, hasLength(1));
      expect(field.peers.single.id, 'peer-a');
      expect(field.peers.single.displayName, 'Alice');
      expect(field.peers.single.handle, '@alice');
      expect(field.peers.single.image?.id, 'img-1');
      expect(field.edges.single.tier, 1);
      expect(field.requests.single.title, 'Need a drill');
      expect(field.requests.single.needs, ['tools']);
      expect(field.requests.single.startAt, DateTime.utc(2026, 9, 10, 10));
      expect(field.requests.single.heldState, ConstellationHeldState.offered);
    });

    test('maps anchorProjection with precise revision and coordinates', () async {
      final client = Client(
        link: _FakeLink(
          Response(
            data: {
              '__typename': 'query_root',
              'constellationField': _fieldPayload(includeAnchorProjection: true),
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: _fetchPolicies,
      );

      final response = await client
          .request(
            GConstellationFieldFetchReq((b) {
              b.vars
                ..showClosed = false
                ..participatedOnly = false
                ..projection = Gv2_ConstellationProjection.FULL;
            }),
          )
          .firstWhere((event) => event.dataSource == DataSource.Link);
      final field = mapConstellationFieldFromFieldFetch(
        response.dataOrThrow(label: 'test').constellationField,
      );

      final projection = field.anchorProjection!;
      expect(
        projection.revision.value,
        BigInt.parse('9007199254740993'),
      );
      expect(projection.anchors, hasLength(1));
      final anchor = projection.anchors.single;
      expect(anchor.target, const ConstellationAnchorPersonTarget('peer-a'));
      expect(anchor.position.xUnits, 1.5);
      expect(anchor.position.yUnits, -2.25);
      expect(anchor.revision.value, BigInt.parse('9007199254740993'));
      expect(projection.serverFilteredBeaconIds, ['B_hidden']);
      expect(projection.serverFilteredBeaconCount, 1);
    });

    test('rejects edge tier outside {1,2}', () async {
      final client = Client(
        link: _FakeLink(
          Response(
            data: {
              '__typename': 'query_root',
              'constellationField': _fieldPayload(edgeTier: 3),
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: _fetchPolicies,
      );

      final response = await client
          .request(
            GConstellationFieldFetchReq((b) {
              b.vars
                ..showClosed = false
                ..participatedOnly = false
                ..projection = Gv2_ConstellationProjection.FULL;
            }),
          )
          .firstWhere((event) => event.dataSource == DataSource.Link);

      expect(
        () => mapConstellationFieldFromFieldFetch(
          response.dataOrThrow(label: 'test').constellationField,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed anchor revision', () {
      expect(
        () => mapWireAnchor(
          targetKind: Gv2_ConstellationAnchorTargetKind.PERSON,
          targetId: 'peer-a',
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
          revision: '12abc',
          placedAt: '2026-09-09T11:00:00.000Z',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed anchor coordinates without clamping', () {
      expect(
        () => mapWireAnchor(
          targetKind: Gv2_ConstellationAnchorTargetKind.PERSON,
          targetId: 'peer-a',
          xUnits: 11,
          yUnits: 0,
          coordinateSpaceVersion: 1,
          revision: '1',
          placedAt: '2026-09-09T11:00:00.000Z',
        ),
        throwsA(isA<FormatException>()),
      );
    });

  });

  group('request routing', () {
    test('FULL fetch carries filters and projection on ConstellationFieldFetch',
        () {
      final req = GConstellationFieldFetchReq((b) {
        b.vars
          ..showClosed = true
          ..participatedOnly = true
          ..projection = Gv2_ConstellationProjection.FULL;
      });

      expect(req.operation.operationName, 'ConstellationFieldFetch');
      expect(req.vars.showClosed, isTrue);
      expect(req.vars.participatedOnly, isTrue);
      expect(req.vars.projection, Gv2_ConstellationProjection.FULL);
      expect(
        req.execRequest.variables,
        containsPair('showClosed', true),
      );
      expect(
        req.execRequest.variables,
        containsPair('participatedOnly', true),
      );
      expect(
        req.execRequest.variables['projection'],
        'FULL',
      );
    });

    test('ANCHORS fetch uses ConstellationAnchorsFetch with filters only', () {
      final req = GConstellationAnchorsFetchReq((b) {
        b.vars
          ..showClosed = true
          ..participatedOnly = false;
      });

      expect(req.operation.operationName, 'ConstellationAnchorsFetch');
      expect(req.vars.showClosed, isTrue);
      expect(req.vars.participatedOnly, isFalse);
      expect(req.execRequest.variables.keys, containsAll(['showClosed', 'participatedOnly']));
      expect(req.execRequest.variables.keys, isNot(contains('projection')));
    });

    test('projectionToWire maps domain enums to stitched values', () {
      expect(
        projectionToWire(ConstellationProjection.full),
        Gv2_ConstellationProjection.FULL,
      );
      expect(
        projectionToWire(ConstellationProjection.anchors),
        Gv2_ConstellationProjection.ANCHORS,
      );
    });
  });

  group('wire hygiene', () {
    test('operation document selects no forbidden score-shaped fields', () {
      final source = File(
        'lib/features/constellation/data/gql/constellation_field_fetch.graphql',
      ).readAsStringSync();

      expect(_forbiddenWirePattern.hasMatch(source), isFalse);
    });

    test('domain entities expose no score-shaped members', () {
      final entityMembers = <String>{
        ..._recordMembers<ConstellationField>(),
        ..._recordMembers<ConstellationPerson>(),
        ..._recordMembers<ConstellationTrustEdgeEntity>(),
        ..._recordMembers<ConstellationRequest>(),
      };

      for (final member in entityMembers) {
        expect(_forbiddenWirePattern.hasMatch(member), isFalse);
      }
    });
  });

  group('ConstellationFieldCase holderIds', () {
    test('holderIds follow returned request authors plus ego', () async {
      const ego = 'ego';
      const authorA = 'author-a';
      const profileOnlyPeer = 'peer-b';

      final case_ = ConstellationFieldCase(
        _StubRepository(
          ConstellationField(
            loadedAt: DateTime.utc(2026, 9, 9),
            context: '',
            peers: [
              ConstellationPerson(id: authorA),
              ConstellationPerson(id: profileOnlyPeer),
            ],
            edges: [
              ConstellationTrustEdgeEntity(
                src: ego,
                dst: authorA,
                tier: 1,
              ),
            ],
            requests: [
              ConstellationRequest(
                id: 'req-1',
                authorId: authorA,
                title: 'First',
                status: 0,
              ),
              ConstellationRequest(
                id: 'req-2',
                authorId: authorA,
                title: 'Second',
                status: 0,
              ),
              ConstellationRequest(
                id: 'req-3',
                authorId: ego,
                title: 'Mine',
                status: 0,
                isMine: true,
              ),
            ],
          ),
        ),
        env: const Env.fromEnvironment(),
        logger: Logger('ConstellationFieldCaseTest'),
      );

      final result = await case_.load(viewerId: ego);

      expect(result.paths.attributed, contains(authorA));
      expect(result.paths.attributed, isNot(contains(ego)));
      expect(result.paths.ring, isNot(contains(profileOnlyPeer)));
    });
  });
}

Set<String> _recordMembers<T>() {
  final mirror = _TypeMembers<T>();
  return mirror.members;
}

class _TypeMembers<T> {
  _TypeMembers() {
    if (T == ConstellationField) {
      members.addAll(const [
        'loadedAt',
        'context',
        'peers',
        'edges',
        'requests',
        'peersCapped',
        'requestsCapped',
      ]);
      return;
    }
    if (T == ConstellationPerson) {
      members.addAll(const ['id', 'displayName', 'handle', 'image']);
      return;
    }
    if (T == ConstellationTrustEdgeEntity) {
      members.addAll(const ['src', 'dst', 'tier']);
      return;
    }
    if (T == ConstellationRequest) {
      members.addAll(const [
        'id',
        'authorId',
        'title',
        'status',
        'needs',
        'primaryNeedSlug',
        'startAt',
        'endAt',
        'addressLabel',
        'hasCoordinates',
        'isMine',
        'viewerHasActiveHelpOffer',
        'viewerIsRoomParticipant',
        'viewerHasForwardEdge',
        'helpOfferCount',
        'coverThumb',
        'heldState',
      ]);
    }
  }

  final Set<String> members = {};
}
