import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

void main() {
  group('ProfileCubit availability commands', () {
    late _AvailabilityHarness harness;

    setUp(() => harness = _AvailabilityHarness());

    tearDown(() => harness.dispose());

    test('setAvailabilityLimited success updates profile from repository event',
        () async {
      harness.signIn('U-me');
      await harness.waitForProfile();

      final limited = harness.cubit.state.profile.copyWith(
        availability: const Availability(isLimited: true),
      );
      harness.profiles.onSetLimited = (profileId, isLimited) async {
        harness.profiles.emit(limited);
      };

      await harness.cubit.setAvailabilityLimited(true);

      expect(harness.cubit.state.profile.availability.isLimited, isTrue);
      expect(harness.profiles.setLimitedCalls, 1);
      expect(harness.profiles.lastSetLimitedProfileId, 'U-me');
      expect(harness.profiles.lastSetLimitedValue, isTrue);
      expect(harness.effects.emitted, isEmpty);
      expect(harness.cubit.isAvailabilityLimitedInFlight, isFalse);
    });

    test('pauseAvailability success updates profile from repository event',
        () async {
      harness.signIn('U-me');
      await harness.waitForProfile();
      final resumeOn = DateTime.utc(2026, 8, 20);
      final paused = harness.cubit.state.profile.copyWith(
        availability: Availability(
          isLimited: true,
          resumeOn: resumeOn,
        ),
      );
      harness.profiles.onPause = (profileId, resumeOnArg) async {
        expect(resumeOnArg, resumeOn);
        harness.profiles.emit(paused);
      };

      await harness.cubit.pauseAvailability(resumeOn);

      expect(
        harness.cubit.state.profile.availability.resumeOn,
        resumeOn,
      );
      expect(harness.profiles.pauseCalls, 1);
      expect(harness.profiles.lastPauseProfileId, 'U-me');
      expect(harness.effects.emitted, isEmpty);
      expect(harness.cubit.isAvailabilityPauseInFlight, isFalse);
    });

    test('resumeAvailability success updates profile from repository event',
        () async {
      harness.signIn('U-me');
      await harness.waitForProfile();
      final open = harness.cubit.state.profile.copyWith(
        availability: Availability.open(),
      );
      harness.profiles.onResume = (profileId) async {
        harness.profiles.emit(open);
      };

      await harness.cubit.resumeAvailability();

      expect(harness.cubit.state.profile.availability, Availability.open());
      expect(harness.profiles.resumeCalls, 1);
      expect(harness.profiles.lastResumeProfileId, 'U-me');
      expect(harness.effects.emitted, isEmpty);
      expect(harness.cubit.isAvailabilityResumeInFlight, isFalse);
    });

    test('failure retains previous profile and emits exactly one ShowError',
        () async {
      harness.signIn('U-me');
      await harness.waitForProfile();
      final before = harness.cubit.state.profile;
      harness.profiles.failAvailability = Exception('offline');

      await harness.cubit.setAvailabilityLimited(true);

      expect(harness.cubit.state.profile, before);
      expect(harness.effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(harness.cubit.isAvailabilityLimitedInFlight, isFalse);
    });

    test('combined limited+paused profile stays intact until repository confirms',
        () async {
      final resumeOn = DateTime.utc(2026, 8, 20);
      harness.signIn('U-me');
      await harness.waitForProfile();
      harness.cubit.emit(
        ProfileState(
          profile: harness.cubit.state.profile.copyWith(
            availability: Availability(
              isLimited: true,
              resumeOn: resumeOn,
            ),
          ),
        ),
      );
      final before = harness.cubit.state.profile;
      harness.profiles.onSetLimited = (profileId, isLimited) async {
        harness.profiles.emit(
          before.copyWith(
            availability: Availability(
              isLimited: isLimited,
              resumeOn: resumeOn,
            ),
          ),
        );
      };

      await harness.cubit.setAvailabilityLimited(false);

      expect(harness.cubit.state.profile.availability.isLimited, isFalse);
      expect(harness.cubit.state.profile.availability.resumeOn, resumeOn);
      expect(harness.effects.emitted, isEmpty);
    });

    test('repository update does not emit duplicate user-visible effects',
        () async {
      harness.signIn('U-me');
      await harness.waitForProfile();
      harness.profiles.onPause = (profileId, resumeOn) async {
        harness.profiles.emit(
          harness.cubit.state.profile.copyWith(
            availability: Availability(resumeOn: resumeOn),
          ),
        );
      };

      await harness.cubit.pauseAvailability(DateTime.utc(2026, 8, 21));

      expect(harness.effects.emitted, isEmpty);
    });
  });
}

final class _AvailabilityHarness {
  _AvailabilityHarness() {
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

  final authLocal = _AvailabilityAuthLocal();
  final profiles = _AvailabilityProfileRepository();
  final effects = FakeUiEffectPort();

  late final AuthCase authCase;
  late final AccountCase accountCase;
  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final ProfileCubit cubit;

  void signIn(String accountId) => authLocal.emit(accountId);

  Future<void> waitForProfile() => _waitFor(
    () => cubit.state.profile.id == 'U-me',
  );

  Future<void> _waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for profile availability harness.');
  }

  Future<void> dispose() async {
    await cubit.dispose();
    await realtimePort.dispose();
    await profiles.dispose();
    await authLocal.dispose();
  }
}

final class _AvailabilityAuthLocal extends StreamingAuthLocal {
  @override
  Future<AccountEntity?> getAccountById(String id) async => AccountEntity(
    id: id,
    displayName: 'Cached $id',
  );
}

typedef _SetLimitedHandler = Future<void> Function(String profileId, bool value);
typedef _PauseHandler = Future<void> Function(String profileId, DateTime resumeOn);
typedef _ResumeHandler = Future<void> Function(String profileId);

final class _AvailabilityProfileRepository implements ProfileRepositoryPort {
  final _changes = StreamController<RepositoryEvent<Profile>>.broadcast();

  _SetLimitedHandler? onSetLimited;
  _PauseHandler? onPause;
  _ResumeHandler? onResume;
  Object? failAvailability;

  int setLimitedCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  String? lastSetLimitedProfileId;
  bool? lastSetLimitedValue;
  String? lastPauseProfileId;
  String? lastResumeProfileId;

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

  void emit(Profile profile) => _changes.add(RepositoryEventUpdate(profile));

  @override
  Future<Profile> fetchById(String id) async =>
      Profile(id: id, displayName: '$id-1');

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
  Future<void> setAvailabilityLimited({
    required String profileId,
    required bool isLimited,
  }) async {
    setLimitedCalls++;
    lastSetLimitedProfileId = profileId;
    lastSetLimitedValue = isLimited;
    final failure = failAvailability;
    if (failure is Exception) throw failure;
    if (failure is Error) throw failure;
    await onSetLimited?.call(profileId, isLimited);
  }

  @override
  Future<void> pauseAvailability({
    required String profileId,
    required DateTime resumeOn,
  }) async {
    pauseCalls++;
    lastPauseProfileId = profileId;
    final failure = failAvailability;
    if (failure is Exception) throw failure;
    if (failure is Error) throw failure;
    await onPause?.call(profileId, resumeOn);
  }

  @override
  Future<void> resumeAvailability({required String profileId}) async {
    resumeCalls++;
    lastResumeProfileId = profileId;
    final failure = failAvailability;
    if (failure is Exception) throw failure;
    if (failure is Error) throw failure;
    await onResume?.call(profileId);
  }

  @override
  Future<void> dispose() => _changes.close();
}

final class _FakePlatformRepository implements PlatformRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
