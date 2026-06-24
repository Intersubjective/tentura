import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/notification_center_item.dart';
import '../gql/_g/notifications_feed.req.gql.dart';
import '../gql/_g/notifications_mark_all_read.req.gql.dart';
import '../gql/_g/notifications_mark_read.req.gql.dart';

typedef NotificationFeedPage = ({
  List<NotificationCenterItem> items,
  int unreadCount,
});

@Singleton(env: [Environment.dev, Environment.prod])
class NotificationCenterRepository {
  const NotificationCenterRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'NotificationCenter';

  Future<NotificationFeedPage> fetch({int limit = 50, DateTime? before}) async {
    final data = await _remoteApiService
        .request(
          GNotificationsFeedReq(
            (r) => r
              ..vars.limit = limit
              ..vars.before = before?.toUtc().toIso8601String(),
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
    return (
      unreadCount: data.notificationsUnreadCount,
      items: [
        for (final i in data.notificationsFeed)
          NotificationCenterItem(
            id: i.id,
            category: NotificationCenterCategory.parse(i.category),
            kind: i.kind,
            title: i.title,
            body: i.body,
            actionUrl: i.actionUrl,
            createdAt: DateTime.parse(i.createdAt),
            collapsedCount: i.collapsedCount,
            readAt: i.readAt == null ? null : DateTime.tryParse(i.readAt!),
            beaconId: i.beaconId,
            coordinationItemId: i.coordinationItemId,
            actorUserId: i.actorUserId,
          ),
      ],
    );
  }

  Future<int> markRead(List<String> ids) async {
    if (ids.isEmpty) {
      return 0;
    }
    final data = await _remoteApiService
        .request(GNotificationsMarkReadReq((r) => r..vars.ids.addAll(ids)))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
    return data.notificationsMarkRead;
  }

  Future<int> markAllRead() async {
    final data = await _remoteApiService
        .request(GNotificationsMarkAllReadReq())
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
    return data.notificationsMarkAllRead;
  }
}
