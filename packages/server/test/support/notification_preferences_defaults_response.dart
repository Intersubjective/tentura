// Executed by the client wire test in the server's Dart runtime so the UI
// receives the real default preferences and resolver projection, without
// making the Flutter client depend on server libraries.
import 'dart:convert';
import 'dart:io';

import 'package:tentura_server/api/controllers/graphql/query/query_notification_preferences.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';

void main(List<String> arguments) {
  final preferences = NotificationPreferencesEntity.defaults(
    'Uviewer000001',
  ).copyWith(locale: arguments.single);
  stdout.writeln(
    'NOTIFICATION_PREFERENCES_DEFAULTS ${jsonEncode({
      'notificationPreferences': {
        '__typename': 'NotificationPreferences',
        ...mapNotificationPreferences(preferences),
      },
    })}',
  );
}
