import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/use_case/notification_center_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// Shared projection for [NotificationOutboxItemEntity] → `NotificationItem`.
Map<String, dynamic> mapNotificationItem(NotificationOutboxItemEntity i) => {
      'id': i.id,
      'category': i.category.name,
      'kind': i.kind.name,
      'priority': i.priority.name,
      'title': i.title,
      'body': i.body,
      'actionUrl': i.actionUrl,
      'createdAt': i.createdAt.toUtc().toIso8601String(),
      'readAt': i.readAt?.toUtc().toIso8601String(),
      'collapsedCount': i.collapsedCount,
      'beaconId': i.beaconId,
      'coordinationItemId': i.coordinationItemId,
      'actorUserId': i.actorUserId,
    };

final class QueryNotificationCenter extends GqlNodeBase {
  QueryNotificationCenter({NotificationCenterCase? useCase})
      : _case = useCase ?? GetIt.I<NotificationCenterCase>();

  final NotificationCenterCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        notificationsFeed,
        notificationsUnreadCount,
      ];

  GraphQLObjectField<dynamic, dynamic> get notificationsFeed =>
      GraphQLObjectField(
        'notificationsFeed',
        GraphQLListType(gqlTypeNotificationItem.nonNullable()).nonNullable(),
        arguments: [
          _limit.fieldNullable,
          _before.fieldNullable,
        ],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final items = await _case.feed(
            accountId: jwt.sub,
            limit: _limit.fromArgs(args) ?? 50,
            before: _before.fromArgs(args),
          );
          return [for (final i in items) mapNotificationItem(i)];
        },
      );

  GraphQLObjectField<dynamic, dynamic> get notificationsUnreadCount =>
      GraphQLObjectField(
        'notificationsUnreadCount',
        graphQLInt.nonNullable(),
        resolve: (_, args) =>
            _case.unreadActionableCount(getCredentials(args).sub),
      );

  static final _limit = InputFieldInt(fieldName: 'limit');
  static final _before = InputFieldDatetime(fieldName: 'before');
}
