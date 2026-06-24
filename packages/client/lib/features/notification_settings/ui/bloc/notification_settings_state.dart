import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/notification_settings.dart';

export 'package:tentura/ui/bloc/state_base.dart';

class NotificationSettingsState extends StateBase {
  NotificationSettingsState({
    NotificationSettings? settings,
    super.status = const StateIsLoading(),
  }) : settings = settings ?? NotificationSettings.empty();

  final NotificationSettings settings;

  NotificationSettingsState copyWith({
    NotificationSettings? settings,
    StateStatus? status,
  }) =>
      NotificationSettingsState(
        settings: settings ?? this.settings,
        status: status ?? this.status,
      );
}
