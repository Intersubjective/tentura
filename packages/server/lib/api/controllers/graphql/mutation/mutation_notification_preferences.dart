import 'package:tentura_server/domain/use_case/notification_preference_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../query/query_notification_preferences.dart'
    show mapNotificationPreferences;

final class MutationNotificationPreferences extends GqlNodeBase {
  MutationNotificationPreferences({NotificationPreferenceCase? useCase})
      : _case = useCase ?? GetIt.I<NotificationPreferenceCase>();

  final NotificationPreferenceCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        notificationPreferencesUpdate,
        beaconMuteSet,
        beaconMuteClear,
      ];

  GraphQLObjectField<dynamic, dynamic> get notificationPreferencesUpdate =>
      GraphQLObjectField(
        'notificationPreferencesUpdate',
        gqlTypeNotificationPreferences.nonNullable(),
        arguments: [
          _pushCategories.fieldNullable,
          _emailCategories.fieldNullable,
          _quietHoursStart.fieldNullable,
          _quietHoursEnd.fieldNullable,
          _clearQuietHours.fieldNullable,
          _tzOffsetMinutes.fieldNullable,
          _emailDigest.fieldNullable,
          _snoozeUntil.fieldNullable,
          _clearSnooze.fieldNullable,
          _lockScreenSafe.fieldNullable,
          _locale.fieldNullable,
        ],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final prefs = await _case.update(
            accountId: jwt.sub,
            pushCategories: _pushCategories.fromArgs(args),
            emailCategories: _emailCategories.fromArgs(args),
            quietHoursStartMinute: _quietHoursStart.fromArgs(args),
            quietHoursEndMinute: _quietHoursEnd.fromArgs(args),
            clearQuietHours: _clearQuietHours.fromArgs(args) ?? false,
            tzOffsetMinutes: _tzOffsetMinutes.fromArgs(args),
            emailDigest: _emailDigest.fromArgs(args),
            snoozeUntil: _snoozeUntil.fromArgs(args),
            clearSnooze: _clearSnooze.fromArgs(args) ?? false,
            lockScreenSafe: _lockScreenSafe.fromArgs(args),
            locale: _locale.fromArgs(args),
          );
          return mapNotificationPreferences(prefs);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconMuteSet => GraphQLObjectField(
        'beaconMuteSet',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconId.field,
          _mutedUntil.fieldNullable,
        ],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          await _case.setBeaconMute(
            accountId: jwt.sub,
            beaconId: _beaconId.fromArgsNonNullable(args),
            mutedUntil: _mutedUntil.fromArgs(args),
          );
          return true;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconMuteClear =>
      GraphQLObjectField(
        'beaconMuteClear',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconId.field,
        ],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          await _case.clearBeaconMute(
            accountId: jwt.sub,
            beaconId: _beaconId.fromArgsNonNullable(args),
          );
          return true;
        },
      );

  static final _pushCategories =
      InputFieldStringList(fieldName: 'pushCategories');
  static final _emailCategories =
      InputFieldStringList(fieldName: 'emailCategories');
  static final _quietHoursStart = InputFieldInt(fieldName: 'quietHoursStart');
  static final _quietHoursEnd = InputFieldInt(fieldName: 'quietHoursEnd');
  static final _clearQuietHours = InputFieldBool(fieldName: 'clearQuietHours');
  static final _tzOffsetMinutes = InputFieldInt(fieldName: 'tzOffsetMinutes');
  static final _emailDigest = InputFieldString(fieldName: 'emailDigest');
  static final _snoozeUntil = InputFieldDatetime(fieldName: 'snoozeUntil');
  static final _clearSnooze = InputFieldBool(fieldName: 'clearSnooze');
  static final _lockScreenSafe = InputFieldBool(fieldName: 'lockScreenSafe');
  static final _locale = InputFieldString(fieldName: 'locale');
  static final _beaconId = InputFieldString(fieldName: 'beaconId');
  static final _mutedUntil = InputFieldDatetime(fieldName: 'mutedUntil');
}
