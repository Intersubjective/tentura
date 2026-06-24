import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/notification_center_item.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'notification_center_state.freezed.dart';

@freezed
abstract class NotificationCenterState extends StateBase
    with _$NotificationCenterState {
  const factory NotificationCenterState({
    @Default([]) List<NotificationCenterItem> items,
    @Default(0) int unreadCount,
    @Default(StateIsLoading()) StateStatus status,
  }) = _NotificationCenterState;

  const NotificationCenterState._();

  bool get isEmpty => items.isEmpty;
}
