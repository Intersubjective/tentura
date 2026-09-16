import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

class _FakeProfiles implements ProfileRepositoryPort {
  final Map<String, Profile> store = {};
  int fetchCount = 0;
  Completer<void>? gate;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async {
    fetchCount++;
    final g = gate;
    if (g != null) await g.future;
    return [
      for (final id in ids)
        if (store.containsKey(id)) store[id]!,
    ];
  }

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
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<void> setAvailabilityLimited({
    required String profileId,
    required bool isLimited,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> pauseAvailability({
    required String profileId,
    required DateTime resumeOn,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> resumeAvailability({required String profileId}) =>
      throw UnimplementedError();
}

class _FakeAccount implements AttentionAccountPort {
  final _controller = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _controller.stream;

  void switchAccount(String id) => _controller.add(id);
}

void main() {
  late _FakeProfiles profiles;
  late _FakeAccount account;
  late AttentionActorProfilesCase subject;

  setUp(() {
    profiles = _FakeProfiles();
    account = _FakeAccount();
    subject = AttentionActorProfilesCase(profiles, account);
  });

  tearDown(() async {
    await subject.dispose();
  });

  test('fetches missing ids once and serves cache on second resolve', () async {
    profiles.store['u1'] = const Profile(id: 'u1', displayName: 'Anna');
    final first = await subject.resolve({'u1'});
    expect(first['u1']?.displayName, 'Anna');
    expect(profiles.fetchCount, 1);

    final second = await subject.resolve({'u1'});
    expect(second['u1']?.displayName, 'Anna');
    expect(profiles.fetchCount, 1);
  });

  test('negative-caches misses and skips refetch', () async {
    final first = await subject.resolve({'missing'});
    expect(first, isEmpty);
    expect(profiles.fetchCount, 1);

    final second = await subject.resolve({'missing'});
    expect(second, isEmpty);
    expect(profiles.fetchCount, 1);
  });

  test('concurrent resolve coalesces in-flight batch', () async {
    profiles.store['u1'] = const Profile(id: 'u1', displayName: 'Anna');
    profiles.gate = Completer<void>();

    final a = subject.resolve({'u1'});
    final b = subject.resolve({'u1'});
    await Future<void>.delayed(Duration.zero);
    expect(profiles.fetchCount, 1);
    profiles.gate!.complete();
    final results = await Future.wait([a, b]);
    expect(results[0]['u1']?.displayName, 'Anna');
    expect(results[1]['u1']?.displayName, 'Anna');
    expect(profiles.fetchCount, 1);
  });

  test('clear on account switch drops cache', () async {
    profiles.store['u1'] = const Profile(id: 'u1', displayName: 'Anna');
    await subject.resolve({'u1'});
    expect(profiles.fetchCount, 1);

    account.switchAccount('other');
    await Future<void>.delayed(Duration.zero);

    await subject.resolve({'u1'});
    expect(profiles.fetchCount, 2);
  });
}
