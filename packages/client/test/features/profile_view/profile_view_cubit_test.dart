import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

void main() {
  group('Profile view realtime orchestration', () {
    late _ProfileViewHarness harness;

    setUp(() => harness = _ProfileViewHarness());

    tearDown(() => harness.dispose());

    test(
      'loads the contact overlay and capability cues',
      () async {
        harness
          ..contactStore.set('U-target', 'Private name')
          ..profiles.result = _profile(displayName: 'Public name')
          ..capabilities.cues = const PersonCapabilityCues(
            privateLabels: ['translation'],
          )
          ..start();
        await harness.waitFor(
          () => harness.cubit.state.profile.displayName.isNotEmpty,
        );

        expect(harness.cubit.state.profile.shownName, 'Private name');
        expect(harness.cubit.state.cues.privateLabels, ['translation']);
      },
    );

    test(
      'delivered relationship invalidation silently replaces profile',
      () async {
        harness
          ..profiles.result = _profile()
          ..start();
        await harness.waitFor(() => harness.profiles.fetchCalls == 1);
        final effects = harness.effects.emitted.length;

        harness.profiles.result = _profile(myVote: 1);
        harness.realtimePort.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.relationship,
            aggregateId: 'U-coalesced-batch-representative',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await harness.waitFor(() => harness.cubit.state.profile.myVote == 1);

        expect(harness.effects.emitted, hasLength(effects));
      },
    );

    test('unrelated profile invalidation is ignored', () async {
      harness.start();
      await harness.waitFor(() => harness.profiles.fetchCalls == 1);

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
    });

    test('contact and catch-up changes converge the open profile', () async {
      harness.start();
      await harness.waitFor(() => harness.profiles.fetchCalls == 1);

      harness.contactStore.set('U-target', 'Renamed elsewhere');
      await harness.waitFor(
        () => harness.cubit.state.profile.contactName == 'Renamed elsewhere',
      );
      final afterContact = harness.profiles.fetchCalls;

      harness.profiles.result = _profile(displayName: 'Updated public name');
      harness.realtimePort.emitCatchUp();
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'Updated public name',
      );

      expect(harness.profiles.fetchCalls, greaterThan(afterContact));
    });

    test('stale completion cannot replace a newer snapshot', () async {
      harness.start();
      await harness.waitFor(() => harness.profiles.fetchCalls == 1);
      final stale = Completer<Profile>();
      final fresh = Completer<Profile>();
      harness.profiles.pending.addAll([stale, fresh]);

      final staleFetch = harness.cubit.fetch(showLoading: false);
      final freshFetch = harness.cubit.fetch(showLoading: false);
      await harness.waitFor(() => harness.profiles.pending.isEmpty);
      fresh.complete(_profile(displayName: 'Fresh'));
      await freshFetch;
      stale.complete(_profile(displayName: 'Stale'));
      await staleFetch;

      expect(harness.cubit.state.profile.displayName, 'Fresh');
    });

    test('background failure retains usable state without an effect', () async {
      harness
        ..profiles.result = _profile(displayName: 'Stable')
        ..start();
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'Stable',
      );
      harness.profiles.error = StateError('offline');

      harness.realtimePort.emitCatchUp();
      await harness.waitFor(() => harness.profiles.fetchCalls >= 2);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(harness.cubit.state.profile.displayName, 'Stable');
      expect(harness.cubit.state.loadError, isNull);
      expect(harness.effects.emitted, isEmpty);
    });

    test(
      'friend mutations are delegated and keep the contact overlay',
      () async {
        harness
          ..contactStore.set('U-target', 'Private name')
          ..start();
        await harness.waitFor(() => harness.profiles.fetchCalls == 1);

        await harness.cubit.addFriend();
        expect(harness.cubit.state.profile.myVote, 1);
        expect(harness.cubit.state.profile.shownName, 'Private name');
        await harness.cubit.removeFriend();

        expect(harness.likes.amounts, [1, 0]);
        expect(harness.cubit.state.profile.myVote, 0);
      },
    );
  });
}

Profile _profile({String displayName = 'Target', int myVote = 0}) => Profile(
  id: 'U-target',
  displayName: displayName,
  myVote: myVote,
);

final class _ProfileViewHarness {
  _ProfileViewHarness() {
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
  final profiles = _FakeProfileRepository();
  final likes = _FakeLikeRepository();
  final capabilities = _FakeCapabilityRepository();
  final effects = FakeUiEffectPort();

  late final AuthCase authCase;
  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final ContactsCase contactsCase;
  late final ProfileViewCase case_;
  ProfileViewCubit? _cubit;

  ProfileViewCubit get cubit => _cubit!;

  void start() {
    _cubit = ProfileViewCubit(
      id: 'U-target',
      profileViewCase: case_,
      effects: effects,
    );
  }

  Future<void> closeCubit() async {
    await _cubit?.close();
    _cubit = null;
  }

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for Profile convergence.');
  }

  Future<void> dispose() async {
    await closeCubit();
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
  Profile result = _profile();
  Object? error;
  int fetchCalls = 0;
  final pending = <Completer<Profile>>[];

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

  @override
  Future<Profile> fetchById(String id) async {
    fetchCalls++;
    if (pending.isNotEmpty) return pending.removeAt(0).future;
    final failure = error;
    if (failure is Exception) throw failure;
    if (failure is Error) throw failure;
    return result;
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

final class _FakeLikeRepository implements LikeRemoteRepository {
  final _changes = StreamController<RepositoryEvent<Likable>>.broadcast();
  final amounts = <int>[];

  @override
  Stream<RepositoryEvent<Likable>> get changes => _changes.stream;

  @override
  Future<T> setLike<T extends Likable>(T entity, {required int amount}) async {
    amounts.add(amount);
    return switch (entity) {
          final Profile profile => profile.copyWith(myVote: amount),
          _ => entity,
        }
        as T;
  }

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeCapabilityRepository implements CapabilityRepositoryPort {
  final _changes = StreamController<void>.broadcast();
  PersonCapabilityCues cues = PersonCapabilityCues.empty;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) async => cues;

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
