import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'auth_test_helpers.dart';

/// Regression for dev 2026-10-05: `/session/access-token` took ~60s and the
/// 10s bootstrap timeout signed everyone out. Only a server rejection may.
void main() {
  group('AuthCubit bootstrap', () {
    test('slow session restore keeps the stored account signed in', () {
      fakeAsync((async) {
        final remote = _ScriptedRemote([_Step.hang]);
        final cubit = _hydrate(async, remote);

        async.elapse(const Duration(seconds: 11));

        expect(cubit.state.isBootstrapping, isFalse);
        expect(cubit.state.currentAccountId, 'U-session');
        expect(cubit.state.authRecoveryNeeded, isFalse);

        // Early requests failing auth while the restore is pending must not
        // escalate to the Recover screen.
        cubit
          ..noteAuthSessionLoss(const AuthSessionLostException())
          ..noteAuthSessionLoss(const AuthSessionLostException());
        expect(cubit.state.authSessionLossCount, 0);

        remote.release('U-session');
        async.flushMicrotasks();

        expect(cubit.state.currentAccountId, 'U-session');
        expect(cubit.state.authRecoveryNeeded, isFalse);
      });
    });

    test('server unavailable is retried, not treated as a lost session', () {
      fakeAsync((async) {
        final remote = _ScriptedRemote([
          _Step.unavailable,
          _Step.unavailable,
          _Step.ok,
        ]);
        final cubit = _hydrate(async, remote);

        async.elapse(const Duration(minutes: 1));

        expect(cubit.state.currentAccountId, 'U-session');
        expect(cubit.state.authRecoveryNeeded, isFalse);
        expect(cubit.state.authSessionLossCount, 0);
        expect(remote.calls, greaterThanOrEqualTo(3));
      });
    });

    test('server rejection still signs the user out', () {
      fakeAsync((async) {
        final remote = _ScriptedRemote([_Step.reject]);
        final cubit = _hydrate(async, remote);

        async.elapse(const Duration(seconds: 1));

        expect(cubit.state.currentAccountId, isEmpty);
        expect(cubit.state.authRecoveryNeeded, isTrue);
      });
    });
  });
}

AuthCubit _hydrate(FakeAsync async, _ScriptedRemote remote) {
  final local = _SessionLocal();
  AuthCubit? cubit;
  unawaited(
    AuthCubit.hydrated(
      const Env(),
      buildTestAuthCase(local, remote),
      AccountCase(
        local,
        remote,
        _FakePlatform(),
        _FakeProfiles(),
        env: const Env(),
        logger: Logger('test'),
      ),
      _FakeProfiles(),
      _FakeEffects(),
    ).then((c) => cubit = c),
  );
  // hydrated resolves on the bootstrap timeout at the latest.
  async
    ..flushMicrotasks()
    ..elapse(const Duration(seconds: 10, milliseconds: 1));
  return cubit!;
}

enum _Step { ok, hang, unavailable, reject }

final class _ScriptedRemote extends EmptyAuthRemote {
  _ScriptedRemote(this._steps);

  final List<_Step> _steps;

  final _hanging = Completer<String>();

  int calls = 0;

  void release(String userId) => _hanging.complete(userId);

  @override
  Future<String> signInWithSession() async {
    final step = _steps[calls < _steps.length ? calls : _steps.length - 1];
    calls++;
    return switch (step) {
      _Step.ok => 'U-session',
      _Step.hang => _hanging.future,
      _Step.unavailable => throw const AuthServerUnavailableException(),
      _Step.reject => throw const SessionAuthRejectedException(),
    };
  }
}

final class _SessionLocal extends EmptyAuthLocal {
  String _current = 'U-session';

  @override
  Future<String> getCurrentAccountId() async => _current;

  @override
  Future<void> setCurrentAccountId(String? id) async => _current = id ?? '';

  @override
  Future<bool> isSessionAccount(String id) async => true;

  @override
  Future<String> getSeedByAccountId(String id) async => 'seed';
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
