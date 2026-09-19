import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_surface_summary.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_surface_summary.req.gql.dart';

void main() {
  final remote = _FixtureRemoteClient();
  final repository = AttentionRepository(remote);
  final logRecords = <LogRecord>[];
  final sub = Logger('AttentionRepository').onRecord.listen(logRecords.add);

  tearDown(() {
    logRecords.clear();
    remote.reset();
  });

  tearDownAll(() => sub.cancel());

  test('maps surface, itemKind, forward fields and enums from wire JSON', () async {
    remote.feedData = _feedData([
      _wireReceipt(
        surface: 'myWork',
        itemKind: 'forward',
        forwardOutcome: 'helping',
        forwardCount: 3,
      ),
    ]);
    final feed = await repository.fetch(
      view: AttentionView.all,
      surface: AttentionSurface.myWork,
    );
    final receipt = feed.page.items.single;
    expect(receipt.surface, AttentionSurface.myWork);
    expect(receipt.itemKind, AttentionItemKind.forward);
    expect(receipt.forwardOutcome, AttentionForwardOutcome.helping);
    expect(receipt.forwardCount, 3);
  });

  test('maps watchingDigest itemKind and digestCount', () async {
    remote.feedData = _feedData([
      _wireReceipt(
        surface: 'activity',
        itemKind: 'watchingDigest',
        digestCount: 4,
      ),
    ]);
    final receipt = (await repository.fetch(view: AttentionView.all))
        .page
        .items
        .single;
    expect(receipt.itemKind, AttentionItemKind.watchingDigest);
    expect(receipt.digestCount, 4);
  });

  test('unknown itemKind wire value maps to receipt and logs', () async {
    remote.feedData = _feedData([
      _wireReceipt(surface: 'activity', itemKind: 'futureKind'),
    ]);
    final receipt = (await repository.fetch(view: AttentionView.all))
        .page
        .items
        .single;
    expect(receipt.itemKind, AttentionItemKind.receipt);
    expect(
      logRecords.any((r) => r.message.contains('unknown itemKind wire value')),
      isTrue,
    );
  });

  test('unknown surface wire value maps to activity and logs', () async {
    remote.feedData = _feedData([
      _wireReceipt(surface: 'futureSurface', itemKind: 'receipt'),
    ]);
    final receipt = (await repository.fetch(view: AttentionView.all))
        .page
        .items
        .single;
    expect(receipt.surface, AttentionSurface.activity);
    expect(
      logRecords.any((r) => r.message.contains('unknown surface wire value')),
      isTrue,
    );
  });

  test('surfaceSummary throws when the network layer fails', () async {
    remote.surfaceSummaryError = StateError('offline');
    await expectLater(repository.surfaceSummary(), throwsA(isA<StateError>()));
  });

  test('surfaceSummary returns the legacy totals and all four §6 indicators',
      () async {
    // CHANGES IN U15R-d: §6 names four indicator rules and none of the three
    // totals is any of them. `myDeskDot` and `forYouDot` are non-nullable on
    // the wire, so the fixture has to carry them — which is the point: a
    // client that silently defaulted them would be back to inferring a dot
    // from a total.
    // CHANGES IN U15R-e: `myDeskCount` completes the set, and carries a value
    // different from `needsYouTotal` so a relay that mixed the two up here
    // cannot pass.
    remote.surfaceSummaryData = GAttentionSurfaceSummaryData.fromJson({
      '__typename': 'query_root',
      'attentionSurfaceSummary': {
        '__typename': 'AttentionSurfaceSummary',
        'activityUnreadTotal': 2,
        'myWorkUnreadTotal': 5,
        'needsYouTotal': 1,
        'myDeskDot': false,
        'forYouDot': true,
        'myDeskCount': 4,
      },
    });
    final summary = await repository.surfaceSummary();
    expect(summary.activityUnreadTotal, 2);
    expect(summary.myWorkUnreadTotal, 5);
    expect(summary.needsYouTotal, 1);
    expect(
      summary.myDeskDot,
      isFalse,
      reason: 'a myWorkUnreadTotal of 5 does not make the §6 dot true',
    );
    expect(summary.forYouDot, isTrue);
    expect(
      summary.myDeskCount,
      4,
      reason: '§6 `my desk.count` is its own field, not `needsYouTotal` (1)',
    );
  });
}

GAttentionFeedData _feedData(List<Map<String, dynamic>> items) =>
    GAttentionFeedData.fromJson({
      '__typename': 'query_root',
      'attentionFeed': {
        '__typename': 'AttentionFeed',
        'summary': {
          '__typename': 'AttentionSummary',
          'unreadTotal': items.length,
          'needsYouTotal': 0,
        },
        'page': {
          '__typename': 'AttentionPage',
          'nextCursor': null,
          'items': items,
        },
      },
    })!;

Map<String, dynamic> _wireReceipt({
  required String surface,
  required String itemKind,
  String? forwardOutcome,
  int? forwardCount,
  int? digestCount,
}) => {
  '__typename': 'AttentionReceipt',
  'id': 'Nsurface000001',
  'category': 'connections',
  'kind': 'inviteAccepted',
  'priority': 'normal',
  'title': 'Title',
  'body': 'Body',
  'actionUrl': '/#/',
  'createdAt': '2026-07-24T12:00:00.000Z',
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': null,
  'coordinationItemId': null,
  'actorUserId': null,
  'sourceEventKey': null,
  'destinationKind': null,
  'targetEntityId': null,
  'presentationKey': null,
  'presentationPayloadJson': '{}',
  'inAppPreferenceClass': null,
  'requiresAction': false,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'surface': surface,
  'itemKind': itemKind,
  'forwardOutcome': forwardOutcome,
  'forwardCount': forwardCount,
  'digestCount': digestCount,
};

final class _FixtureRemoteClient implements RemoteRequestClient {
  GAttentionFeedData? feedData;
  GAttentionSurfaceSummaryData? surfaceSummaryData;
  Object? surfaceSummaryError;

  void reset() {
    feedData = null;
    surfaceSummaryData = null;
    surfaceSummaryError = null;
  }

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    if (request is GAttentionFeedReq) {
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          dataSource: DataSource.Link,
          data: feedData as TData,
        ),
      );
    }
    if (request is GAttentionSurfaceSummaryReq) {
      if (surfaceSummaryError != null) {
        return Stream.error(surfaceSummaryError!);
      }
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          dataSource: DataSource.Link,
          data: surfaceSummaryData as TData,
        ),
      );
    }
    throw UnsupportedError('Unexpected operation: $request');
  }
}
