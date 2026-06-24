import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/notification_settings/data/repository/notification_settings_repository.dart';
import 'package:tentura/features/notification_settings/domain/entity/notification_settings.dart';
import 'package:tentura/features/notification_settings/ui/bloc/notification_settings_cubit.dart';

class _FakeRepo implements NotificationSettingsRepository {
  _FakeRepo(this._initial);
  final NotificationSettings _initial;
  bool failUpdate = false;
  int updateCalls = 0;

  @override
  Future<NotificationSettings> fetch() async => _initial;

  @override
  Future<NotificationSettings> update(
    NotificationSettings settings, {
    bool clearQuietHours = false,
    bool clearSnooze = false,
  }) async {
    updateCalls++;
    if (failUpdate) {
      throw Exception('boom');
    }
    return settings; // echo the saved settings
  }
}

NotificationSettings base() => const NotificationSettings(
      pushCategories: {NotificationSettingsCategory.asksOfMe},
      emailCategories: {NotificationSettingsCategory.asksOfMe},
      tzOffsetMinutes: 0,
      emailDigest: NotificationDigestCadence.off,
      lockScreenSafe: false,
    );

void main() {
  test('fetch loads settings', () async {
    final cubit = NotificationSettingsCubit(repository: _FakeRepo(base()));
    await cubit.fetch();
    expect(cubit.state.status, isA<StateIsSuccess>());
    expect(
      cubit.state.settings.pushCategories,
      contains(NotificationSettingsCategory.asksOfMe),
    );
    await cubit.close();
  });

  test('enabling a push category persists optimistically', () async {
    final repo = _FakeRepo(base());
    final cubit = NotificationSettingsCubit(repository: repo);
    await cubit.fetch();

    await cubit.setChannelCategory(
      category: NotificationSettingsCategory.coordination,
      email: false,
      enabled: true,
    );
    expect(
      cubit.state.settings.pushCategories,
      contains(NotificationSettingsCategory.coordination),
    );
    expect(repo.updateCalls, 1);
    await cubit.close();
  });

  test('setDigest updates cadence', () async {
    final cubit = NotificationSettingsCubit(repository: _FakeRepo(base()));
    await cubit.fetch();
    await cubit.setDigest(NotificationDigestCadence.daily);
    expect(cubit.state.settings.emailDigest, NotificationDigestCadence.daily);
    await cubit.close();
  });

  test('reverts to previous settings when the update fails', () async {
    final repo = _FakeRepo(base())..failUpdate = true;
    final cubit = NotificationSettingsCubit(repository: repo);
    await cubit.fetch();

    await cubit.setLockScreenSafe(true);
    // Optimistic value rolled back.
    expect(cubit.state.settings.lockScreenSafe, isFalse);
    expect(cubit.state.status, isA<StateHasError>());
    await cubit.close();
  });
}
