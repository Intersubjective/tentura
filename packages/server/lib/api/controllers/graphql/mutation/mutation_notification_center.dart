import 'package:tentura_server/domain/use_case/notification_center_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationNotificationCenter extends GqlNodeBase {
  MutationNotificationCenter({NotificationCenterCase? useCase})
      : _case = useCase ?? GetIt.I<NotificationCenterCase>();

  final NotificationCenterCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        notificationsMarkRead,
        notificationsMarkAllRead,
      ];

  GraphQLObjectField<dynamic, dynamic> get notificationsMarkRead =>
      GraphQLObjectField(
        'notificationsMarkRead',
        graphQLInt.nonNullable(),
        arguments: [
          _ids.field,
        ],
        resolve: (_, args) => _case.markRead(
          accountId: getCredentials(args).sub,
          ids: _ids.fromArgsNonNullable(args),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get notificationsMarkAllRead =>
      GraphQLObjectField(
        'notificationsMarkAllRead',
        graphQLInt.nonNullable(),
        resolve: (_, args) => _case.markAllRead(getCredentials(args).sub),
      );

  static final _ids = InputFieldStringList(fieldName: 'ids');
}
