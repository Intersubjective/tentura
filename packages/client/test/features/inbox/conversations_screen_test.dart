// Conversations is a Home destination of its own: the viewer's Posts, with
// the chosen Post's chat beside the list on a wide window. Activity keeps
// only «Для вас», with no tabs. These tests run the real screens.

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
import 'package:tentura/features/home/ui/widget/conversations_navbar_item.dart';
import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/conversations_screen.dart';
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
  Size logicalSize = const Size(800, 800),
  bool conversations = true,
}) async {
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
          BlocProvider(create: (_) => PostsCubit(postsCase: postsCase)),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: logicalSize),
            child: TenturaResponsiveScope(
              child: conversations
                  ? ConversationsScreen(
                      postPaneBuilder: (id, onClose) =>
                          _FakePostPane(id: id, onClose: onClose),
                    )
                  : const InboxScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

class _FakePostPane extends StatelessWidget {
  const _FakePostPane({required this.id, required this.onClose});

  final String id;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    child: TextButton(onPressed: onClose, child: Text('chat:$id')),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _emitPostsChange() => _syncPort.emitChange(
  const RealtimeEntityChange(
    kind: RealtimeEntityKind.beacon,
    aggregateId: 'Pa',
    source: RealtimeChangeSource.serverInvalidation,
    operation: RealtimeOperation.update,
  ),
);

void main() {
  testWidgets('Activity shows «Для вас» alone, with no tabs', (tester) async {
    await _pumpInbox(tester, posts: [_unreadPost('Pa')], conversations: false);

    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(ActivityStreamView), findsOneWidget);
    expect(find.byType(PostsTabView), findsNothing);
  });

  testWidgets('Conversations lists the viewer\'s Posts', (tester) async {
    await _pumpInbox(tester, posts: [_unreadPost('Pa'), _unreadPost('Pb')]);

    expect(find.byType(PostsTabView), findsOneWidget);
    expect(find.byType(PostConversationRow), findsNWidgets(2));
  });

  testWidgets('compact: the account avatar sits in the top bar', (
    tester,
  ) async {
    await _pumpInbox(
      tester,
      posts: [_unreadPost('Pa')],
      logicalSize: const Size(390, 800),
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(HomeAccountAvatarButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('regular and wider: no avatar in the bar (the rail has it)', (
    tester,
  ) async {
    await _pumpInbox(tester, posts: [_unreadPost('Pa')]);
    expect(find.byType(HomeAccountAvatarButton), findsNothing);
  });

  testWidgets('a narrow window shows the list alone', (tester) async {
    await _pumpInbox(tester, posts: [_unreadPost('Pa')]);

    expect(find.byKey(TenturaListDetailLayout.listPaneKey), findsNothing);
  });

  testWidgets('reselecting Conversations scrolls the list to the top', (
    tester,
  ) async {
    await _pumpInbox(
      tester,
      posts: [for (var i = 0; i < 30; i++) _unreadPost('P$i')],
    );
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -600));
    await _settle(tester);
    final position = tester.state<ScrollableState>(list).position;
    expect(position.pixels, greaterThan(0));

    _reselect.bump(HomeTab.conversations);
    await _settle(tester);

    expect(position.pixels, 0);
  });

  group('Conversations nav dot', () {
    Finder dot() => find.descendant(
      of: find.byType(ConversationsNavbarItem),
      matching: find.byType(Badge),
    );

    testWidgets('shows while a Post has unread messages', (tester) async {
      await _pumpInbox(tester, posts: [_unreadPost('Pa', unreadCount: 0)]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(body: ConversationsNavbarItem()),
        ),
      );
      expect(dot(), findsNothing);

      _postsRepository.posts = [_unreadPost('Pa')];
      await GetIt.I<PostsCase>().myPosts();
      await tester.pump();
      expect(dot(), findsOneWidget);

      _postsRepository.posts = [_unreadPost('Pa', unreadCount: 0)];
      await GetIt.I<PostsCase>().myPosts();
      await tester.pump();
      await tester.pump();
      expect(dot(), findsNothing);
    });
  });

  group('wide window: list-detail', () {
    const wide = Size(1400, 900);
    final listPane = find.byKey(TenturaListDetailLayout.listPaneKey);

    bool rowSelected(WidgetTester tester, String id) =>
        tester.widget<PostConversationRow>(find.byKey(ValueKey(id))).selected;

    testWidgets('the list sits beside an empty chat pane', (tester) async {
      await _pumpInbox(tester, posts: [_unreadPost('Pa')], logicalSize: wide);

      expect(listPane, findsOneWidget);
      expect(tester.getSize(listPane).width, TenturaSpacing.listPaneWidth);
      expect(
        find.text(
          L10n.of(tester.element(listPane))!.postsTabSelectConversation,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a conversation opens in the pane, marked selected', (
      tester,
    ) async {
      await _pumpInbox(
        tester,
        posts: [_unreadPost('Pa'), _unreadPost('Pb')],
        logicalSize: wide,
      );

      await tester.tap(find.byKey(const ValueKey('Pb')));
      await _settle(tester);

      expect(find.text('chat:Pb'), findsOneWidget);
      expect(rowSelected(tester, 'Pb'), isTrue);
      expect(rowSelected(tester, 'Pa'), isFalse);
    });

    testWidgets('closing or losing the Post clears the pane', (tester) async {
      await _pumpInbox(
        tester,
        posts: [_unreadPost('Pa'), _unreadPost('Pb')],
        logicalSize: wide,
      );
      await tester.tap(find.byKey(const ValueKey('Pa')));
      await _settle(tester);

      await tester.tap(find.text('chat:Pa'));
      await _settle(tester);
      expect(find.text('chat:Pa'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('Pb')));
      await _settle(tester);
      _postsRepository.posts = [_unreadPost('Pa')];
      _emitPostsChange();
      await _settle(tester);
      expect(find.text('chat:Pb'), findsNothing);
    });
  });
}
