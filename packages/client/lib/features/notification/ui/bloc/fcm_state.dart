import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/notification_permission_status.dart';
import '../../domain/entity/notification_permissions.dart';

export 'package:tentura/ui/bloc/state_base.dart';
export '../../domain/entity/notification_permission_status.dart';

part 'fcm_state.freezed.dart';

@freezed
abstract class FcmState extends StateBase with _$FcmState {
  const factory FcmState({
    @Default('') String appId,
    @Default(null) String? token,
    @Default(NotificationPermissions()) NotificationPermissions permissions,
    @Default(StateIsSuccess()) StateStatus status,

    /// Read without prompting. Stays [NotificationPermissionStatus.unsupported]
    /// until known, so nothing is offered before the first read.
    @Default(NotificationPermissionStatus.unsupported)
    NotificationPermissionStatus permissionStatus,

    /// The person closed the in-app prompt on this device.
    @Default(false) bool permissionPromptDismissed,
  }) = _FcmState;

  const FcmState._();

  /// The in-app "turn on notifications" banner is shown only while nobody has
  /// asked yet and the person hasn't closed it.
  bool get showsPermissionPrompt =>
      permissionStatus == NotificationPermissionStatus.notDetermined &&
      !permissionPromptDismissed;
}
