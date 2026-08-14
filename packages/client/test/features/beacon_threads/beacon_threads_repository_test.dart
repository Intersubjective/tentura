import 'package:ferry/ferry.dart'
    show Client, DataSource, FetchPolicy, Link, NextLink, OperationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;

import 'package:tentura/data/service/remote_api_service.dart'
    show ErrorHandler;
import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_threads_list.data.gql.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_threads_list.req.gql.dart';
import 'package:tentura/features/beacon_threads/data/model/request_thread_model.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

class _FakeLink extends Link {
  _FakeLink(this.response);

  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(response);
}

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
    expect(rows.last.item?.title, 'Need review');
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
}
