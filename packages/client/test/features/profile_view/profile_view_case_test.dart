import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/ui/model/person_action_policy.dart';

import '../../support/test_realtime_sync.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

void main() {
  group('ProfileViewCase authoritative relationship mutations', () {
    late _Harness harness;

    setUp(() => harness = _Harness());

    tearDown(() => harness.dispose());

    test('mutates then refetches authoritative profile projection', () async {
      harness
        ..profiles.byId['U-target'] = _profile(myVote: 0)
        ..profiles.refetchResult = _profile(myVote: 1)
        ..likes.mutationResult = _profile(myVote: 1);

      final result = await harness.case_.addFriend(_profile(myVote: 0));

      expect(harness.likes.amounts, [1]);
      expect(harness.profiles.fetchCalls, 1);
      expect(result.myVote, 1);
      expect(result, isNot(same(harness.likes.mutationResult)));
    });

    test('applies contact overlay on refetched profile', () async {
      harness
        ..contactStore.set('U-target', 'Private name')
        ..profiles.byId['U-target'] = _profile(displayName: 'Public', myVote: 1)
        ..likes.mutationResult = _profile(displayName: 'Public', myVote: 1);

      final result = await harness.case_.addFriend(_profile(myVote: 0));

      expect(result.shownName, 'Private name');
      expect(result.myVote, 1);
    });

    group('PersonActionPolicy transitions after Trust', () {
      test('subject-only → mutual → Send primary', () async {
        harness
          ..profiles.refetchResult = _profile(
            myVote: 1,
            subjectExplicitlyTrustsViewer: true,
            rScore: 1,
          )
          ..likes.mutationResult = _profile(
            myVote: 1,
            subjectExplicitlyTrustsViewer: true,
            rScore: 1,
          );

        final before = _profile(rScore: 1);
        final beforePolicy = PersonActionPolicy.from(
          before,
          isSelf: false,
          isBlocked: false,
        );
        expect(beforePolicy.visibilityState, PersonVisibilityState.subjectOnly);
        expect(beforePolicy.primaryAction, PersonPrimaryAction.trust);

        final after = await harness.case_.addFriend(before);
        final afterPolicy = PersonActionPolicy.from(
          after,
          isSelf: false,
          isBlocked: false,
        );

        expect(afterPolicy.visibilityState, PersonVisibilityState.mutual);
        expect(afterPolicy.primaryAction, PersonPrimaryAction.sendRequest);
        expect(after.viewerExplicitlyTrustsSubject, isTrue);
      });

      test('neither → viewer-only → Request remains unavailable', () async {
        harness
          ..profiles.refetchResult = _profile(myVote: 1)
          ..likes.mutationResult = _profile(myVote: 1);

        final before = _profile();
        final beforePolicy = PersonActionPolicy.from(
          before,
          isSelf: false,
          isBlocked: false,
        );
        expect(beforePolicy.visibilityState, PersonVisibilityState.neither);
        expect(beforePolicy.primaryAction, PersonPrimaryAction.trust);

        final after = await harness.case_.addFriend(before);
        final afterPolicy = PersonActionPolicy.from(
          after,
          isSelf: false,
          isBlocked: false,
        );

        expect(afterPolicy.visibilityState, PersonVisibilityState.viewerOnly);
        expect(afterPolicy.primaryAction, PersonPrimaryAction.none);
        expect(afterPolicy.showRequestOptions, isTrue);
        expect(afterPolicy.canDirectSendRequest, isFalse);
      });
    });
  });
}

Profile _profile({
  String displayName = 'Target',
  int myVote = 0,
  double rScore = 0,
  bool subjectExplicitlyTrustsViewer = false,
}) => Profile(
  id: 'U-target',
  displayName: displayName,
  myVote: myVote,
  rScore: rScore,
  subjectExplicitlyTrustsViewer: subjectExplicitlyTrustsViewer,
);

final class _Harness {
  _Harness() {
    profiles = _FakeProfileRepository();
    likes = _FakeLikeRepository(profiles);
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    realtimeCase = realtime.case_;
    authCase = buildTestAuthCase(authLocal, EmptyAuthRemote());
    contactsCase = ContactsCase(
      contactsRepository,
      authCase,
      contactStore,
      realtimeCase,
      env: const Env(),
      logger: Logger('test'),
    );
    case_ = ProfileViewCase(
      profiles,
      likes,
      capabilities,
      contactsCase,
      realtimeCase,
      env: const Env(),
      logger: Logger('test'),
    );
  }

  final authLocal = StreamingAuthLocal();
  final contactsRepository = FakeContactsRepository();
  final contactStore = ContactNameStore();
  late final _FakeProfileRepository profiles;
  late final _FakeLikeRepository likes;
  final capabilities = _FakeCapabilityRepository();

  late final AuthCase authCase;
  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final ContactsCase contactsCase;
  late final ProfileViewCase case_;

  Future<void> dispose() async {
    await contactsCase.dispose();
    await realtimePort.dispose();
    await contactStore.dispose();
    await profiles.dispose();
    await likes.dispose();
    await capabilities.dispose();
    await authLocal.dispose();
  }
}

final class _FakeProfileRepository implements ProfileRepositoryPort {
  final _changes = StreamController<RepositoryEvent<Profile>>.broadcast();
  final byId = <String, Profile>{};
  Profile? refetchResult;
  bool authoritativeOnNextFetch = false;
  int fetchCalls = 0;

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

  @override
  Future<Profile> fetchById(String id) async {
    fetchCalls++;
    if (authoritativeOnNextFetch) {
      authoritativeOnNextFetch = false;
      return refetchResult ?? byId[id] ?? Profile(id: id);
    }
    return byId[id] ?? Profile(id: id);
  }

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => const [];

  @override
  Future<void> update(
    Profile profile, {
    String? displayName,
    String? description,
    bool dropImage = false,
    dynamic image,
    bool updateHandle = false,
    String? handle,
  }) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> setAvailabilityLimited({
    required String profileId,
    required bool isLimited,
  }) async {}

  @override
  Future<void> pauseAvailability({
    required String profileId,
    required DateTime resumeOn,
  }) async {}

  @override
  Future<void> resumeAvailability({required String profileId}) async {}

  @override
  Future<void> dispose() => _changes.close();
}

final class _FakeLikeRepository implements LikeRemoteRepository {
  final _changes = StreamController<RepositoryEvent<Likable>>.broadcast();
  final amounts = <int>[];
  Profile mutationResult = Profile(id: 'U-target');
  final _FakeProfileRepository profiles;

  _FakeLikeRepository(this.profiles);

  @override
  Stream<RepositoryEvent<Likable>> get changes => _changes.stream;

  @override
  Future<T> setLike<T extends Likable>(T entity, {required int amount}) async {
    amounts.add(amount);
    profiles.authoritativeOnNextFetch = true;
    return mutationResult as T;
  }

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeCapabilityRepository implements CapabilityRepositoryPort {
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) async =>
      PersonCapabilityCues.empty;

  @override
  Future<List<TagProjection>> fetchSubjectiveTags(String targetId) async =>
      const [];

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
