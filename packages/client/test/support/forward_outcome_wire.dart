// The server's forward (outcome) stream row on the wire, and the real client
// mapper that turns an `attentionFeed` page into receipts.
//
// The server half of the forward-outcome unread tick encodes the tick on the
// existing forward row (`docs/contracts/attention-active-attention-axis.json`
// § forwardOutcomeTick): `seenAt` is null exactly while a relabel by somebody
// else is unseen, otherwise it is the row's `latest_forward_at`; `createdAt`
// is `GREATEST(entry_at, outcome_changed_at)`. Tests build that row here and
// map it through the production `AttentionRepository`, so no test hand-builds
// the receipt the Activity row is drawn from.

import 'dart:async';

import 'package:ferry/ferry.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.req.gql.dart';

/// One stream row as the `attentionFeed` query returns it. Every field of
/// `AttentionReceiptFields` is present, as the server sends it.
Map<String, dynamic> attentionStreamRowWire({
  required String id,
  required String itemKind,
  required String beaconId,
  required String createdAt,
  String? seenAt,
  String? forwardOutcome,
  String kind = 'roomActivityLowPriority',
  String title = 'Book swap Sunday',
  String? beaconTitle,
  String presentationPayloadJson = '{}',
  int? eventTotal,
  int? eventUnseenCount,
  int? forwardCount,
  String? actorUserId,
  List<Map<String, dynamic>> eventsPreview = const [],
}) => {
  '__typename': 'v2_AttentionReceipt',
  'id': id,
  'category': 'requestProgress',
  'kind': kind,
  'priority': 'normal',
  'title': title,
  'body': '',
  'actionUrl': '/#/beacon/view/$beaconId',
  'createdAt': createdAt,
  'seenAt': seenAt,
  'collapsedCount': 1,
  'beaconId': beaconId,
  'coordinationItemId': null,
  'actorUserId': actorUserId,
  'sourceEventKey': null,
  'destinationKind': 'beacon',
  'targetEntityId': beaconId,
  'presentationKey': null,
  'presentationPayloadJson': presentationPayloadJson,
  'inAppPreferenceClass': null,
  'requiresAction': false,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'clearedAt': null,
  'clearReason': null,
  'historyLifecycleEligible': true,
  'surface': 'activity',
  'itemKind': itemKind,
  'forwardOutcome': forwardOutcome,
  'forwardCount': forwardCount,
  'digestCount': null,
  'eventTotal': eventTotal,
  'eventUnseenCount': eventUnseenCount,
  'provenanceJson': null,
  'beaconAuthorId': 'Ualice0000001',
  'beaconAuthorName': 'Alice',
  'beaconAuthorImageId': null,
  'beaconImageId': null,
  'beaconEndAt': null,
  'allowsForward': true,
  'beaconTitle': beaconTitle ?? title,
  'beaconKind': null,
  'postRootExcerpt': null,
  'postRootImageId': null,
  'eventsPreview': eventsPreview,
};

/// The forward row the server sends for a Request whose forward was
/// answered: id `inbox:<beaconId>`, `itemKind` `forward`.
Map<String, dynamic> forwardOutcomeRowWire({
  required String beaconId,
  required String createdAt,
  required String? seenAt,
  String forwardOutcome = 'watching',
  String title = 'Book swap Sunday',
}) => attentionStreamRowWire(
  id: 'inbox:$beaconId',
  itemKind: 'forward',
  beaconId: beaconId,
  createdAt: createdAt,
  seenAt: seenAt,
  forwardOutcome: forwardOutcome,
  forwardCount: 1,
  title: title,
);

GAttentionFeedData attentionFeedData(List<Map<String, dynamic>> items) =>
    GAttentionFeedData.fromJson({
      '__typename': 'query_root',
      'attentionFeed': {
        '__typename': 'AttentionFeed',
        'summary': {
          '__typename': 'AttentionSummary',
          'unreadTotal': 0,
          'needsYouTotal': 0,
        },
        'page': {
          '__typename': 'AttentionPage',
          'nextCursor': null,
          'items': items,
        },
      },
    })!;

/// Maps [items] through the production [AttentionRepository.fetch].
Future<List<AttentionReceipt>> mapStreamRowsThroughRepository(
  List<Map<String, dynamic>> items, {
  AttentionView view = AttentionView.all,
}) async {
  final remote = _FeedFixtureRemoteClient(attentionFeedData(items));
  final feed = await AttentionRepository(remote).fetch(view: view);
  return feed.page.items;
}

/// Maps a single stream row through the production repository.
Future<AttentionReceipt> mapStreamRowThroughRepository(
  Map<String, dynamic> row,
) async => (await mapStreamRowsThroughRepository([row])).single;

final class _FeedFixtureRemoteClient implements RemoteRequestClient {
  _FeedFixtureRemoteClient(this.feedData);

  final GAttentionFeedData feedData;

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
    throw UnsupportedError('Unexpected operation: $request');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
