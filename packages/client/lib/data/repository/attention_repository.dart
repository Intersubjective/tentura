import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_mark_all_seen.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_mark_seen.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_settle.req.gql.dart';

@LazySingleton(
  as: AttentionRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
final class AttentionRepository implements AttentionRepositoryPort {
  AttentionRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'Attention';

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) async {
    final data = await _remoteApiService
        .request(
          GAttentionFeedReq(
            (request) => request.vars
              ..view = view.name
              ..cursor = cursor
              ..search = search
              ..limit = limit,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final feed = data.attentionFeed;
    return AttentionFeed(
      summary: AttentionSummary(
        unreadTotal: feed.summary.unreadTotal,
        needsYouTotal: feed.summary.needsYouTotal,
      ),
      page: AttentionFeedPage(
        nextCursor: feed.page.nextCursor,
        items: [
          for (final item in feed.page.items)
            AttentionReceipt(
              id: item.id,
              category: item.category,
              kind: item.kind,
              priority: item.priority,
              title: item.title,
              body: item.body,
              actionUrl: item.actionUrl,
              createdAt: DateTime.parse(item.createdAt),
              seenAt: item.seenAt == null
                  ? null
                  : DateTime.tryParse(item.seenAt!),
              collapsedCount: item.collapsedCount,
              beaconId: item.beaconId,
              coordinationItemId: item.coordinationItemId,
              actorUserId: item.actorUserId,
              sourceEventKey: item.sourceEventKey,
              destinationKind: item.destinationKind,
              targetEntityId: item.targetEntityId,
              presentationKey: item.presentationKey,
              presentationPayloadJson: item.presentationPayloadJson,
              inAppPreferenceClass: item.inAppPreferenceClass,
              requiresAction: item.requiresAction,
              attentionThreadKey: item.attentionThreadKey,
              settlementKind: item.settlementKind,
              settledAt: item.settledAt == null
                  ? null
                  : DateTime.tryParse(item.settledAt!),
            ),
        ],
      ),
    );
  }

  @override
  Future<int> markSeen(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final data = await _remoteApiService
        .request(
          GAttentionMarkSeenReq((request) => request.vars.ids.addAll(ids)),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return data.attentionMarkSeen;
  }

  @override
  Future<int> markAllSeen() async {
    final data = await _remoteApiService
        .request(GAttentionMarkAllSeenReq())
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return data.attentionMarkAllSeen;
  }

  @override
  Future<int> settle({
    required String receiptId,
    required String kind,
  }) async {
    final data = await _remoteApiService
        .request(
          GAttentionSettleReq(
            (request) => request.vars
              ..receiptId = receiptId
              ..kind = kind,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return data.attentionSettle;
  }
}
