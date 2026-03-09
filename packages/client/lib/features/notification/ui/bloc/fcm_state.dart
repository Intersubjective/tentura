import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/notification_permissions.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'fcm_state.freezed.dart';

@freezed
abstract class FcmState extends StateBase with _$FcmState {
  const factory FcmState({
    @Default('') String appId,
    @Default(null) String? token,
    @Default(NotificationPermissions()) NotificationPermissions permissions,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _FcmState;

  const FcmState._();
}
