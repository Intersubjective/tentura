// The real Activity screen and the real My Work screen start a Post only when
// `canCreatePost` (default `kPostsEnabled`) is on, and navigate to the Post
// create route; with it off they never mention Posts and My Work «+» goes
// straight to the Request form. Runs the full screens with a recording
// ScreenCubit effect port.
// UI copy is asserted verbatim in Russian (docs/plans/post-ux-mockups.md).

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/conversations_screen.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../block/support/controllable_block_case.dart';
import '../inbox/inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;
import '../my_work/my_work_test_support.dart' hide buildTestBeaconThreadsCase;
import '../updates/support/noop_invite_setup_port.dart';

const _accountId = 'viewer';
const _viewport = Size(800, 800);

class _HarnessRouter extends Mock implements StackRouter {}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initial);

  @override
  void clearPendingMovedNudge() {}

  @override
  Future<bool> fetch({bool showLoading = true, bool showError = true}) async =>
      true;

  @override
  Future<void> setWatching(String beaconId) async {}

  @override
  Future<void> stopWatching(String beaconId) async {}

  @override
  Future<void> dismiss(String beaconId, {String note = ''}) async {}

  @override
  Future<void> reject(String beaconId, {String message = ''}) async {}

  @override
  Future<void> unreject(String beaconId) async {}

  @override
  Future<void> dismissTombstone(String beaconId) async {}
}

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _accountId, displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _ForwardRepo implements ForwardRepository {
  final _helpOfferChanges = StreamController<HelpOfferEvent>.broadcast();
  final _forwardChanges = StreamController<String>.broadcast();
  final _forwardCommandCompleted = StreamController<String>.broadcast();

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferChanges.stream;

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Stream<String> get forwardCommandCompleted => _forwardCommandCompleted.stream;

  @override
  Future<void> dispose() async {
    await _helpOfferChanges.close();
    await _forwardChanges.close();
    await _forwardCommandCompleted.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _OrientationPrefs implements HomeOrientationPreferencesPort {
  @override
  Future<bool> isActivated({required String userId}) async => true;

  @override
  Future<void> setActivated({required String userId}) async {}

  @override
  Future<bool> isOrientationDismissed({required String userId}) async => true;

  @override
  Future<void> setOrientationDismissed({required String userId}) async {}

  @override
  Future<void> resetFirstRunState({required String userId}) async {}

  @override
  Future<OrientationDebugOverride> getDebugOverride() async =>
      OrientationDebugOverride.auto;

  @override
  Future<void> setDebugOverride(OrientationDebugOverride value) async {}
}

class _EmptyAttentionRepo extends AttentionRepositoryFake {
  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => const AttentionFeed(
    summary: AttentionSummary(),
    page: AttentionFeedPage(),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

final class _NoPosts implements PostsRepositoryPort {
  @override
  Future<List<PostSummary>> myPosts() async => const [];

  @override
  Future<PostSummary?> postSummary(String id) async => null;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<
  ({FakeUiEffectPort effects, AttentionCase attention, _Accounts accounts})
>
_baseHarness(WidgetTester tester) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);

  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    _EmptyAttentionRepo(),
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('post-create-entry-wiring'),
  );
  accounts.emit(_accountId);
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
  ensureNoopAttentionActorProfilesRegistered();
  GetIt.I
    ..registerSingleton<AttentionCase>(attention)
    ..registerSingleton<InviteAcceptedSetupPort>(NoopInviteAcceptedSetupPort())
    ..registerSingleton<RealtimeSyncCase>(sync.case_)
    ..registerSingleton<Logger>(Logger('post-create-entry-wiring'));
  addTearDown(() async {
    await attention.dispose();
    await accounts.close();
    await sync.port.dispose();
  });
  return (
    effects: FakeUiEffectPort(),
    attention: attention,
    accounts: accounts,
  );
}

Widget _app({required List<BlocProvider> providers, required Widget screen}) =>
    StackRouterScope(
      controller: _HarnessRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: providers,
        child: MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: _viewport),
            child: TenturaResponsiveScope(child: screen),
          ),
        ),
      ),
    );

Future<FakeUiEffectPort> _pumpConversations(
  WidgetTester tester, {
  bool? canCreatePost,
}) async {
  final base = await _baseHarness(tester);
  final inboxCase = buildTestInboxCase(
    FakeInboxRepository()..openForwardsCount = 0,
    buildTestBeaconThreadsCase(),
    forwardRepository: _ForwardRepo(),
  );
  GetIt.I
    ..registerSingleton<InboxCase>(inboxCase)
    ..registerSingleton<PostsCase>(
      PostsCase(
        _NoPosts(),
        GetIt.I<RealtimeSyncCase>(),
        env: const Env(),
        logger: Logger('post-create-entry-wiring'),
      ),
    );
  final homeAttention = HomeAttentionCubit(
    base.attention,
    base.accounts,
    Logger('post-create-entry-wiring'),
  );
  await tester.pumpWidget(
    _app(
      providers: [
        BlocProvider<InboxCubit>.value(
          value: _TestInboxCubit(
            const InboxState(status: StateIsSuccess(), projectionLoaded: true),
          ),
        ),
        BlocProvider<HomeAttentionCubit>.value(value: homeAttention),
        BlocProvider<HomeTabReselectCubit>(
          create: (_) => HomeTabReselectCubit(),
        ),
        BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(base.effects)),
      ],
      screen: BlocProvider(
        create: (_) => PostsCubit(postsCase: GetIt.I<PostsCase>()),
        child: canCreatePost == null
            ? const ConversationsScreen()
            : ConversationsScreen(canCreatePost: canCreatePost),
      ),
    ),
  );
  await _settle(tester);
  return base.effects;
}

Future<FakeUiEffectPort> _pumpMyWork(WidgetTester tester) async {
  final base = await _baseHarness(tester);
  GetIt.I
    ..registerSingleton<BeaconRepository>(FakeBeaconRepository())
    ..registerSingleton<ClosureRepository>(ClosureRepositoryMock());
  final repo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: [
        Beacon.empty.copyWith(
          id: 'beacon-1',
          title: 'Моя ответственность',
          updatedAt: DateTime.utc(2026, 9, 5),
          status: BeaconStatus.open,
        ),
      ],
      helpOfferedNonArchived: const [],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );
  final cubit = MyWorkCubit(
    userId: _accountId,
    myWorkCase: buildTestMyWorkCase(repo: repo, attentionCase: base.attention),
  );
  addTearDown(cubit.close);
  final homeActivation = HomeActivationCubit(_OrientationPrefs());
  await homeActivation.bindAccount(_accountId);
  homeActivation.reportMyWork(
    accountId: _accountId,
    myWorkCardCount: 1,
    draftCount: 0,
    archivedCountHint: 0,
    myWorkLoaded: true,
  );
  await tester.pumpWidget(
    _app(
      providers: [
        BlocProvider<MyWorkCubit>.value(value: cubit),
        BlocProvider<HomeActivationCubit>.value(value: homeActivation),
        BlocProvider<HomeAttentionCubit>.value(
          value: HomeAttentionCubit(
            base.attention,
            base.accounts,
            Logger('post-create-entry-wiring'),
          ),
        ),
        BlocProvider<InboxOperationalCubit>.value(
          value: InboxOperationalCubit()
            ..report(needsMeCount: 0, loadComplete: true),
        ),
        BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
        BlocProvider<HomeTabReselectCubit>(
          create: (_) => HomeTabReselectCubit(),
        ),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(base.effects)),
      ],
      screen: const MyWorkScreen(),
    ),
  );
  await _settle(tester);
  for (var i = 0; i < 24 && !cubit.state.isSuccess; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return base.effects;
}

Finder get _topBar => find.byType(TenturaTopBar);

Finder get _conversationsNewPost => find.descendant(
  of: _topBar,
  matching: find.widgetWithIcon(IconButton, Icons.add),
);

Finder get _myWorkPlus =>
    find.descendant(of: _topBar, matching: find.byIcon(Icons.add));

List<String> _pushed(FakeUiEffectPort effects) => [
  for (final e in effects.emitted.whereType<NavigatePush>()) e.path,
];

void main() {
  group('Conversations top bar', () {
    testWidgets('has no new-Post button while Posts are disabled', (
      tester,
    ) async {
      await _pumpConversations(tester, canCreatePost: false);

      expect(_conversationsNewPost, findsNothing);
    });

    testWidgets('«+» opens the Post create route when Posts are enabled', (
      tester,
    ) async {
      final effects = await _pumpConversations(tester, canCreatePost: true);

      expect(_conversationsNewPost, findsOneWidget);
      await tester.tap(_conversationsNewPost);
      await _settle(tester);

      expect(_pushed(effects), [kPathPostNew]);
    });
  });

  group('My Work «+»', () {
    // Work is about Requests; Posts start from Posts' own «+».
    testWidgets('creates a Request directly, with no Post choice', (
      tester,
    ) async {
      final effects = await _pumpMyWork(tester);

      await tester.tap(_myWorkPlus);
      await _settle(tester);

      expect(find.text('Пост'), findsNothing);
      expect(_pushed(effects), [kPathBeaconNew]);
    });
  });
}
