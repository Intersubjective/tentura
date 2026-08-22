import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.req.gql.dart';

/// CR-13 compatibility coverage through the production path:
/// GraphQL JSON -> Ferry generated data -> [AttentionRepository.fetch] ->
/// domain receipt. This protects both nullable wire fields and the
/// repository's explicit field mapping; hand-constructing the domain entity
/// would cover neither.
void main() {
  final remote = _FixtureRemoteClient();
  final repository = AttentionRepository(remote);

  test(
    'legacy wire receipt deserializes and maps nullable identity fields',
    () async {
      final feed = await _fetch(repository, remote, [_legacyWireReceipt()]);
      final receipt = feed.page.items.single;

      expect(receipt.sourceEventKey, isNull);
      expect(receipt.destinationKind, isNull);
      expect(receipt.targetEntityId, isNull);
      expect(receipt.presentationKey, isNull);
      expect(receipt.actorUserId, 'Uactor000000001');
      expect(receipt.createdAt, DateTime.utc(2026, 7, 24, 12));
      expect(
        attentionDestination(receipt).toString(),
        '/profile/view/Uactor000000001',
      );
    },
  );

  test(
    'canonical wire receipt preserves typed identity through mapping',
    () async {
      final feed = await _fetch(repository, remote, [_canonicalWireReceipt()]);
      final receipt = feed.page.items.single;

      expect(
        receipt.sourceEventKey,
        'inviteAccepted:Uactor000000001:Urecipient00001',
      );
      expect(receipt.destinationKind, 'profile');
      expect(receipt.targetEntityId, 'Uactor000000001');
      expect(receipt.presentationKey, 'invite_accepted');
      expect(
        attentionDestination(receipt).path,
        '/profile/view/Uactor000000001',
      );
    },
  );

  test(
    'wire replay never creates two domain receipts with the same id',
    () async {
      final receipt = _canonicalWireReceipt();
      final feed = await _fetch(repository, remote, [receipt, receipt]);

      expect(feed.page.items, hasLength(1));
      expect(feed.page.items.single.id, receipt['id']);
    },
  );
}

Future<AttentionFeed> _fetch(
  AttentionRepository repository,
  _FixtureRemoteClient remote,
  List<Map<String, dynamic>> receipts,
) async {
  final data = GAttentionFeedData.fromJson({
    '__typename': 'query_root',
    'attentionFeed': {
      '__typename': 'AttentionFeed',
      'summary': {
        '__typename': 'AttentionSummary',
        'unreadTotal': 1,
        'needsYouTotal': 0,
      },
      'page': {
        '__typename': 'AttentionPage',
        'nextCursor': null,
        'items': receipts,
      },
    },
  });
  expect(data, isNotNull, reason: 'fixture must pass Ferry deserialization');
  remote.data = data;
  return repository.fetch(view: AttentionView.all);
}

Map<String, dynamic> _legacyWireReceipt() => _wireReceipt();

Map<String, dynamic> _canonicalWireReceipt() => _wireReceipt()
  ..addAll({
    'sourceEventKey': 'inviteAccepted:Uactor000000001:Urecipient00001',
    'destinationKind': 'profile',
    'targetEntityId': 'Uactor000000001',
    'presentationKey': 'invite_accepted',
  });

Map<String, dynamic> _wireReceipt() => {
  '__typename': 'AttentionReceipt',
  'id': 'Nlegacy00000001',
  'category': 'connections',
  'kind': 'inviteAccepted',
  'priority': 'normal',
  'title': 'Invite accepted',
  'body': 'Alex joined via your invite',
  'actionUrl': '/profile/view/Uactor000000001',
  'createdAt': '2026-07-24T12:00:00.000Z',
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': null,
  'coordinationItemId': null,
  'actorUserId': 'Uactor000000001',
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
};

final class _FixtureRemoteClient implements RemoteRequestClient {
  GAttentionFeedData? data;

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
          data: data as TData,
        ),
      );
    }
    throw UnsupportedError('Unexpected operation: $request');
  }
}
