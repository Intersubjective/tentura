import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'auth_test_helpers.dart';
import 'cookie_sign_in_test_support.dart';

/// Boot with stored account A and a cookie for user B ends with only B (#1140).
void main() {
  test('cookie boot prunes a different stored account', () async {
    final local = CookieSignInLocal(currentAccountId: selectedAccountId);
    addTearDown(local.dispose);
    final remote = CookieSignInRemote();
    final cubit = await AuthCubit.hydrated(
      const Env(),
      buildTestAuthCase(local, remote, logger: Logger('1140')),
      AccountCase(
        local,
        remote,
        _FakePlatform(),
        _FakeProfiles(),
        env: const Env(),
        logger: Logger('1140'),
      ),
      _FakeProfiles(),
      _FakeEffects(),
    );
    addTearDown(cubit.dispose);

    expect(cubit.state.currentAccountId, cookieAccountId);
    expect(
      cubit.state.accounts.map((e) => e.id).toList(),
      [cookieAccountId],
    );
    expect(await local.getAccountById(selectedAccountId), isNull);
    expect(await local.getAccountById(unrelatedAccountId), isNull);
  });
}

final class _FakePlatform extends Fake implements PlatformRepositoryPort {}

final class _FakeProfiles extends Fake implements ProfileRepositoryPort {
  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();
}

final class _FakeEffects extends Fake implements UiEffectPort {
  @override
  Stream<UiEffect> get effects => const Stream.empty();

  @override
  void emit(UiEffect effect) {}
}
