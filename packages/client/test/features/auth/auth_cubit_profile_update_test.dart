import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'auth_test_helpers.dart';

const _oldImage = ImageEntity(id: 'img-old', authorId: 'U1', blurHash: 'old');
const _newImage = ImageEntity(id: 'img-new', authorId: 'U1', blurHash: 'new');

Future<({AuthCubit cubit, _RecordingLocal local, _Profiles profiles})> _build(
  AccountEntity initial,
) async {
  final local = _RecordingLocal(initial);
  final profiles = _Profiles();
  final cubit = await AuthCubit.hydrated(
    const Env(),
    buildTestAuthCase(local, EmptyAuthRemote()),
    AccountCase(
      local,
      EmptyAuthRemote(),
      _Platform(),
      profiles,
      env: const Env(),
      logger: Logger('test'),
    ),
    profiles,
    _Effects(),
  );
  return (cubit: cubit, local: local, profiles: profiles);
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('profile update persists the new name, not the stale account', () async {
    final h = await _build(const AccountEntity(id: 'U1', displayName: 'Old'));

    h.profiles.controller.add(
      const RepositoryEventUpdate(Profile(id: 'U1', displayName: 'New')),
    );
    await _settle();

    expect(h.local.saved.single.displayName, 'New');
    expect(h.cubit.state.accounts.single.displayName, 'New');
    await h.cubit.close();
  });

  test('profile update persists the new image, not the stale one', () async {
    final h = await _build(
      const AccountEntity(id: 'U1', displayName: 'Same', image: _oldImage),
    );

    h.profiles.controller.add(
      const RepositoryEventUpdate(
        Profile(id: 'U1', displayName: 'Same', image: _newImage),
      ),
    );
    await _settle();

    expect(h.local.saved, hasLength(1));
    expect(h.local.saved.single.image?.id, 'img-new');
    expect(h.cubit.state.accounts.single.image?.id, 'img-new');
    await h.cubit.close();
  });

  test('profile update persists new name and new image together', () async {
    final h = await _build(
      const AccountEntity(id: 'U1', displayName: 'Old', image: _oldImage),
    );

    h.profiles.controller.add(
      const RepositoryEventUpdate(
        Profile(id: 'U1', displayName: 'New', image: _newImage),
      ),
    );
    await _settle();

    expect(h.local.saved, hasLength(1));
    expect(
      h.local.saved.single,
      const AccountEntity(id: 'U1', displayName: 'New', image: _newImage),
    );
    expect(
      h.cubit.state.accounts.single,
      const AccountEntity(id: 'U1', displayName: 'New', image: _newImage),
    );
    await h.cubit.close();
  });
}

final class _RecordingLocal extends EmptyAuthLocal {
  _RecordingLocal(this._initial);

  final AccountEntity _initial;
  final saved = <AccountEntity>[];

  @override
  Future<List<AccountEntity>> getAccountsAll() async => [_initial];

  @override
  Future<void> updateAccount(AccountEntity account) async => saved.add(account);
}

final class _Platform extends Fake implements PlatformRepositoryPort {}

final class _Profiles extends Fake implements ProfileRepositoryPort {
  final controller = StreamController<RepositoryEvent<Profile>>.broadcast();

  @override
  Stream<RepositoryEvent<Profile>> get changes => controller.stream;
}

final class _Effects extends Fake implements UiEffectPort {
  @override
  Stream<UiEffect> get effects => const Stream.empty();

  @override
  void emit(UiEffect effect) {}
}
