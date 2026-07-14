import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/domain/capability/friend_context.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/friends/domain/use_case/friends_case.dart';
import 'package:tentura/features/friends/ui/bloc/friends_cubit.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

void main() {
  group('Friends realtime orchestration', () {
    late _FriendsHarness harness;

    setUp(() => harness = _FriendsHarness());

    tearDown(() => harness.dispose());

    test('loads friends, contact overlays, contexts, and presence', () async {
      harness
        ..contactsRepository.fetchMineResult = {'friend-1': 'Private name'}
        ..friendsRepository.result = [_friend('friend-1')]
        ..capabilities.contexts = {
          'friend-1': const FriendContext(activeForwardsToCount: 2),
        }
        ..signIn();
      await harness.waitFor(
        () => harness.cubit.state.friends.containsKey('friend-1'),
      );

      expect(
        harness.cubit.state.friends['friend-1']!.shownName,
        'Private name',
      );
      expect(
        harness.cubit.state.friendContexts['friend-1']!.activeForwardsToCount,
        2,
      );
      expect(harness.presence.lastWatched, {'friend-1'});
    });

    test('relationship invalidation silently replaces the snapshot', () async {
      harness.friendsRepository.result = [_friend('friend-1')];
      harness.signIn();
      await harness.waitFor(
        () => harness.cubit.state.friends.containsKey('friend-1'),
      );
      final effects = harness.effects.emitted.length;

      harness.friendsRepository.result = [_friend('friend-2')];
      harness.realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.relationship,
          aggregateId: 'friend-2',
          operation: RealtimeOperation.insert,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await harness.waitFor(
        () => harness.cubit.state.friends.containsKey('friend-2'),
      );

      expect(harness.cubit.state.friends.containsKey('friend-1'), isFalse);
      expect(harness.effects.emitted, hasLength(effects));
    });

    test('catch-up replaces a missed friendship change', () async {
      harness.friendsRepository.result = [_friend('friend-1')];
      harness.signIn();
      await harness.waitFor(
        () => harness.cubit.state.friends.containsKey('friend-1'),
      );

      harness.friendsRepository.result = const [];
      harness.realtimePort.emitCatchUp();
      await harness.waitFor(() => harness.cubit.state.friends.isEmpty);

      expect(harness.cubit.state.loadError, isNull);
    });

    test('local friend changes use immutable map copies', () async {
      harness.friendsRepository.result = [_friend('friend-1')];
      harness.signIn();
      await harness.waitFor(
        () => harness.cubit.state.friends.containsKey('friend-1'),
      );
      final previous = harness.cubit.state.friends;
      harness.friendsRepository.result = const [];

      harness.likes.emit(_friend('friend-1', isFriend: false));
      await Future<void>.delayed(Duration.zero);

      expect(previous.containsKey('friend-1'), isTrue);
      expect(harness.cubit.state.friends.containsKey('friend-1'), isFalse);
      expect(identical(previous, harness.cubit.state.friends), isFalse);
    });

    test('stale load completion cannot replace a newer snapshot', () async {
      harness.friendsRepository.result = [_friend('initial')];
      harness.signIn();
      await harness.waitFor(
        () => harness.cubit.state.friends.containsKey('initial'),
      );
      final stale = Completer<Iterable<Profile>>();
      final fresh = Completer<Iterable<Profile>>();
      harness.friendsRepository.pending.addAll([stale, fresh]);

      final staleFetch = harness.cubit.fetch(showLoading: false);
      final freshFetch = harness.cubit.fetch(showLoading: false);
      await harness.waitFor(() => harness.friendsRepository.pending.isEmpty);
      fresh.complete([_friend('fresh')]);
      await freshFetch;
      stale.complete([_friend('stale')]);
      await staleFetch;

      expect(harness.cubit.state.friends.keys, ['fresh']);
    });

    test('background failure retains usable state without an effect', () async {
      harness.friendsRepository.result = [_friend('stable')];
      harness.signIn();
      await harness.waitFor(
        () => harness.cubit.state.friends.containsKey('stable'),
      );
      harness.friendsRepository.error = StateError('offline');

      harness.realtimePort.emitCatchUp();
      await harness.waitFor(() => harness.friendsRepository.fetchCalls >= 2);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(harness.cubit.state.friends.keys, ['stable']);
      expect(harness.cubit.state.loadError, isNull);
      expect(harness.effects.emitted, isEmpty);
    });

    test('mutations are delegated through FriendsCase', () async {
      final profile = _friend('friend-1');

      await harness.cubit.addFriend(profile);
      await harness.cubit.removeFriend(profile);
      await harness.cubit.acceptInvitation('invite-1');

      expect(harness.likes.amounts, [1, 0]);
      expect(harness.invitations.accepted, ['invite-1']);
    });
  });
}

Profile _friend(String id, {bool isFriend = true}) => Profile(
  id: id,
  displayName: id,
  myVote: isFriend ? 1 : 0,
);

final class _FriendsHarness {
  _FriendsHarness() {
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
    friendsCase = FriendsCase(
      capabilities,
      invitations,
      likes,
      friendsRepository,
      presence,
      contactsCase,
      authCase,
      realtimeCase,
      env: const Env(),
      logger: Logger('test'),
    );
    cubit = FriendsCubit(friendsCase, effects);
  }

  final authLocal = StreamingAuthLocal();
  final contactsRepository = FakeContactsRepository();
  final contactStore = ContactNameStore();
  final capabilities = _FakeCapabilityRepository();
  final invitations = _FakeInvitationRepository();
  final likes = _FakeLikeRepository();
  final friendsRepository = _FakeFriendsRepository();
  final presence = _FakePresenceRepository();
  final effects = FakeUiEffectPort();

  late final AuthCase authCase;
  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final ContactsCase contactsCase;
  late final FriendsCase friendsCase;
  late final FriendsCubit cubit;

  void signIn() => authLocal.emit('viewer');

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for Friends convergence.');
  }

  Future<void> dispose() async {
    await cubit.close();
    await contactsCase.dispose();
    await realtimePort.dispose();
    await contactStore.dispose();
    await likes.dispose();
    await invitations.dispose();
    await authLocal.dispose();
  }
}

final class _FakeFriendsRepository implements FriendsRemoteRepository {
  Iterable<Profile> result = const [];
  Object? error;
  int fetchCalls = 0;
  final pending = <Completer<Iterable<Profile>>>[];

  @override
  Future<Iterable<Profile>> fetch() async {
    fetchCalls++;
    if (pending.isNotEmpty) return pending.removeAt(0).future;
    final failure = error;
    if (failure is Exception) throw failure;
    if (failure is Error) throw failure;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeCapabilityRepository implements CapabilityRepositoryPort {
  Map<String, FriendContext> contexts = {};

  @override
  Future<Map<String, FriendContext>> fetchFriendContextsBatch({
    required List<String> subjectIds,
  }) async => {
    for (final id in subjectIds) id: ?contexts[id],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeInvitationRepository implements InvitationRepository {
  final _changes = StreamController<void>.broadcast();
  final accepted = <String>[];

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> accept(String id) async => accepted.add(id);

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeLikeRepository implements LikeRemoteRepository {
  final _changes = StreamController<RepositoryEvent<Likable>>.broadcast();
  final amounts = <int>[];

  @override
  Stream<RepositoryEvent<Likable>> get changes => _changes.stream;

  void emit(Profile profile) => _changes.add(RepositoryEventUpdate(profile));

  @override
  Future<T> setLike<T extends Likable>(T entity, {required int amount}) async {
    amounts.add(amount);
    return entity;
  }

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakePresenceRepository implements PresenceRepository {
  Set<String> lastWatched = {};

  @override
  void watch(String sourceKey, Set<String> userIds) {
    lastWatched = {...userIds};
  }

  @override
  void unwatch(String sourceKey) => lastWatched = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
