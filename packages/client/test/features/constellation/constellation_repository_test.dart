import 'dart:io';

import 'package:ferry/ferry.dart'
    show Client, DataSource, FetchPolicy, Link, NextLink, OperationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;
import 'package:logging/logging.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.req.gql.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
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
  Future<ConstellationField> fetch() async => field;
}

void main() {
  group('ConstellationRepository', () {
    test('maps constellationField payload to domain entities', () async {
      final client = Client(
        link: _FakeLink(
          const Response(
            data: {
              '__typename': 'query_root',
              'constellationField': {
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
                    'tier': 1,
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
                    'coverThumb': null,
                  },
                ],
              },
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: _fetchPolicies,
      );

      final response = await client
          .request(GConstellationFieldFetchReq())
          .firstWhere((event) => event.dataSource == DataSource.Link);
      final field = ConstellationRepository.mapConstellationField(
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

    test('rejects edge tier outside {1,2}', () async {
      final client = Client(
        link: _FakeLink(
          const Response(
            data: {
              '__typename': 'query_root',
              'constellationField': {
                '__typename': 'v2_ConstellationField',
                'loadedAt': '2026-09-09T12:00:00.000Z',
                'context': '',
                'peersCapped': false,
                'requestsCapped': false,
                'peers': [],
                'requests': [],
                'edges': [
                  {
                    '__typename': 'v2_ConstellationEdge',
                    'src': 'ego',
                    'dst': 'peer-a',
                    'tier': 3,
                  },
                ],
              },
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: _fetchPolicies,
      );

      final response = await client
          .request(GConstellationFieldFetchReq())
          .firstWhere((event) => event.dataSource == DataSource.Link);

      expect(
        () => ConstellationRepository.mapConstellationField(
          response.dataOrThrow(label: 'test').constellationField,
        ),
        throwsA(isA<FormatException>()),
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
