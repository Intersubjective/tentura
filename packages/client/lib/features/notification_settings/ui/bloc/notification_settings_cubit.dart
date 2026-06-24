import 'package:get_it/get_it.dart';

import '../../data/repository/notification_settings_repository.dart';
import '../../domain/entity/notification_settings.dart';
import 'notification_settings_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'notification_settings_state.dart';

class NotificationSettingsCubit extends Cubit<NotificationSettingsState> {
  NotificationSettingsCubit({NotificationSettingsRepository? repository})
      : _repository = repository ?? GetIt.I<NotificationSettingsRepository>(),
        super(NotificationSettingsState());

  final NotificationSettingsRepository _repository;

  Future<void> fetch() async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      final settings = await _repository.fetch();
      emit(state.copyWith(settings: settings, status: const StateIsSuccess()));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> setChannelCategory({
    required NotificationSettingsCategory category,
    required bool email,
    required bool enabled,
  }) {
    final current = email
        ? state.settings.emailCategories
        : state.settings.pushCategories;
    final next = {...current};
    if (enabled) {
      next.add(category);
    } else {
      next.remove(category);
    }
    return _persist(
      email
          ? state.settings.copyWith(emailCategories: next)
          : state.settings.copyWith(pushCategories: next),
    );
  }

  Future<void> setDigest(NotificationDigestCadence cadence) =>
      _persist(state.settings.copyWith(emailDigest: cadence));

  Future<void> setLockScreenSafe(bool value) =>
      _persist(state.settings.copyWith(lockScreenSafe: value));

  Future<void> setQuietHours({
    required int startMinute,
    required int endMinute,
  }) =>
      _persist(
        state.settings.copyWith(
          quietHoursStart: startMinute,
          quietHoursEnd: endMinute,
          // UTC offset (minutes) the server adds to derive the account's local
          // time for quiet-hours / digest scheduling.
          tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
        ),
      );

  Future<void> clearQuietHours() =>
      _persist(state.settings.copyWith(clearQuietHours: true), clearQuietHours: true);

  Future<void> snoozeFor(Duration duration) => _persist(
        state.settings.copyWith(snoozeUntil: DateTime.now().add(duration)),
      );

  Future<void> clearSnooze() =>
      _persist(state.settings.copyWith(clearSnooze: true), clearSnooze: true);

  Future<void> _persist(
    NotificationSettings optimistic, {
    bool clearQuietHours = false,
    bool clearSnooze = false,
  }) async {
    final previous = state.settings;
    emit(state.copyWith(settings: optimistic, status: const StateIsSuccess()));
    try {
      final saved = await _repository.update(
        optimistic,
        clearQuietHours: clearQuietHours,
        clearSnooze: clearSnooze,
      );
      emit(state.copyWith(settings: saved));
    } catch (e) {
      // Revert on failure.
      emit(state.copyWith(settings: previous, status: StateHasError(e)));
    }
  }
}
