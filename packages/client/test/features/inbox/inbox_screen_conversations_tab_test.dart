// Activity has two tabs, «Для вас» and «Разговоры». These tests run the real
// `InboxScreen` and pin its tab wiring: «Для вас» is the default, «Разговоры»
// lists the viewer's Posts, reselecting the Activity nav item brings the user
// back to «Для вас», and the tab bar never carries an unread dot.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/features/inbox/ui/widget/posts_tab_view.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

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
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
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

class _AttentionRepo extends AttentionRepositoryFake {
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

final class _PostsRepository implements PostsRepositoryPort {
  _PostsRepository(this.posts);

  List<PostSummary> posts;

  @override
  Future<List<PostSummary>> myPosts() async => posts;

  @override
  Future<PostSummary?> postSummary(String id) async =>
      posts.where((p) => p.id == id).firstOrNull;
}

PostSummary _unreadPost(String id, {int unreadCount = 4}) => PostSummary(
  id: id,
  authorId: 'U$id',
  authorName: 'Анна',
  rootExcerpt: 'Посоветуйте стоматолога в центре',
  lastActivityAt: DateTime.now().toUtc(),
  unreadCount: unreadCount,
);

late HomeTabReselectCubit _reselect;
late _PostsRepository _postsRepository;
late TestRealtimeSyncPort _syncPort;

Future<void> _pumpInbox(
  WidgetTester tester, {
  List<PostSummary> posts = const [],
}) async {
  const logicalSize = Size(800, 800);
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  _syncPort = sync.port;
  final attention = AttentionCase(
    _AttentionRepo(),
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('inbox-conversations-tab-test'),
  );
  accounts.emit('viewer');
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }

  final inboxCase = buildTestInboxCase(
    FakeInboxRepository()..openForwardsCount = 0,
    buildTestBeaconThreadsCase(),
    forwardRepository: _ForwardRepo(),
  );
  _postsRepository = _PostsRepository(posts);
  final postsCase = PostsCase(
    _postsRepository,
    sync.case_,
    env: const Env(),
    logger: Logger('inbox-conversations-tab-test'),
  );

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attention);
  ensureNoopAttentionActorProfilesRegistered();
  GetIt.I.registerSingleton(inboxCase);
  GetIt.I.registerSingleton<PostsCase>(postsCase);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('inbox-conversations-tab-test'));
  }
  addTearDown(() async {
    await attention.dispose();
    await accounts.close();
    await sync.port.dispose();
    for (final unregister in <void Function()>[
      () => GetIt.I.unregister<AttentionCase>(),
      () => GetIt.I.unregister<InboxCase>(),
      () => GetIt.I.unregister<PostsCase>(),
      () => GetIt.I.unregister<InviteAcceptedSetupPort>(),
      () => GetIt.I.unregister<RealtimeSyncCase>(),
      () => GetIt.I.unregister<Logger>(),
    ]) {
      try {
        unregister();
      } on Object {
        // Not registered by this harness run.
      }
    }
  });

  final inboxCubit = _TestInboxCubit(
    const InboxState(status: StateIsSuccess(), projectionLoaded: true),
  );
  final homeAttention = HomeAttentionCubit(
    attention,
    accounts,
    Logger('inbox-conversations-tab-test'),
  );
  _reselect = HomeTabReselectCubit();

  await tester.pumpWidget(
    StackRouterScope(
      controller: _HarnessRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<InboxCubit>.value(value: inboxCubit),
          BlocProvider<HomeAttentionCubit>.value(value: homeAttention),
          BlocProvider<HomeTabReselectCubit>.value(value: _reselect),
          BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
          BlocProvider(create: (_) => ScreenCubit.local()),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: logicalSize),
            child: const TenturaResponsiveScope(child: InboxScreen()),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder get _tabBar => find.byType(TabBar);

Finder _tab(String label) =>
    find.descendant(of: _tabBar, matching: find.text(label));

int _selectedTabIndex(WidgetTester tester) =>
    tester.widget<TabBar>(_tabBar).controller!.index;

void main() {
  testWidgets('Activity offers the tabs «Для вас» and «Разговоры»', (
    tester,
  ) async {
    await _pumpInbox(tester);

    expect(_tabBar, findsOneWidget);
    expect(_tab('Для вас'), findsOneWidget);
    expect(_tab('Разговоры'), findsOneWidget);
  });

  testWidgets('Activity opens on «Для вас», not on «Разговоры»', (
    tester,
  ) async {
    await _pumpInbox(tester, posts: [_unreadPost('Pa')]);

    expect(_selectedTabIndex(tester), 0);
    expect(find.byType(ActivityStreamView), findsOneWidget);
    expect(find.byType(PostsTabView), findsNothing);
  });

  testWidgets('selecting «Разговоры» shows the viewer\'s Posts', (
    tester,
  ) async {
    await _pumpInbox(tester, posts: [_unreadPost('Pa')]);

    await tester.tap(_tab('Разговоры'));
    await _settle(tester);

    expect(_selectedTabIndex(tester), 1);
    expect(find.byType(PostsTabView), findsOneWidget);
    expect(find.byType(PostConversationRow), findsOneWidget);
  });

  testWidgets('reselecting the Activity nav item returns to «Для вас»', (
    tester,
  ) async {
    await _pumpInbox(tester, posts: [_unreadPost('Pa')]);
    await tester.tap(_tab('Разговоры'));
    await _settle(tester);
    expect(_selectedTabIndex(tester), 1);

    _reselect.bump(HomeTab.inbox);
    await _settle(tester);

    expect(_selectedTabIndex(tester), 0);
    expect(find.byType(ActivityStreamView), findsOneWidget);
  });

  testWidgets('reselecting the Activity nav item on «Для вас» keeps it there', (
    tester,
  ) async {
    await _pumpInbox(tester);

    _reselect.bump(HomeTab.inbox);
    await _settle(tester);

    expect(_selectedTabIndex(tester), 0);
  });

  testWidgets('unread conversations show a dot before opening the tab', (
    tester,
  ) async {
    await _pumpInbox(tester, posts: [_unreadPost('Pa'), _unreadPost('Pb')]);
    final badge = tester.widget<Badge>(
      find.descendant(of: _tabBar, matching: find.byType(Badge)),
    );
    expect(badge.isLabelVisible, isTrue);
    expect(badge.label, isNull);
    expect(_selectedTabIndex(tester), 0);
    await tester.tap(_tab('Разговоры'));
    await _settle(tester);
    expect(
      tester.widget<Badge>(find.byType(Badge).first).isLabelVisible,
      isTrue,
    );
  });

  testWidgets('read conversations and empty list have no visible dot', (
    tester,
  ) async {
    await _pumpInbox(tester, posts: [_unreadPost('Pa', unreadCount: 0)]);
    final badge = find.descendant(of: _tabBar, matching: find.byType(Badge));
    expect(tester.widget<Badge>(badge).isLabelVisible, isFalse);
    _postsRepository.posts = [];
    _syncPort.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.beacon,
        aggregateId: 'Pa',
        source: RealtimeChangeSource.serverInvalidation,
        operation: RealtimeOperation.update,
      ),
    );
    await _settle(tester);
    expect(tester.widget<Badge>(badge).isLabelVisible, isFalse);
  });

  testWidgets('conversation dot updates when unread messages change', (
    tester,
  ) async {
    await _pumpInbox(tester, posts: [_unreadPost('Pa', unreadCount: 0)]);
    final badge = find.descendant(of: _tabBar, matching: find.byType(Badge));
    for (final count in [4, 0]) {
      _postsRepository.posts = [_unreadPost('Pa', unreadCount: count)];
      _syncPort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.beacon,
          aggregateId: 'Pa',
          source: RealtimeChangeSource.serverInvalidation,
          operation: RealtimeOperation.update,
        ),
      );
      await _settle(tester);
      expect(tester.widget<Badge>(badge).isLabelVisible, count > 0);
    }
  });
}
