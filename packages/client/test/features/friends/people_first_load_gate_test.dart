import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/friends/ui/screen/friends_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/domain/capability/friend_context.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/likable.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/friends/domain/entity/person_list_meta.dart';
import 'package:tentura/features/friends/domain/use_case/friends_case.dart';
import 'package:tentura/features/friends/ui/bloc/friends_cubit.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../../support/fake_block_case.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

class _ViewerCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

class _PresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream => const Stream.empty();
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump();
  }
}

typedef _Frame = ({int spinners, int ada, int boris});

_Frame _frame() => (
  spinners: find.byType(CircularProgressIndicator).evaluate().length,
  ada: find.text('Ada').evaluate().length,
  boris: find.text('Boris').evaluate().length,
);

void main() {
  for (final locale in [const Locale('en'), const Locale('ru')]) {
    for (final surface in [kPhoneSurface, const Size(1280, 800)]) {
      testWidgets(
        'People withholds the list past 2.5 s until primary data arrives '
        '(${locale.languageCode}, ${surface.width.toInt()}×${surface.height.toInt()})',
        (tester) async {
          final harness = _FriendsHarness();
          final screen = ScreenCubit.local(harness.effects);
          final initial = Completer<Iterable<Profile>>();
          harness.friendsRepository.pending.add(initial);
          GetIt.I
            ..registerSingleton<FriendsCubit>(harness.cubit)
            ..registerSingleton<FriendsCase>(harness.friendsCase)
            ..registerSingleton<AuthCase>(harness.authCase)
            ..registerSingleton<InvitationRepository>(harness.invitations)
            ..registerSingleton<UiEffectPort>(harness.effects);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await screen.close();
            await harness.dispose();
            GetIt.I
              ..unregister<FriendsCubit>()
              ..unregister<FriendsCase>()
              ..unregister<AuthCase>()
              ..unregister<InvitationRepository>()
              ..unregister<UiEffectPort>();
          });
          await tester.binding.setSurfaceSize(surface);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          harness.signIn();
          await tester.pumpWidget(
            MaterialApp(
              theme: TenturaTheme.light(),
              locale: locale,
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: TenturaResponsiveScope(
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<ScreenCubit>.value(value: screen),
                    BlocProvider<ProfileCubit>.value(value: _ViewerCubit()),
                    BlocProvider<PresenceCubit>.value(value: _PresenceCubit()),
                  ],
                  child: const FriendsScreen(),
                ),
              ),
            ),
          );
          await _flush(tester);
          expect(harness.friendsRepository.fetchCalls, 1);
          const gated = (spinners: 1, ada: 0, boris: 0);
          expect(initial.isCompleted, isFalse);
          expect(find.text('Ada'), findsNothing);
          expect(find.text('Boris'), findsNothing);
          // Allow ample time for the approximate spinner delay, while staying
          // comfortably inside the first-load timeout.
          await tester.pump(const Duration(milliseconds: 500));
          expect(initial.isCompleted, isFalse);
          expect(
            _frame(),
            gated,
            reason:
                'A pending first list eventually shows one spinner and no rows',
          );
          // 500 ms plus at most 64 ms above, then 2100 ms: beyond the
          // proposal's 2.5 s escape without relying on a millisecond boundary.
          await tester.pump(const Duration(milliseconds: 2100));
          await _flush(tester);
          expect(initial.isCompleted, isFalse);
          final l10n = L10n.of(tester.element(find.byType(FriendsScreen)))!;
          expect(find.text(l10n.friendsEmptyTitle), findsNothing);
          expect(find.text('Ada'), findsNothing);
          expect(find.text('Boris'), findsNothing);
          expect(
            _frame(),
            gated,
            reason:
                'No partial list or empty state before primary data; '
                'spinner stays past 2.5 s',
          );
          initial.complete([
            _friend('ada').copyWith(displayName: 'Ada'),
            _friend('boris').copyWith(displayName: 'Boris'),
          ]);
          await _flush(tester);
          expect(find.text('Ada'), findsOneWidget);
          expect(find.text('Boris'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);

          // Let a local event's debounced reconciliation finish before testing
          // a separate catch-up from a missed server notification.
          harness.friendsRepository.result = harness.cubit.state.friends.values;
          await tester.pump(const Duration(milliseconds: 101));
          await _flush(tester);
          final refresh = Completer<Iterable<Profile>>();
          harness.friendsRepository.pending.add(refresh);
          final reads = harness.friendsRepository.fetchCalls;
          harness.realtimePort.emitCatchUp();
          await _flush(tester);
          await tester.pump(const Duration(milliseconds: 101));
          await _flush(tester);
          expect(harness.friendsRepository.fetchCalls, reads + 1);
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            expect(refresh.isCompleted, isFalse);
            expect(_frame(), (spinners: 0, ada: 1, boris: 1));
          }
          refresh.complete([
            _friend('ada').copyWith(displayName: 'Ada refreshed'),
            _friend('boris').copyWith(displayName: 'Boris'),
          ]);
          await _flush(tester);
          expect(find.text('Ada refreshed'), findsOneWidget);
          expect(find.text('Ada'), findsNothing);
          expect(find.text('Boris'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(harness.effects.emitted, isEmpty);
        },
      );
    }
  }

  for (final locale in [const Locale('ru'), const Locale('en')]) {
    for (final surface in [kPhoneSurface, const Size(1280, 800)]) {
      testWidgets(
        'People shows no top linear bar while the gate spinner is active '
        '(${locale.languageCode}, ${surface.width.toInt()}×${surface.height.toInt()})',
        (tester) async {
          final harness = _FriendsHarness();
          final screen = ScreenCubit.local(harness.effects);
          final initial = Completer<Iterable<Profile>>();
          harness.friendsRepository.pending.add(initial);
          GetIt.I
            ..registerSingleton<FriendsCubit>(harness.cubit)
            ..registerSingleton<FriendsCase>(harness.friendsCase)
            ..registerSingleton<AuthCase>(harness.authCase)
            ..registerSingleton<InvitationRepository>(harness.invitations)
            ..registerSingleton<UiEffectPort>(harness.effects);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await screen.close();
            await harness.dispose();
            GetIt.I
              ..unregister<FriendsCubit>()
              ..unregister<FriendsCase>()
              ..unregister<AuthCase>()
              ..unregister<InvitationRepository>()
              ..unregister<UiEffectPort>();
          });
          await tester.binding.setSurfaceSize(surface);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          harness.signIn();
          await tester.pumpWidget(
            MaterialApp(
              theme: TenturaTheme.light(),
              locale: locale,
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: TenturaResponsiveScope(
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<ScreenCubit>.value(value: screen),
                    BlocProvider<ProfileCubit>.value(value: _ViewerCubit()),
                    BlocProvider<PresenceCubit>.value(value: _PresenceCubit()),
                  ],
                  child: const FriendsScreen(),
                ),
              ),
            ),
          );
          await _flush(tester);
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.byType(LinearPiActive), findsNothing);
          expect(
            find.descendant(
              of: find.byType(FriendsScreen),
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
        },
      );
    }
  }
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
      blockCase,
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
  final blockCase = FakeBlockCase();

  late final AuthCase authCase;
  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final ContactsCase contactsCase;
  late final FriendsCase friendsCase;
  late final FriendsCubit cubit;

  void signIn() => authLocal.emit('viewer');

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
  Map<String, PersonListMeta> listMetaResult = const {};
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
  Future<Map<String, PersonListMeta>> fetchPeopleListMeta() async =>
      listMetaResult;

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
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

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
