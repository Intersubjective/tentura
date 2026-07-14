import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

void main() {
  group('Own profile realtime convergence', () {
    late _ProfileHarness harness;

    setUp(() => harness = _ProfileHarness());

    tearDown(() => harness.dispose());

    test('matching invalidation and catch-up silently refresh', () async {
      harness.signIn('U-me');
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'U-me-1',
      );
      final effects = harness.effects.emitted.length;

      harness.realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.profile,
          aggregateId: 'U-other',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(harness.profiles.fetchCalls, 1);

      harness.realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.profile,
          aggregateId: 'U-me',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'U-me-2',
      );

      harness.realtimePort.emitCatchUp();
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'U-me-3',
      );
      expect(harness.effects.emitted, hasLength(effects));
    });

    test(
      'stale account response cannot overwrite the current account',
      () async {
        final stale = Completer<Profile>();
        final fresh = Completer<Profile>();
        harness.profiles.pending.addAll([stale, fresh]);

        harness.signIn('U-old');
        await harness.waitFor(() => harness.profiles.fetchCalls == 1);
        harness.signIn('U-new');
        await harness.waitFor(() => harness.profiles.fetchCalls == 2);

        fresh.complete(const Profile(id: 'U-new', displayName: 'New'));
        await harness.waitFor(
          () => harness.cubit.state.profile.displayName == 'New',
        );
        stale.complete(const Profile(id: 'U-old', displayName: 'Old'));
        await Future<void>.delayed(Duration.zero);

        expect(harness.cubit.state.profile.id, 'U-new');
        expect(harness.cubit.state.profile.displayName, 'New');
      },
    );

    test('background failure retains profile and emits no effect', () async {
      harness.signIn('U-me');
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'U-me-1',
      );
      harness.profiles.error = StateError('offline');

      harness.realtimePort.emitCatchUp();
      await harness.waitFor(() => harness.profiles.fetchCalls == 2);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(harness.cubit.state.profile.displayName, 'U-me-1');
      expect(harness.effects.emitted, isEmpty);
    });

    test('local repository updates only replace the active profile', () async {
      harness.signIn('U-me');
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'U-me-1',
      );

      harness.profiles.emit(
        const Profile(id: 'U-other', displayName: 'Wrong'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(harness.cubit.state.profile.id, 'U-me');

      harness.profiles.emit(
        const Profile(id: 'U-me', displayName: 'Local update'),
      );
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'Local update',
      );
    });
  });
}

final class _ProfileHarness {
  _ProfileHarness() {
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    realtimeCase = realtime.case_;
    authCase = buildTestAuthCase(authLocal, EmptyAuthRemote());
    accountCase = AccountCase(
      authLocal,
      EmptyAuthRemote(),
      _FakePlatformRepository(),
      profiles,
      env: const Env(),
      logger: Logger('test'),
    );
    cubit = ProfileCubit(
      accountCase: accountCase,
      authCase: authCase,
      profileRepository: profiles,
      realtimeSyncCase: realtimeCase,
      effects: effects,
    );
  }

  final authLocal = _ProfileAuthLocal();
  final profiles = _FakeProfileRepository();
  final effects = FakeUiEffectPort();

  late final AuthCase authCase;
  late final AccountCase accountCase;
  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final ProfileCubit cubit;

  void signIn(String accountId) => authLocal.emit(accountId);

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for own Profile convergence.');
  }

  Future<void> dispose() async {
    await cubit.dispose();
    await realtimeCase.dispose();
    await realtimePort.dispose();
    await profiles.dispose();
    await authLocal.dispose();
  }
}

final class _ProfileAuthLocal extends StreamingAuthLocal {
  @override
  Future<AccountEntity?> getAccountById(String id) async => AccountEntity(
    id: id,
    displayName: 'Cached $id',
  );
}

final class _FakeProfileRepository implements ProfileRepositoryPort {
  final _changes = StreamController<RepositoryEvent<Profile>>.broadcast();
  final _fetchesById = <String, int>{};
  final pending = <Completer<Profile>>[];
  Object? error;
  int fetchCalls = 0;

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

  void emit(Profile profile) => _changes.add(RepositoryEventUpdate(profile));

  @override
  Future<Profile> fetchById(String id) async {
    fetchCalls++;
    if (pending.isNotEmpty) return pending.removeAt(0).future;
    final failure = error;
    if (failure is Exception) throw failure;
    if (failure is Error) throw failure;
    final fetch = (_fetchesById[id] ?? 0) + 1;
    _fetchesById[id] = fetch;
    return Profile(id: id, displayName: '$id-$fetch');
  }

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => const [];

  @override
  Future<void> update(
    Profile profile, {
    String? displayName,
    String? description,
    bool dropImage = false,
    ImageEntity? image,
    bool updateHandle = false,
    String? handle,
  }) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> dispose() => _changes.close();
}

final class _FakePlatformRepository implements PlatformRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
