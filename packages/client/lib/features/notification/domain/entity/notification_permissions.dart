import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_permissions.freezed.dart';

@freezed
abstract class NotificationPermissions with _$NotificationPermissions {
  const factory NotificationPermissions({
    @Default(false) bool authorized,
  }) = _NotificationPermissions;

  const NotificationPermissions._();
}
