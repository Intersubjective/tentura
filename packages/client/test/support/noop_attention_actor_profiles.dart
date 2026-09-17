import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

/// Empty [AttentionActorProfilesCase] for unit/widget tests that construct
/// [UpdatesFeedCubit] / [ActivityOffersCubit] without full DI.
AttentionActorProfilesCase buildNoopAttentionActorProfiles() =>
    AttentionActorProfilesCase(
      const _NoopProfiles(),
      _NoopAccount(),
    );

/// Registers a shared noop instance on [GetIt.I] when missing (idempotent).
void ensureNoopAttentionActorProfilesRegistered() {
  if (GetIt.I.isRegistered<AttentionActorProfilesCase>()) return;
  GetIt.I.registerSingleton<AttentionActorProfilesCase>(
    buildNoopAttentionActorProfiles(),
  );
}

class _NoopProfiles implements ProfileRepositoryPort {
  const _NoopProfiles();

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async =>
      const <Profile>[];

  @override
  Future<Profile> fetchById(String id) => throw UnimplementedError();

  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> update(
    Profile profile, {
    String? displayName,
    String? description,
    bool dropImage = false,
    ImageEntity? image,
    bool updateHandle = false,
    String? handle,
  }) => throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<void> setAvailabilityLimited({
    required String profileId,
    required bool isLimited,
  }) => throw UnimplementedError();

  @override
  Future<void> pauseAvailability({
    required String profileId,
    required DateTime resumeOn,
  }) => throw UnimplementedError();

  @override
  Future<void> resumeAvailability({required String profileId}) =>
      throw UnimplementedError();
}

class _NoopAccount implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}
