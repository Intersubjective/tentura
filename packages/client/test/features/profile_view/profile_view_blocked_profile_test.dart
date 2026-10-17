import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/block/ui/sheet/block_user_sheet.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/domain/exception.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/features/profile_view/ui/widget/blocked_profile_view_body.dart';
import 'package:tentura/features/profile_view/ui/widget/profile_view_app_bar.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_person_shared_context_port.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../../support/fake_block_case.dart';
import '../contacts/contacts_case_test.dart';

void main() {
  group('ProfileViewCubit blocked-profile fallback', () {
    late _BlockedProfileHarness harness;

    setUp(() => harness = _BlockedProfileHarness());

    tearDown(() => harness.dispose());

    test(
      'ProfileFetchException with direct block shows stripped profile state',
      () async {
        const blocked = Profile(
          id: 'U-blocked',
          displayName: 'Blocked Person',
        );
        harness
          ..profiles.error = const ProfileFetchException('U-blocked')
          ..blockCase.fetchMyBlocksResult = [
            const BlockIntent(blocked: blocked),
          ]
          ..start(id: 'U-blocked');
        await harness.waitFor(() => harness.cubit.state.isBlockedFallback);

        expect(harness.cubit.state.blockedProfile, blocked);
        expect(harness.cubit.state.loadError, isNull);
        expect(harness.effects.emitted.whereType<ShowError>(), isEmpty);
      },
    );

    // B056: blocking from the open profile used to keep the loaded profile
    // (trust toggle on, "Send a request") because the block event only
    // scheduled a silent refetch, and a refetch failure after the first load
    // is swallowed. The profile must switch to the blocked state at once.
    test('blocking the open profile switches to the blocked state', () async {
      harness
        ..profiles.result = const Profile(
          id: 'U-friend',
          displayName: 'Helper Two',
          myVote: 1,
        )
        ..start(id: 'U-friend');
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'Helper Two',
      );

      // After the block the server hides the person from the viewer.
      harness.profiles.error = const ProfileFetchException('U-friend');
      harness.blockCase.emitChange(
        const RepositoryEventCreate(
          BlockIntent(blocked: Profile(id: 'U-friend')),
        ),
      );
      await harness.waitFor(() => harness.cubit.state.isBlockedFallback);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(harness.cubit.state.isBlockedFallback, isTrue);
      expect(harness.cubit.state.blockedProfile?.id, 'U-friend');
      expect(harness.cubit.state.blockedProfile?.displayName, 'Helper Two');
      expect(harness.effects.emitted.whereType<ShowError>(), isEmpty);
    });

    test('a block of someone else leaves the open profile alone', () async {
      harness
        ..profiles.result = const Profile(
          id: 'U-friend',
          displayName: 'Helper Two',
          myVote: 1,
        )
        ..start(id: 'U-friend');
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'Helper Two',
      );

      harness.blockCase.emitChange(
        const RepositoryEventCreate(
          BlockIntent(blocked: Profile(id: 'U-other')),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(harness.cubit.state.isBlockedFallback, isFalse);
      expect(harness.cubit.state.profile.displayName, 'Helper Two');
    });

    test('unblocking from elsewhere restores the full profile', () async {
      harness
        ..profiles.error = const ProfileFetchException('U-friend')
        ..blockCase.fetchMyBlocksResult = [
          const BlockIntent(
            blocked: Profile(id: 'U-friend', displayName: 'Helper Two'),
          ),
        ]
        ..start(id: 'U-friend');
      await harness.waitFor(() => harness.cubit.state.isBlockedFallback);

      harness.profiles
        ..error = null
        ..result = const Profile(id: 'U-friend', displayName: 'Helper Two');
      harness.blockCase.emitChange(
        const RepositoryEventDelete(
          BlockIntent(blocked: Profile(id: 'U-friend')),
        ),
      );
      await harness.waitFor(() => !harness.cubit.state.isBlockedFallback);

      expect(harness.cubit.state.blockedProfile, isNull);
      expect(harness.cubit.state.profile.displayName, 'Helper Two');
    });

    // B056 review: a block from another session of this account, or by the
    // other person, has no local BlockCase event. The server's block marker
    // (constellation_field with the blocker's id) triggers a refetch, and a
    // refetch the server answers without the profile is not kept stale.
    test('a block from another session reaches the open profile', () async {
      harness
        ..profiles.result = const Profile(
          id: 'U-friend',
          displayName: 'Helper Two',
          myVote: 1,
        )
        ..start(id: 'U-friend');
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'Helper Two',
      );

      harness.profiles.error = const ProfileFetchException('U-friend');
      harness.blockCase.fetchMyBlocksResult = [
        const BlockIntent(
          blocked: Profile(id: 'U-friend', displayName: 'Helper Two'),
        ),
      ];
      harness.realtimePort.emitChange(_blockMarker(blockerId: 'U-viewer'));
      await harness.waitFor(() => harness.cubit.state.isBlockedFallback);

      expect(harness.cubit.state.blockedProfile?.id, 'U-friend');
      expect(harness.cubit.state.blockedProfile?.displayName, 'Helper Two');
      expect(harness.effects.emitted.whereType<ShowError>(), isEmpty);
    });

    test('a block by the other person drops the stale profile', () async {
      harness
        ..profiles.result = const Profile(
          id: 'U-friend',
          displayName: 'Helper Two',
          myVote: 1,
        )
        ..start(id: 'U-friend');
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'Helper Two',
      );

      harness.profiles.error = const ProfileFetchException('U-friend');
      harness.realtimePort.emitChange(_blockMarker(blockerId: 'U-friend'));
      await harness.waitFor(() => harness.cubit.state.loadError != null);

      // The same state as opening a profile the server does not return:
      // nothing of the loaded profile (trust, request actions) is kept.
      expect(harness.cubit.state.loadError, isA<ProfileFetchException>());
      expect(harness.cubit.state.profile, const Profile(id: 'U-friend'));
      expect(harness.cubit.state.blockedProfile, isNull);
      expect(harness.effects.emitted.whereType<ShowError>(), isEmpty);
    });

    test(
      'a transient refetch failure still keeps the loaded profile',
      () async {
        harness
          ..profiles.result = const Profile(
            id: 'U-friend',
            displayName: 'Helper Two',
            myVote: 1,
          )
          ..start(id: 'U-friend');
        await harness.waitFor(
          () => harness.cubit.state.profile.displayName == 'Helper Two',
        );
        final calls = harness.profiles.fetchCalls;

        harness.profiles.error = StateError('offline');
        harness.realtimePort.emitChange(_blockMarker(blockerId: 'U-friend'));
        await harness.waitFor(() => harness.profiles.fetchCalls > calls);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(harness.cubit.state.profile.displayName, 'Helper Two');
        expect(harness.cubit.state.loadError, isNull);
      },
    );

    test('the global constellation marker does not refetch', () async {
      harness
        ..profiles.result = const Profile(
          id: 'U-friend',
          displayName: 'Helper Two',
        )
        ..start(id: 'U-friend');
      await harness.waitFor(
        () => harness.cubit.state.profile.displayName == 'Helper Two',
      );
      final calls = harness.profiles.fetchCalls;

      harness.realtimePort.emitChange(
        _blockMarker(
          blockerId: RealtimeSyncCase.globalConstellationFieldId,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(harness.profiles.fetchCalls, calls);
    });

    test(
      'ProfileFetchException without direct block keeps loadError path',
      () async {
        harness
          ..profiles.error = const ProfileFetchException('U-missing')
          ..blockCase.fetchMyBlocksResult = const []
          ..start(id: 'U-missing');
        await harness.waitFor(() => harness.cubit.state.loadError != null);

        expect(harness.cubit.state.blockedProfile, isNull);
        expect(harness.cubit.state.loadError, isA<ProfileFetchException>());
        expect(harness.effects.emitted.whereType<ShowError>(), isNotEmpty);
      },
    );

    test('unblock clears blocked fallback and retries fetch', () async {
      const blocked = Profile(
        id: 'U-blocked',
        displayName: 'Blocked Person',
      );
      harness
        ..profiles.error = const ProfileFetchException('U-blocked')
        ..blockCase.fetchMyBlocksResult = [
          const BlockIntent(blocked: blocked),
        ]
        ..start(id: 'U-blocked');
      await harness.waitFor(() => harness.cubit.state.isBlockedFallback);

      harness.profiles.error = null;
      harness.profiles.result = blocked;
      await harness.cubit.unblockBlockedProfile();
      await harness.waitFor(() => !harness.cubit.state.isBlockedFallback);

      expect(harness.blockCase.unblockCalls, ['U-blocked']);
      expect(harness.cubit.state.profile.displayName, 'Blocked Person');
    });
  });

  group('BlockedProfileViewBody', () {
    late _BlockedProfileHarness harness;

    setUp(() => harness = _BlockedProfileHarness());

    tearDown(() => harness.dispose());

    testWidgets('renders avatar, name, and unblock action only', (
      tester,
    ) async {
      const profile = Profile(id: 'U-blocked', displayName: 'Blocked Person');
      harness.start(id: profile.id, autoFetch: false);
      harness.cubit.emit(
        const ProfileViewState(
          profile: profile,
          blockedProfile: profile,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: BlocProvider<ProfileViewCubit>.value(
                  value: harness.cubit,
                  child: const CustomScrollView(
                    slivers: [BlockedProfileViewBody(profile: profile)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = lookupL10n(const Locale('en'));
      expect(find.text('Blocked Person'), findsOneWidget);
      expect(find.text(l10n.unblockUserMenuItem), findsOneWidget);
      expect(find.text(l10n.showConnections), findsNothing);
      expect(find.text(l10n.profileSendRequestTo), findsNothing);
      expect(find.text(l10n.trustThisUser), findsNothing);
      expect(find.text(l10n.profileRequestOptions), findsNothing);
    });

    testWidgets('unblock button calls cubit.unblockBlockedProfile', (
      tester,
    ) async {
      const profile = Profile(id: 'U-blocked', displayName: 'Blocked Person');
      harness.start(id: profile.id, autoFetch: false);
      harness.cubit.emit(
        const ProfileViewState(
          profile: profile,
          blockedProfile: profile,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: BlocProvider<ProfileViewCubit>.value(
                  value: harness.cubit,
                  child: const CustomScrollView(
                    slivers: [BlockedProfileViewBody(profile: profile)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.text(lookupL10n(const Locale('en')).unblockUserMenuItem),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.blockCase.unblockCalls, ['U-blocked']);
    });
  });

  group('ProfileView app bar block menu', () {
    final getIt = GetIt.I;
    late _BlockedProfileHarness harness;
    late FakeBlockCase menuBlockCase;

    setUp(() {
      harness = _BlockedProfileHarness();
      menuBlockCase = FakeBlockCase();
      getIt.registerSingleton<BlockCase>(menuBlockCase);
    });

    tearDown(() async {
      await harness.dispose();
      await getIt.reset();
    });

    Future<void> pumpMenu(
      WidgetTester tester, {
      required ProfileViewState state,
      required Profile viewer,
    }) async {
      harness.start(id: state.profile.id, autoFetch: false);
      harness.cubit.emit(state);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileViewCubit>.value(value: harness.cubit),
            BlocProvider<ScreenCubit>.value(value: ScreenCubit.local()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: Size(400, 800)),
              child: TenturaResponsiveScope(
                child: Builder(
                  builder: (context) {
                    final l10n = L10n.of(context)!;
                    return Scaffold(
                      body: PopupMenuButton<void>(
                        itemBuilder: (menuContext) =>
                            profileViewPopupMenuEntries(
                              context: context,
                              state: state,
                              viewerId: viewer.id,
                              l10n: l10n,
                              profileViewCubit: harness.cubit,
                              screenCubit: context.read<ScreenCubit>(),
                            ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows Block item for another user and opens block sheet', (
      tester,
    ) async {
      const other = Profile(id: 'U-other', displayName: 'Other Person');
      const viewer = Profile(id: 'U-viewer', displayName: 'Viewer');
      await pumpMenu(
        tester,
        state: const ProfileViewState(profile: other),
        viewer: viewer,
      );

      final l10n = lookupL10n(const Locale('en'));
      await tester.tap(find.byType(PopupMenuButton<void>));
      await tester.pumpAndSettle();
      expect(find.text(l10n.blockUserMenuItem), findsOneWidget);

      await tester.tap(find.text(l10n.blockUserMenuItem));
      await tester.pumpAndSettle();

      expect(find.byType(BlockUserSheetBody), findsOneWidget);
      expect(find.text(l10n.blockUserTitle('Other Person')), findsOneWidget);
    });

    testWidgets('hides Block item on the viewer own profile', (tester) async {
      const viewer = Profile(id: 'U-viewer', displayName: 'Viewer');
      await pumpMenu(
        tester,
        state: const ProfileViewState(profile: viewer),
        viewer: viewer,
      );

      final l10n = lookupL10n(const Locale('en'));
      await tester.tap(find.byType(PopupMenuButton<void>));
      await tester.pumpAndSettle();

      expect(find.text(l10n.blockUserMenuItem), findsNothing);
      expect(find.text(l10n.renameContactMenuItem), findsNothing);
    });
  });
}

class _BlockedProfileHarness {
  _BlockedProfileHarness() {
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
      FakePersonSharedContextPort(),
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
  final blockCase = FakeBlockCase();

  late final AuthCase authCase;
  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final ContactsCase contactsCase;
  late final ProfileViewCase case_;
  ProfileViewCubit? _cubit;

  ProfileViewCubit get cubit => _cubit!;

  void start({required String id, bool autoFetch = true}) {
    _cubit = autoFetch
        ? ProfileViewCubit(
            id: id,
            profileViewCase: case_,
            blockCase: blockCase,
            effects: effects,
          )
        : ProfileViewCubit.test(
            id: id,
            profileViewCase: case_,
            blockCase: blockCase,
            effects: effects,
            autoFetch: false,
          );
  }

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for ProfileView state.');
  }

  Future<void> dispose() async {
    await _cubit?.close();
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
  Profile result = const Profile();
  Object? error;
  int fetchCalls = 0;

  @override
  Stream<RepositoryEvent<Profile>> get changes => _changes.stream;

  @override
  Future<Profile> fetchById(String id) async {
    fetchCalls++;
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

  @override
  Stream<RepositoryEvent<Likable>> get changes => _changes.stream;

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
  Future<List<TagProjection>> fetchSubjectiveTags(String targetId) async =>
      const [];

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The server's `user_block` trigger marker (m0232): `constellation_field`
/// with the blocker's id, sent to both parties.
RealtimeEntityChange _blockMarker({required String blockerId}) =>
    RealtimeEntityChange(
      kind: RealtimeEntityKind.constellationField,
      aggregateId: blockerId,
      operation: RealtimeOperation.update,
      source: RealtimeChangeSource.serverInvalidation,
    );
