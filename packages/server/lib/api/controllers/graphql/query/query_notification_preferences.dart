import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/use_case/notification_preference_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';

/// Shared resolver projection for [NotificationPreferencesEntity] →
/// the `NotificationPreferences` GraphQL object. Reused by the mutation.
Map<String, dynamic> mapNotificationPreferences(
  NotificationPreferencesEntity p,
) =>
    {
      'accountId': p.accountId,
      'pushCategories': [for (final c in p.pushCategories) c.name],
      'emailCategories': [for (final c in p.emailCategories) c.name],
      'quietHoursStart': p.quietHoursStartMinute,
      'quietHoursEnd': p.quietHoursEndMinute,
      'tzOffsetMinutes': p.tzOffsetMinutes,
      'emailDigest': p.emailDigest.name,
      'snoozeUntil': p.snoozeUntil?.toUtc().toIso8601String(),
      'lockScreenSafe': p.lockScreenSafe,
      'locale': p.locale,
    };

final class QueryNotificationPreferences extends GqlNodeBase {
  QueryNotificationPreferences({NotificationPreferenceCase? useCase})
      : _case = useCase ?? GetIt.I<NotificationPreferenceCase>();

  final NotificationPreferenceCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        notificationPreferences,
      ];

  GraphQLObjectField<dynamic, dynamic> get notificationPreferences =>
      GraphQLObjectField(
        'notificationPreferences',
        gqlTypeNotificationPreferences.nonNullable(),
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final prefs = await _case.getForAccount(jwt.sub);
          return mapNotificationPreferences(prefs);
        },
      );
}
