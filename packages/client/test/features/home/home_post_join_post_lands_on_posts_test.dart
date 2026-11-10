// After a Post invite is accepted, Home's post-join hand-off must leave the
// person on the Post they joined: the Posts tab is active, the Post's view is
// on screen (not the Posts tab's «Choose a post to open it here» pane), and
// the Post's General first page is fetched only while that view is mounted —
// the server records that fetch as the person's first open.
//
// Real RootRouter (routes, Home shell, tabs router), real HomeScreen with its
// HomePostJoinListener, real Post routes (kind gate → PostViewScope →
// ThreadHostCubit → RoomCubit) and real Posts tab screen. Other tab roots are
// stand-ins; repositories below the use cases are fakes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/entity/post_join_destination.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/domain/port/post_join_beacon_handoff_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/conversations_screen.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/env.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart';
import '../my_work/my_work_test_support.dart' show buildStubAttentionCase;

const _postId = kRoomCubitFakeBeaconId;
const _rootId = 'Mjoinroot001';
const _author = Profile(id: 'Ualice', displayName: 'Alice');
const _me = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Eve');
final _createdAt = DateTime.utc(2026, 11, 9, 9);

final _post = Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  author: _author,
  expiresAt: _createdAt.add(const Duration(hours: 72)),
  postRootMessageId: _rootId,
);

/// One General first-page fetch and whether a Post view was mounted then.
typedef _GeneralFetch = ({String beaconId, bool postViewMounted});

/// The Post's room. Records every General first-page fetch.
class _RoomRepository extends FakeBeaconThreadsRepository {
  _RoomRepository() : super(userId: _me.id) {
    messages = [
      RoomMessage(
        id: _rootId,
        beaconId: _postId,
        authorId: _author.id,
        author: _author,
        body: 'Weekend hike?',
        createdAt: _createdAt,
      ),
    ];
    participants = [
      BeaconParticipant(
        id: 'p-${_me.id}',
        beaconId: _postId,
        userId: _me.id,
        role: BeaconParticipantRoleBits.addressee,
        status: 0,
        roomAccess: RoomAccessBits.admitted,
        createdAt: _createdAt,
        updatedAt: _createdAt,
      ),
    ];
  }

  final generalFirstPages = <_GeneralFetch>[];

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) {
    final general =
        threadItemId == null || threadItemId == RequestThread.generalId;
    if (general && beforeIso == null) {
      generalFirstPages.add((
        beaconId: beaconId,
        postViewMounted: find
            .byType(PostViewScreen, skipOffstage: false)
            .evaluate()
            .isNotEmpty,
      ));
    }
    return super.fetchMessages(
      beaconId: beaconId,
      beforeIso: beforeIso,
      threadItemId: threadItemId,
    );
  }

  @override
  Future<List<RequestThread>> fetchThreads(String beaconId) async => [
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      lastSeenAt: _createdAt,
    ),
  ];
}

class _PostRepository implements BeaconRepository {
  final _changes = StreamController<RepositoryEvent<Beacon>>.broadcast();

  @override
  Future<void> dispose() => _changes.close();

  @override
  Stream<RepositoryEvent<Beacon>> get changes => _changes.stream;

  @override
  Future<Beacon> fetchBeaconById(String id) async => _post;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Kinds extends Fake implements BeaconKindRepository {
  @override
  Future<BeaconKind> fetchKind(String beaconId) async => BeaconKind.post;
}

class _ForwardRepository implements ForwardRepository {
  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The person's Posts: the one they just joined.
class _PostsRepository implements PostsRepositoryPort {
  static final _summary = PostSummary(
    id: _postId,
    authorId: _author.id,
    authorName: _author.displayName,
    lastActivityAt: _createdAt,
    participantCount: 2,
  );

  @override
  Future<List<PostSummary>> myPosts() async => [_summary];

  @override
  Future<PostSummary?> postSummary(String id) async =>
      id == _postId ? _summary : null;
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _me);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _AuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(updatedAt: DateTime.utc(2026, 11));

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _RouterAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(
    updatedAt: DateTime.utc(2026, 11),
    currentAccountId: _me.id,
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

class _Accounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

class _OrientationPreferences implements HomeOrientationPreferencesPort {
  @override
  Future<bool> isActivated({required String userId}) async => true;

  @override
  Future<bool> isOrientationDismissed({required String userId}) async => true;

  @override
  Future<OrientationDebugOverride> getDebugOverride() async =>
      OrientationDebugOverride.auto;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What the invite-accept flow left for Home to pick up.
class _Handoff implements PostJoinBeaconHandoffPort {
  _Handoff(this._destination);

  PostJoinDestination? _destination;

  @override
  PostJoinDestination? readAndClear() {
    final d = _destination;
    _destination = null;
    return d;
  }
}

PageInfo _page(String name, Widget child) =>
    PageInfo(name, builder: (_) => child);

/// Mounts the app's RootRouter on Home, as after a Post invite was accepted,
/// with [destination] waiting in the hand-off.
Future<({RootRouter router, _RoomRepository room})> _landOnHome(
  WidgetTester tester, {
  required PostJoinDestination destination,
  required Locale locale,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  final room = _RoomRepository();
  final posts = _PostRepository();
  final effects = FakeUiEffectPort();
  final screen = ScreenCubit.local(effects);
  final profile = _ProfileCubit();
  final postJoin = PostJoinNavigationCubit();
  final homeActivation = HomeActivationCubit(_OrientationPreferences());
  final homeAttention = HomeAttentionCubit(
    buildStubAttentionCase(),
    _Accounts(),
    Logger('post-join-home-attention'),
  );
  final inbox = InboxOperationalCubit();
  final reselect = HomeTabReselectCubit();
  getIt
    ..registerSingleton<AuthCubit>(_AuthCubit())
    ..registerSingleton<ScreenCubit>(screen)
    ..registerSingleton<HomeTabReselectCubit>(reselect)
    ..registerSingleton<InboxOperationalCubit>(inbox)
    ..registerSingleton<HomeActivationCubit>(homeActivation)
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<Logger>(Logger('post-join-home'))
    ..registerSingleton<HomeAttentionCubit>(homeAttention)
    ..registerSingleton<PostJoinNavigationCubit>(postJoin)
    ..registerSingleton<PostJoinBeaconHandoffPort>(_Handoff(destination))
    ..registerSingleton<ProfileCubit>(profile)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<ForwardRepository>(_ForwardRepository())
    ..registerSingleton<PostsRepositoryPort>(_PostsRepository())
    ..registerSingleton<PostsCase>(
      PostsCase(
        _PostsRepository(),
        sync.case_,
        env: const Env(),
        logger: Logger('post-join-posts'),
      ),
    )
    ..registerSingleton<BeaconRepository>(posts)
    ..registerSingleton<BeaconKindRepository>(_Kinds())
    ..registerSingleton<BeaconThreadsCase>(
      roomCubitMakeCase(room, realtimeSyncCase: sync.case_),
    )
    ..registerSingleton<CoordinationItemRoomSync>(CoordinationItemRoomSync())
    ..registerSingleton<PresenceRepository>(
      roomCubitFakePresenceRepository(),
    );

  final router = RootRouter(
    Logger('post-join-router'),
    _RouterAuthCubit(),
    _Settings(),
    postJoin,
  );
  getIt.registerSingleton<AppNavigator>(router);
  tester.binding.platformDispatcher.defaultRouteNameTestValue = kPathInbox;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
    await homeActivation.close();
    await homeAttention.close();
    await inbox.close();
    await reselect.close();
    await screen.close();
    await posts.dispose();
    await room.dispose();
    router.dispose();
    await getIt.reset();
  });
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: profile),
        BlocProvider<PresenceCubit>.value(
          value: RoomBodyHarnessPresenceCubit(),
        ),
        BlocProvider<ScreenCubit>.value(value: screen),
      ],
      child: MaterialApp.router(
        theme: TenturaTheme.light(),
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router.config(
          deepLinkBuilder: router.deepLinkBuilder,
          deepLinkTransformer: router.deepLinkTransformer,
          reevaluateListenable: router.reevaluateListenable,
          includePrefixMatches: false,
        ),
        // As the app does: effects (NavigatePush, ShowMessage) run through
        // the root effect handler and the router as AppNavigator.
        builder: (context, child) => UiEffectHandler(
          effects: effects,
          child: TenturaResponsiveScope(child: child!),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (router: router, room: room);
}

Future<void> _settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

int? _activeTab(RootRouter router) =>
    router.innerRouterOf<TabsRouter>(HomeRoute.name)?.activeIndex;

void _matrix({
  required String name,
  required Locale locale,
  required Size size,
}) {
  group('Post invite accepted, $name', () {
    Future<void> useSurface(WidgetTester tester) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets(
      'the joined Post is on screen over the Posts tab and its first page '
      'is fetched only while it is shown',
      (tester) async {
        await useSurface(tester);
        final (:router, :room) = await _landOnHome(
          tester,
          destination: const PostJoinDestination(
            beaconId: _postId,
            beaconTitle: 'Weekend hike?',
            inviterName: 'Alice',
            isPost: true,
          ),
          locale: locale,
        );
        // Long enough for any late navigation to replace the Post.
        await _settle(tester);
        expect(tester.takeException(), isNull);

        final l10n = lookupL10n(locale);
        expect(
          find.byType(PostViewScreen).hitTestable(),
          findsOneWidget,
          reason: 'the Post the person joined is what they see',
        );
        expect(
          tester.widget<PostViewScreen>(find.byType(PostViewScreen)).id,
          _postId,
        );
        expect(
          find.text(l10n.postsTabSelectConversation),
          findsNothing,
          reason: 'never the empty «Choose a post» pane',
        );

        expect(
          room.generalFirstPages,
          isNotEmpty,
          reason: 'opening the Post loads its General first page',
        );
        expect(
          room.generalFirstPages,
          everyElement(
            predicate<_GeneralFetch>(
              (f) => f.beaconId == _postId && f.postViewMounted,
              'fetched while the Post view was mounted',
            ),
          ),
        );
        expect(
          _activeTab(router),
          HomeTabSpec.forTab(HomeTab.conversations).index,
          reason: 'a Post opens from Posts, not Inbox',
        );
      },
    );

    testWidgets(
      'a hand-off without a Post fetches no Post first page',
      (tester) async {
        await useSurface(tester);
        final (:router, :room) = await _landOnHome(
          tester,
          destination: const PostJoinDestination(inviterName: 'Alice'),
          locale: locale,
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);

        expect(find.byType(PostViewScreen), findsNothing);
        expect(room.generalFirstPages, isEmpty);
        expect(
          _activeTab(router),
          HomeTabSpec.forTab(HomeTab.inbox).index,
          reason: 'Home stays where it was',
        );
      },
    );
  });
}

void main() {
  late Map<String, PageInfo> saved;

  setUpAll(() {
    saved = {
      MyWorkRoute.name: MyWorkRoute.page,
      ConversationsRoute.name: ConversationsRoute.page,
      InboxRoute.name: InboxRoute.page,
      ConstellationRoute.name: ConstellationRoute.page,
      FriendsRoute.name: FriendsRoute.page,
      ProfileRoute.name: ProfileRoute.page,
    };
    const empty = SizedBox.shrink();
    MyWorkRoute.page = _page(MyWorkRoute.name, empty);
    // The real Posts screen; signed-out Home has no Posts list provider, so
    // the page supplies the same cubit Home's shell would.
    ConversationsRoute.page = _page(
      ConversationsRoute.name,
      BlocProvider(
        create: (_) => PostsCubit(postsCase: GetIt.I<PostsCase>()),
        child: const ConversationsScreen(canCreatePost: false),
      ),
    );
    InboxRoute.page = _page(InboxRoute.name, empty);
    ConstellationRoute.page = _page(ConstellationRoute.name, empty);
    FriendsRoute.page = _page(FriendsRoute.name, empty);
    ProfileRoute.page = _page(ProfileRoute.name, empty);
  });

  tearDownAll(() {
    MyWorkRoute.page = saved[MyWorkRoute.name]!;
    ConversationsRoute.page = saved[ConversationsRoute.name]!;
    InboxRoute.page = saved[InboxRoute.name]!;
    ConstellationRoute.page = saved[ConstellationRoute.name]!;
    FriendsRoute.page = saved[FriendsRoute.name]!;
    ProfileRoute.page = saved[ProfileRoute.name]!;
  });

  _matrix(
    name: 'desktop 1280x800 (en)',
    locale: const Locale('en'),
    size: const Size(1280, 800),
  );
  _matrix(
    name: 'phone 375x667 (ru)',
    locale: const Locale('ru'),
    size: const Size(375, 667),
  );
}
