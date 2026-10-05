import 'package:ferry/ferry.dart'
    show
        Client,
        FetchPolicy,
        Link,
        NextLink,
        OperationRequest,
        OperationResponse,
        OperationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;

import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';

import '../../support/test_realtime_sync.dart';

/// Records every outgoing request so tests can assert on wire variables.
class _RecordingLink extends Link {
  _RecordingLink(this.response);

  final Response response;

  final requests = <Request>[];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    requests.add(request);
    return Stream.value(response);
  }
}

final class _StubRemoteApiClient extends RemoteApiClient {
  _StubRemoteApiClient(this._client)
    : super(
        apiEndpointUrl: 'http://test/graphql',
        apiEndpointUrlV2: 'http://test/api/v2/graphql',
        authJwtExpiresIn: const Duration(hours: 1),
        requestTimeout: const Duration(minutes: 1),
        userAgent: 'test',
      );

  final Client _client;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => _client.request(request);
}

({BeaconThreadsRepository repo, TestRealtimeSyncPort port}) _repositoryFor(
  Link link,
) {
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  final repo = BeaconThreadsRepository(
    _StubRemoteApiClient(
      Client(
        link: link,
        defaultFetchPolicies: const {
          OperationType.query: FetchPolicy.NoCache,
          OperationType.mutation: FetchPolicy.NoCache,
        },
      ),
    ),
    realtime.port,
  );
  return (repo: repo, port: realtime.port);
}

const _candidateJson =
    '{"id":"Zbaton000001","status":"collecting","viewerRole":"candidate",'
    '"myResponse":"can_help"}';

const _takenAuthorJson =
    '{"id":"Zbaton000001","status":"taken","viewerRole":"author",'
    '"candidates":[{"userId":"Uaaaaaaaaaaa","title":"Alice","tier":1,'
    '"response":"can_help","respondedAt":"2026-10-05T10:00:00.000Z"}],'
    '"allAnswered":true,"eligibleCount":1,'
    '"taker":{"id":"Uaaaaaaaaaaa","title":"Alice"},"selectionMode":"auto"}';

Response _mutationResponse(String field, Object? value) => Response(
  data: {'__typename': 'mutation_root', field: value},
  response: const {},
);

Map<String, dynamic> _roomMessageRow({
  required String id,
  String? batonDataJson,
}) => {
  '__typename': 'v2_RoomMessageRow',
  'id': id,
  'beaconId': 'Bbeacon0000001',
  'authorId': 'Uauthor000001',
  'body': 'who can pick this up?',
  'createdAt': '2026-10-05T10:00:00.000Z',
  'editedAt': null,
  'semanticMarker': null,
  'systemMessageKind': null,
  'linkedBlockerId': null,
  'linkedFactCardId': null,
  'linkedPollingId': null,
  'linkedItemId': null,
  'linkedEventKind': null,
  'linkedItemKind': null,
  'linkedItemStatus': null,
  'linkedItemTitle': null,
  'linkedItemBody': null,
  'linkedItemCreatorId': null,
  'linkedItemTargetPersonId': null,
  'linkedItemCreatedAt': null,
  'linkedItemUpdatedAt': null,
  'linkedItemLinkedMessageId': null,
  'linkedItemResolvedAt': null,
  'pollDataJson': null,
  'batonDataJson': batonDataJson,
  'systemPayloadJson': null,
  'authorTitle': 'Alice',
  'authorHasPicture': false,
  'authorPicHeight': 0,
  'authorPicWidth': 0,
  'authorBlurHash': '',
  'authorImageId': '',
  'reactionsJson': null,
  'myReaction': null,
  'reactorsJson': null,
  'attachmentsJson': '[]',
  'mentions': <String>[],
  'mentionSpansJson': '[]',
  'replyToAuthorId': null,
  'replyToAuthorTitle': null,
  'replyToBodyExcerpt': null,
  'replyToHasAttachments': false,
  'replyToMessageId': null,
  'threadItemId': null,
  'quotedFact': null,
};

void main() {
  group('baton mutations send the wire variables', () {
    test('batonCreate sends messageId and candidates with tiers and maps the '
        'returned payload', () async {
      final link = _RecordingLink(
        _mutationResponse('roomBatonCreate', _takenAuthorJson),
      );
      final repo = _repositoryFor(link).repo;

      final data = await repo.batonCreate(
        messageId: 'Mmessage00001',
        candidates: const [
          (userId: 'Uaaaaaaaaaaa', tier: 1),
          (userId: 'Ubbbbbbbbbbb', tier: 3),
        ],
      );

      final vars = link.requests.single.variables;
      expect(vars['messageId'], 'Mmessage00001');
      expect(vars['candidates'], [
        {'userId': 'Uaaaaaaaaaaa', 'tier': 1},
        {'userId': 'Ubbbbbbbbbbb', 'tier': 3},
      ]);
      expect(data, isA<RoomBatonAuthorData>());
      expect(data!.id, 'Zbaton000001');
    });

    test('batonCreate maps a null payload to null', () async {
      final link = _RecordingLink(_mutationResponse('roomBatonCreate', null));
      final repo = _repositoryFor(link).repo;

      final data = await repo.batonCreate(
        messageId: 'Mmessage00001',
        candidates: const [(userId: 'Uaaaaaaaaaaa', tier: 1)],
      );

      expect(data, isNull);
    });

    test(
      'batonRespond sends batonId and canHelp and maps the payload',
      () async {
        final link = _RecordingLink(
          _mutationResponse('roomBatonRespond', _candidateJson),
        );
        final repo = _repositoryFor(link).repo;

        final data = await repo.batonRespond(
          batonId: 'Zbaton000001',
          canHelp: true,
        );

        final vars = link.requests.single.variables;
        expect(vars['batonId'], 'Zbaton000001');
        expect(vars['canHelp'], true);
        expect(data, isA<RoomBatonCandidateData>());
        expect(
          (data! as RoomBatonCandidateData).myResponse,
          RoomBatonResponse.canHelp,
        );
      },
    );

    test('batonRespond forwards a negative answer', () async {
      final link = _RecordingLink(
        _mutationResponse('roomBatonRespond', _candidateJson),
      );
      final repo = _repositoryFor(link).repo;

      await repo.batonRespond(batonId: 'Zbaton000001', canHelp: false);

      expect(link.requests.single.variables['canHelp'], false);
    });

    test('batonSelect with a user sends that userId', () async {
      final link = _RecordingLink(
        _mutationResponse('roomBatonSelect', _takenAuthorJson),
      );
      final repo = _repositoryFor(link).repo;

      final data = await repo.batonSelect(
        batonId: 'Zbaton000001',
        userId: 'Uaaaaaaaaaaa',
      );

      final vars = link.requests.single.variables;
      expect(vars['batonId'], 'Zbaton000001');
      expect(vars['userId'], 'Uaaaaaaaaaaa');
      expect((data! as RoomBatonAuthorData).taker?.id, 'Uaaaaaaaaaaa');
    });

    test('batonSelect without a user asks the server to pick for the '
        'author', () async {
      final link = _RecordingLink(
        _mutationResponse('roomBatonSelect', _takenAuthorJson),
      );
      final repo = _repositoryFor(link).repo;

      await repo.batonSelect(batonId: 'Zbaton000001');

      final vars = link.requests.single.variables;
      expect(vars['batonId'], 'Zbaton000001');
      expect(vars['userId'], isNull);
    });

    test('batonCancel sends batonId and returns the server flag', () async {
      final link = _RecordingLink(_mutationResponse('roomBatonCancel', true));
      final repo = _repositoryFor(link).repo;

      final ok = await repo.batonCancel(batonId: 'Zbaton000001');

      expect(link.requests.single.variables['batonId'], 'Zbaton000001');
      expect(ok, isTrue);
    });
  });

  group('fetchMessages maps batonDataJson', () {
    test('onto RoomMessage.baton, and a row without it to null', () async {
      final link = _RecordingLink(
        Response(
          data: {
            '__typename': 'query_root',
            'RoomMessageList': [
              _roomMessageRow(
                id: 'Mbaton0000001',
                batonDataJson: _candidateJson,
              ),
              _roomMessageRow(id: 'Mplain0000001'),
            ],
          },
          response: const {},
        ),
      );
      final repo = _repositoryFor(link).repo;

      final messages = await repo.fetchMessages(beaconId: 'Bbeacon0000001');

      expect(messages.map((m) => m.id), ['Mbaton0000001', 'Mplain0000001']);
      final RoomBatonData? baton = messages.first.baton;
      expect(baton, isA<RoomBatonCandidateData>());
      expect(baton!.id, 'Zbaton000001');
      expect(messages.last.baton, isNull);
    });

    test(
      'malformed batonDataJson degrades to a message without a baton',
      () async {
        final link = _RecordingLink(
          Response(
            data: {
              '__typename': 'query_root',
              'RoomMessageList': [
                _roomMessageRow(id: 'Mbroken000001', batonDataJson: '{"id":'),
              ],
            },
            response: const {},
          ),
        );
        final repo = _repositoryFor(link).repo;

        final messages = await repo.fetchMessages(beaconId: 'Bbeacon0000001');

        expect(messages.single.baton, isNull);
      },
    );

    test('RoomMessage defaults to no baton', () {
      final message = RoomMessage(
        id: 'M1',
        beaconId: 'B1',
        authorId: 'U1',
        body: '',
        createdAt: DateTime.utc(2026, 10, 5),
      );

      expect(message.baton, isNull);
    });
  });

  group('room_baton realtime invalidation', () {
    test('a room_baton change surfaces on beaconRoomInvalidations', () async {
      final link = _RecordingLink(_mutationResponse('roomBatonCancel', true));
      final built = _repositoryFor(link);
      final received = <BeaconRoomInvalidation>[];
      final sub = built.repo.beaconRoomInvalidations.listen(received.add);
      addTearDown(sub.cancel);

      built.port.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.roomBaton,
          aggregateId: 'Bbeacon0000001',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, [
        const BeaconRoomInvalidation(
          beaconId: 'Bbeacon0000001',
          entityType: BeaconRoomEntityType.roomBaton,
          operation: RealtimeOperation.update,
        ),
      ]);
    });
  });
}
