import 'package:ferry/ferry.dart'
    show
        Client,
        DataSource,
        FetchPolicy,
        Link,
        NextLink,
        OperationRequest,
        OperationResponse,
        OperationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;

import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/data/service/remote_api_service.dart'
    show ErrorHandler;
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_threads_list.data.gql.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_threads_list.req.gql.dart';
import 'package:tentura/features/beacon_threads/data/model/request_thread_model.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

import '../../support/test_realtime_sync.dart';

class _FakeLink extends Link {
  _FakeLink(this.response);

  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(response);
}

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
  ]) =>
      _client.request(request);
}

BeaconThreadsRepository _repositoryFor(Link link) {
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  return BeaconThreadsRepository(
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
}

Map<String, dynamic> _roomMessageRow({
  required String id,
  required String createdAt,
  Map<String, dynamic>? quotedFact,
}) => {
  '__typename': 'v2_RoomMessageRow',
  'id': id,
  'beaconId': 'Bbeacon0000001',
  'authorId': 'Uauthor000001',
  'body': 'see the fact',
  'createdAt': createdAt,
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
  'quotedFact': quotedFact,
};

List<RequestThread> _mapThreadsResponse(GBeaconThreadsListData data) {
  final rows = data.beaconThreads?.toList() ?? const [];
  return rows.map((row) => RequestThreadRowModel(row).toEntity()).toList();
}

void main() {
  test('BeaconThreadsList fetch+map returns domain RequestThread rows', () async {
    const beaconId = 'Bbeacon0000001';
    final client = Client(
      link: _FakeLink(
        const Response(
          data: {
            '__typename': 'query_root',
            'beaconThreads': [
              {
                '__typename': 'v2_BeaconThreadRow',
                'threadId': RequestThread.generalId,
                'threadKind': 'general',
                'unreadCount': 1,
                'messageCount': 9,
                'lastSeenAt': '2026-08-14T10:00:00.000Z',
                'lastMessageAt': '2026-08-14T11:00:00.000Z',
                'lastMessageAuthorId': 'Uauthor000001',
                'lastMessagePreview': {
                  '__typename': 'v2_ThreadMessagePreview',
                  'kind': 0,
                  'excerpt': 'hello',
                  'hasAttachment': false,
                  'joinedUserId': null,
                  'admissionReason': null,
                  'linkedItemId': null,
                  'linkedEventKind': null,
                  'itemKind': null,
                  'itemTitle': null,
                  'pollTitle': null,
                  'factTitle': null,
                  'factVisibility': null,
                },
                'item': null,
              },
              {
                '__typename': 'v2_BeaconThreadRow',
                'threadId': 'item-ask',
                'threadKind': 'ask',
                'unreadCount': 2,
                'messageCount': 3,
                'lastSeenAt': '2026-08-14T09:00:00.000Z',
                'lastMessageAt': '2026-08-14T09:30:00.000Z',
                'lastMessageAuthorId': 'Uauthor000002',
                'lastMessagePreview': null,
                'item': {
                  '__typename': 'v2_CoordinationItemRow',
                  'id': 'item-ask',
                  'beaconId': beaconId,
                  'kind': 2,
                  'status': 0,
                  'source': 1,
                  'published': true,
                  'title': 'Need review',
                  'body': '',
                  'creatorId': 'Ucreator00001',
                  'targetPersonId': 'Utarget000001',
                  'acceptedById': null,
                  'targetItemId': null,
                  'targetMessageId': null,
                  'linkedMessageId': null,
                  'linkedParentItemId': null,
                  'ordering': 0,
                  'createdAt': '2026-08-01T00:00:00.000Z',
                  'updatedAt': '2026-08-02T00:00:00.000Z',
                  'resolvedAt': null,
                  'cancelledAt': null,
                  'staleAt': null,
                  'lastRemindedAt': null,
                  'staleAfterDays': 3,
                  'messageCount': 3,
                  'unreadCount': 2,
                  'lastSeenAt': '2026-08-14T09:00:00.000Z',
                },
              },
            ],
          },
          response: {},
        ),
      ),
      defaultFetchPolicies: const {
        OperationType.query: FetchPolicy.NoCache,
      },
    );

    final request = GBeaconThreadsListReq((b) => b.vars.beaconId = beaconId);
    expect(request.vars.beaconId, beaconId);

    final response = await client
        .request(request)
        .firstWhere((e) => e.dataSource == DataSource.Link);

    final rows = _mapThreadsResponse(response.dataOrThrow(label: 'test'));

    expect(rows, hasLength(2));
    expect(rows.first.threadId, RequestThread.generalId);
    expect(rows.first.isGeneral, isTrue);
    expect(rows.first.lastMessagePreview?.excerpt, 'hello');
    expect(rows.last.threadId, 'item-ask');
    expect(rows.last.kind, RequestThreadKind.ask);
    expect(rows.last.item, isNull);
  });

  test('BeaconThreadsList maps null server list to empty list', () async {
    final client = Client(
      link: _FakeLink(
        const Response(
          data: {
            '__typename': 'query_root',
            'beaconThreads': null,
          },
          response: {},
        ),
      ),
      defaultFetchPolicies: const {
        OperationType.query: FetchPolicy.NoCache,
      },
    );

    final response = await client
        .request(GBeaconThreadsListReq((b) => b.vars.beaconId = 'Bbeacon0000001'))
        .firstWhere((e) => e.dataSource == DataSource.Link);

    expect(_mapThreadsResponse(response.dataOrThrow(label: 'test')), isEmpty);
  });

  // Issue #181 plan §8.11 / §14.2: V2 RoomMessageList rows carry the quoted
  // fact snapshot; RoomMessageCreate takes the quote ids as a pair.
  group('quoted facts (issue #181)', () {
    test('fetchMessages maps quotedFact onto RoomMessage.quotedFact and a '
        'row without it to null', () async {
      final repo = _repositoryFor(
        _FakeLink(
          Response(
            data: {
              '__typename': 'query_root',
              'RoomMessageList': [
                _roomMessageRow(
                  id: 'Mquoted000001',
                  createdAt: '2026-08-14T10:00:00.000Z',
                  quotedFact: {
                    '__typename': 'v2_RoomMessageQuotedFact',
                    'factCardId': 'Ffact00000001',
                    'seq': 2,
                    'text': 'Meet at the station at 9',
                    'pinnedById': 'Upinner000001',
                    'pinnedByTitle': 'Bob',
                    'visibility': 1,
                    'status': 1,
                    'currentSeq': 5,
                    'attachmentsJson':
                        '[{"id":"att-1","kind":2,"position":0,'
                        '"mime":"application/pdf","sizeBytes":2048,'
                        '"fileName":"map.pdf"}]',
                  },
                ),
                _roomMessageRow(
                  id: 'Mplain000001',
                  createdAt: '2026-08-14T11:00:00.000Z',
                ),
              ],
            },
            response: const {},
          ),
        ),
      );

      final messages = await repo.fetchMessages(beaconId: 'Bbeacon0000001');

      expect(messages.map((m) => m.id), ['Mquoted000001', 'Mplain000001']);

      final QuotedFact? quote = messages.first.quotedFact;
      expect(quote, isNotNull);
      expect(quote!.factCardId, 'Ffact00000001');
      expect(quote.seq, 2);
      expect(quote.currentSeq, 5);
      expect(quote.status, 1);
      expect(quote.factText, 'Meet at the station at 9');
      expect(quote.pinnedById, 'Upinner000001');
      expect(quote.pinnedByTitle, 'Bob');
      expect(quote.visibility, 1);
      expect(quote.attachments, hasLength(1));
      expect(quote.attachments.single.id, 'att-1');
      expect(quote.attachments.single.kind, 2);
      expect(quote.attachments.single.mime, 'application/pdf');
      expect(quote.attachments.single.sizeBytes, 2048);
      expect(quote.attachments.single.fileName, 'map.pdf');
      expect(quote.isChangedSinceQuoted, isTrue);

      expect(messages.last.quotedFact, isNull);
    });

    Response createResponse() => const Response(
      data: {
        '__typename': 'mutation_root',
        'RoomMessageCreate': {
          '__typename': 'v2_RoomMessageCreatePayload',
          'id': 'Mcreated00001',
        },
      },
      response: {},
    );

    test('createMessage sends quotedFactCardId + quotedFactRevisionSeq when '
        'given', () async {
      final link = _RecordingLink(createResponse());
      final repo = _repositoryFor(link);

      final id = await repo.createMessage(
        beaconId: 'Bbeacon0000001',
        body: 'about this fact',
        quotedFactCardId: 'Ffact00000001',
        quotedFactRevisionSeq: 3,
      );

      expect(id, 'Mcreated00001');
      final vars = link.requests.single.variables;
      expect(vars['quotedFactCardId'], 'Ffact00000001');
      expect(vars['quotedFactRevisionSeq'], 3);
    });

    test('createMessage omits both quote variables when not given', () async {
      final link = _RecordingLink(createResponse());
      final repo = _repositoryFor(link);

      await repo.createMessage(beaconId: 'Bbeacon0000001', body: 'hello');

      final vars = link.requests.single.variables;
      expect(vars.containsKey('quotedFactCardId'), isFalse);
      expect(vars.containsKey('quotedFactRevisionSeq'), isFalse);
    });
  });
}
