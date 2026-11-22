import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/util/burst_coalescer.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/beacon_detail_path.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_loading_shell.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/conversations_screen.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';

import '../../support/attention_case_factory.dart';
import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/beacon_create_case_factory.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/post_root_pin_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_scope.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/forward_outcome_wire.dart';
import '../../support/posts_case_test_support.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_hint_wire_harness.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit;
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_screen_harness.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/mark_unread_server_fake.dart';
import '../updates/support/noop_invite_setup_port.dart';

const _postId = 'Bpostroute001';
const _firstReply = 'Mpost0000001';
const _secondReply = 'Mpost0000002';
const _unknownReply = 'Mpostmissing';
const _postUrl = '/post/view/$_postId';
const _messageLinkTests = 'Post chat message links';
const _requestId = 'Brequestroute01';
const _viewer = Profile(id: 'Uviewer', displayName: 'Viewer');
const _author = Profile(id: 'Uauthor', displayName: 'Author');

Beacon _beacon(String id, BeaconKind kind) => Beacon(
  id: id,
  title: 'Route beacon',
  kind: kind,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  author: _author,
);

/// Serves only the beacon itself; every other repository call throws, which
/// proves the Post path never reaches Request-only data.
class _BeaconOnlyRepository implements BeaconRepository {
  _BeaconOnlyRepository(this.beacons);

  final Map<String, Beacon> beacons;
  final List<String> fetched = [];

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async {
    fetched.add(id);
    return beacons[id]!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Request-only call: ${invocation.memberName}');
}

class _FakeBeaconKindRepository implements BeaconKindRepository {
  _FakeBeaconKindRepository(this.kinds, {this.lookupGates = const {}});

  final Map<String, BeaconKind> kinds;
  final Map<String, Completer<void>> lookupGates;
  final List<String> requested = [];
  final Completer<void> gate = Completer<void>();
  bool gated = false;

  @override
  Future<BeaconKind> fetchKind(String beaconId) async {
    requested.add(beaconId);
    if (gated) await gate.future;
    await lookupGates[beaconId]?.future;
    return kinds[beaconId]!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime(2026), currentAccountId: _viewer.id);

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

/// Minimal router mounting the production host page and its operational child.
class _TestRouter extends RootStackRouter {
  _TestRouter({this.conversations});

  final Widget? conversations;

  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: conversations == null
          ? ConversationsRoute.page
          : PageInfo(ConversationsRoute.name, builder: (_) => conversations!),
      path: '/conversations',
    ),
    AutoRoute(
      page: BeaconViewRoute.page,
      path: '/beacon/view/:id',
      children: [
        AutoRoute(
          page: BeaconViewOperationalRoute.page,
          path: '',
          initial: true,
        ),
      ],
    ),
    AutoRoute(
      page: PostViewRoute.page,
      path: '/post/view/:id',
      children: [
        AutoRoute(
          page: BeaconViewOperationalRoute.page,
          path: '',
          initial: true,
        ),
      ],
    ),
  ];
}

Future<void> _register<T extends Object>(T instance) async {
  if (GetIt.I.isRegistered<T>()) await GetIt.I.unregister<T>();
  GetIt.I.registerSingleton<T>(instance);
}

/// Pumps the real route for [id]. Request-only collaborators are registered
/// only when [withRequestCollaborators] is set, so a Post that touches them
/// fails with a GetIt error.
Future<RootStackRouter> _pumpRoute(
  WidgetTester tester, {
  required String id,
  required _FakeBeaconKindRepository kinds,
  required BeaconRepository beacons,
  bool withRequestCollaborators = false,
  bool withThrowingRequestCollaborators = false,
  PostsCase? activityCase,
  HomeTabReselectCubit? homeReselect,
  FakeBeaconThreadsRepository? roomRepo,
  RootRouter? rootRouter,
  String? initialLocation,
  bool phoneRu = false,
  Widget? home,
  Widget? conversations,
  UiEffectPort? effects,
}) async {
  _requestOnlyTouches.clear();
  await registerBeaconViewHarnessGetIt(profile: _viewer, roomRepo: roomRepo);
  if (effects != null) await _register<UiEffectPort>(effects);
  await _register<BeaconKindRepository>(kinds);
  await _register<BeaconRepository>(beacons);
  if (withRequestCollaborators) {
    // The Request room opened after conversion builds a RoomCubit from DI.
    await _register<CoordinationItemRoomSync>(CoordinationItemRoomSync());
    await _register<PresenceRepository>(roomCubitFakePresenceRepository());
  }
  if (withThrowingRequestCollaborators) {
    await _register<BeaconHierarchyCase>(_ThrowingBeaconHierarchyCase());
  }
  if (withRequestCollaborators) {
    await _register<BeaconViewCase>(
      buildTestBeaconViewCase(beaconRepo: beacons),
    );
    await _register<BeaconHierarchyCase>(
      buildBeaconHierarchyCaseForTest(
        FakeBeaconHierarchyRepositoryPort(
          capabilities: const BeaconHierarchyCapabilities(
            canListChildren: false,
            canCreateChild: false,
          ),
        ),
        createCase: buildBeaconCreateCase(
          beacons: _NoopWritePort(),
          images: ImageRepository(),
        ),
        beacons: _NoopWritePort(),
        commandStore: InMemoryBeaconChildCommandStore(),
      ),
    );
  }
  addTearDown(() async {
    for (final unregister in [
      () => GetIt.I.unregister<BeaconKindRepository>(),
      () => GetIt.I.unregister<BeaconRepository>(),
      if (withRequestCollaborators) () => GetIt.I.unregister<BeaconViewCase>(),
      if (withRequestCollaborators)
        () => GetIt.I.unregister<CoordinationItemRoomSync>(),
      if (withRequestCollaborators)
        () => GetIt.I.unregister<PresenceRepository>(),
      if (withRequestCollaborators || withThrowingRequestCollaborators)
        () => GetIt.I.unregister<BeaconHierarchyCase>(),
    ]) {
      await unregister();
    }
    await unregisterBeaconViewHarnessGetIt();
  });
  final router = rootRouter ?? _TestRouter(conversations: conversations);
  if (rootRouter != null) {
    final homePage = HomeRoute.page;
    HomeRoute.page = PageInfo(
      HomeRoute.name,
      builder: (_) => Scaffold(body: home ?? const Text('Home')),
    );
    addTearDown(() => HomeRoute.page = homePage);
    await _register<AppNavigator>(rootRouter);
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        initialLocation!;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
  }
  // A compact window throughout: surface and MediaQuery agree, so the route
  // does not render regular-window chrome (the rail) into a phone-wide box.
  tester.view
    ..physicalSize = activityCase == null
        ? (phoneRu ? kPhoneSurface : kBeaconViewHarnessCompact)
        : kBeaconViewHarnessExpanded
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget app = MaterialApp.router(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: Locale(phoneRu ? 'ru' : 'en'),
    builder: (_, child) => TenturaResponsiveScope(
      child: effects == null
          ? child!
          : UiEffectHandler(effects: effects, child: child!),
    ),
    routerConfig: rootRouter != null
        ? rootRouter.config(
            deepLinkBuilder: rootRouter.deepLinkBuilder,
            deepLinkTransformer: rootRouter.deepLinkTransformer,
            reevaluateListenable: rootRouter.reevaluateListenable,
            includePrefixMatches: false,
          )
        : router.config(
            deepLinkBuilder: (_) => DeepLink([
              if (activityCase == null)
                BeaconViewRoute(id: id)
              else
                ConversationsRoute(),
            ]),
          ),
  );
  if (activityCase != null) {
    app = MultiBlocProvider(
      providers: [
        if (homeReselect == null)
          BlocProvider(create: (_) => HomeTabReselectCubit())
        else
          BlocProvider.value(value: homeReselect),
        BlocProvider(create: (_) => ScreenCubit.local()),
        BlocProvider(create: (_) => PostsCubit(postsCase: activityCase)),
      ],
      child: app,
    );
  }
  if (roomRepo != null) {
    app = BlocProvider<PresenceCubit>.value(
      value: RoomBodyHarnessPresenceCubit(),
      child: app,
    );
  }
  await tester.pumpWidget(
    BlocProvider<ProfileCubit>.value(
      value: _ProfileCubit(),
      child: app,
    ),
  );
  return router;
}

/// Request-only collaborators: any touch is recorded and throws.
final List<String> _requestOnlyTouches = [];

class _ThrowingBeaconHierarchyCase implements BeaconHierarchyCase {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    _requestOnlyTouches.add('BeaconHierarchyCase.${invocation.memberName}');
    throw StateError('Request-only BeaconHierarchyCase touched');
  }
}

class _NoopWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<RootRouter> _pumpDetailRoot(
  WidgetTester tester,
  String location, {
  Widget? home,
  UiEffectPort? effects,
  Map<String, Completer<void>> lookupGates = const {},
  FakeBeaconThreadsRepository? roomRepo,
  bool phoneRu = false,
  String? postRootMessageId,
}) async {
  final router = RootRouter(
    Logger('PostDetailLinks'),
    _Auth(),
    _Settings(),
    PostJoinNavigationCubit(),
  );
  addTearDown(router.dispose);
  final kinds = _FakeBeaconKindRepository({
    _postId: BeaconKind.post,
    _requestId: BeaconKind.request,
  }, lookupGates: lookupGates);
  final beacons = TrackingBeaconRepository()
    ..fetchByIdHandler = (id) async => _beacon(id, kinds.kinds[id]!).copyWith(
      postRootMessageId: id == _postId ? postRootMessageId : null,
    );
  addTearDown(beacons.dispose);
  await _pumpRoute(
    tester,
    id: _postId,
    kinds: kinds,
    beacons: beacons,
    withRequestCollaborators: true,
    rootRouter: router,
    initialLocation: location,
    roomRepo: roomRepo,
    phoneRu: phoneRu,
    home: home,
    effects: effects,
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _expectDetail(
  WidgetTester tester,
  RootRouter router,
  String id,
  String prefix,
  Type screen,
  Map<String, Completer<void>> gates,
) async {
  // Read the destination before the kind lookup unblocks. At that point a
  // mistaken legacy path cannot pass by being rewritten by the detail screen.
  await tester.pump();
  final path = '$prefix/$id';
  expect(Uri.parse(router.currentUrl).path, path);
  gates[id]!.complete();
  await tester.pumpAndSettle();
  expect(find.byType(screen), findsOneWidget);
  expect(Uri.parse(router.currentUrl).path, path);
}

class _ViewerAccount implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => Stream.value(_viewer.id);
}

Future<List<AttentionReceipt>> _wireAttentionReceipts() =>
    mapStreamRowsThroughRepository([
      for (final (id, kind, title) in [
        (_postId, BeaconKind.post, 'A shared Post'),
        (_requestId, BeaconKind.request, 'A forwarded Request'),
      ])
        {
          ...attentionStreamRowWire(
            id: 'receipt-$id',
            itemKind: 'receipt',
            beaconId: id,
            createdAt: '2026-10-31T00:10:00.000Z',
            kind: 'newRelay',
            title: title,
            presentationPayloadJson: '{"eventType":"relayReceived"}',
          ),
          'presentationKey': 'relay_received',
          'beaconKind': kind.value,
        },
    ]);

mixin _PostGeneralChat on FakeBeaconThreadsRepository {
  @override
  Future<List<RequestThread>> fetchThreads(String beaconId) async => [
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      lastSeenAt: DateTime.utc(2026, 1, 1, 13),
    ),
  ];
}

class _PostChatRepository extends FakeBeaconThreadsRepository
    with _PostGeneralChat {
  _PostChatRepository() : super(userId: _viewer.id);

  final requestedTargets = <String>[];

  @override
  Future<RoomMessage?> fetchMessageTarget({
    required String beaconId,
    required String messageId,
  }) {
    requestedTargets.add(messageId);
    return super.fetchMessageTarget(beaconId: beaconId, messageId: messageId);
  }
}

class _WirePostChatRepository extends RoomOverRealHintWireRepository
    with _PostGeneralChat {
  _WirePostChatRepository(super._real);
}

class _PostChatPageRecorder extends _WirePostChatRepository {
  _PostChatPageRecorder(super._real);

  final pages = <List<RoomMessage>>[];

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) async {
    final page = await super.fetchMessages(
      beaconId: beaconId,
      beforeIso: beforeIso,
      threadItemId: threadItemId,
    );
    pages.add(List.of(page));
    return page;
  }
}

class _LinkedPostChatRepository extends _WirePostChatRepository {
  _LinkedPostChatRepository(super._real);

  final targetLookupFinished = Completer<void>();

  @override
  Future<RoomMessage?> fetchMessageTarget({
    required String beaconId,
    required String messageId,
  }) async {
    try {
      return await super.fetchMessageTarget(
        beaconId: beaconId,
        messageId: messageId,
      );
    } finally {
      if (!targetLookupFinished.isCompleted) targetLookupFinished.complete();
    }
  }
}

_PostChatRepository _postChat({
  List<String> ids = const [_firstReply, _secondReply],
}) => _PostChatRepository()
  ..messages = [
    for (final (index, id) in ids.indexed)
      RoomMessage(
        id: id,
        beaconId: _postId,
        authorId: _author.id,
        author: _author,
        body: 'Reply ${index + 1}',
        createdAt: DateTime.utc(2026, 1, 1, 12, index),
      ),
  ];

Finder _tile(String id) => find.byWidgetPredicate(
  (widget) => widget is RoomMessageTile && widget.message.id == id,
  description: 'chat tile for $id',
);

String? _visibleHighlight(WidgetTester tester, String id) {
  final tile = _tile(id).hitTestable();
  if (tile.evaluate().isEmpty) return null;
  return tester.widget<RoomMessageTile>(tile).highlightedMessageId?.value;
}

Future<String?> _waitForHighlight(WidgetTester tester, String id) async {
  // Observe the flash while it is active, with a bounded wait on a red run.
  for (var frame = 0; frame < 90; frame++) {
    final highlighted = _visibleHighlight(tester, id);
    if (highlighted == id) return highlighted;
    await tester.pump(const Duration(milliseconds: 16));
  }
  return _visibleHighlight(tester, id);
}

void _expectUnfocusedChat(WidgetTester tester) {
  expect(find.byType(PostViewScreen), findsOneWidget);
  expect(_tile(_secondReply).hitTestable(), findsOneWidget);
  final chat = tester.widget<BasicChatBody>(find.byType(BasicChatBody));
  expect(chat.hasError, isFalse);
  expect(chat.isLoading, isFalse);
  final chatState = tester.state<BasicChatBodyState>(
    find.byType(BasicChatBody),
  );
  expect(chatState.highlightedMessageId.value, isNull);
}

const _openingMessageId = 'Mpostopening';
const _openingBody = 'Начало поста';
const _rootLink =
    '$_postUrl?is_deep_link=true&tab=threads&thread=general&message=$_openingMessageId';
const _frame = Duration(milliseconds: 16);

final _expandedOpening = find.byKey(const Key('PostRootPinCard.expanded'));
final _collapsedOpening = find.byKey(const Key('PostRootPinCard.collapsed'));
final _openingCard = find.byType(PostRootPinCard);
final _chat = find.byType(BasicChatBody);
final _replyList = find.descendant(of: _chat, matching: find.byType(ListView));

String _numberedReplyId(int number) =>
    'Mpostreply${number.toString().padLeft(3, '0')}';

Map<String, dynamic> _postMessageRow(String id, String body, int minute) =>
    roomHintWireMessageRow(
      id: id,
      authorId: _author.id,
      authorTitle: _author.displayName,
      createdAt: DateTime.utc(2026, 1, 1, 12, minute).toIso8601String(),
      body: body,
    )..['beaconId'] = _postId;

Future<_WirePostChatRepository> _wirePostRoom(
  WidgetTester tester,
  RoomHintWireServer server,
) async {
  final wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
  addTearDown(() => tester.runAsync(wire.close));
  return _WirePostChatRepository(wire.repository);
}

BasicChatBodyState _chatState(WidgetTester tester) =>
    tester.state<BasicChatBodyState>(_chat);

ScrollPosition _replyScroll(WidgetTester tester) =>
    tester.widget<ListView>(_replyList).controller!.position;

void _expectOnlyOpeningCard(WidgetTester tester, int replies) {
  expect(_tile(_openingMessageId), findsNothing);
  expect(
    tester.widget<BasicChatBody>(_chat).messages.map((m) => m.id),
    isNot(contains(_openingMessageId)),
  );
  final card = tester.widget<PostRootPinCard>(_openingCard);
  expect(card.pin.messageId, _openingMessageId);
  expect(card.replyCount, replies);
}

List<Object> _openingAppearance() => [
  for (final element
      in find
          .descendant(
            of: _openingCard,
            matching: find.byWidgetPredicate((_) => true),
          )
          .evaluate())
    switch (element.widget) {
      Material(:final color, :final shape) => (color, shape),
      DecoratedBox(:final decoration) => decoration,
      ColoredBox(:final color) => color,
      Ink(:final decoration) => decoration,
      Opacity(:final opacity) => opacity,
      RichText(:final text) => text.style,
      _ => null,
    },
].whereType<Object>().toList();

Future<String?> _waitForChatSelection(WidgetTester tester, String id) async {
  for (var frame = 0; frame < 90; frame++) {
    final selected = _chatState(tester).highlightedMessageId.value;
    if (selected == id) return selected;
    await tester.pump(_frame);
  }
  return _chatState(tester).highlightedMessageId.value;
}

Future<Duration> _remainingFlash(WidgetTester tester, String id) async {
  final start = tester.binding.clock.now();
  for (var frame = 0; frame < 100; frame++) {
    if (_chatState(tester).highlightedMessageId.value == null) {
      return tester.binding.clock.now().difference(start);
    }
    expect(_chatState(tester).highlightedMessageId.value, id);
    await tester.pump(_frame);
  }
  fail('Message $id was still highlighted after 1600 ms');
}

class _ConversationPosts implements PostsRepositoryPort {
  _ConversationPosts({this.otherPostCount = 0});

  final int otherPostCount;
  final post = PostSummary(
    id: _postId,
    authorId: _author.id,
    authorName: _author.displayName,
    rootExcerpt: _openingBody,
    lastActivityAt: DateTime.utc(2026, 1, 1, 12),
  );

  @override
  Future<List<PostSummary>> myPosts() async => [
    post,
    for (var i = 0; i < otherPostCount; i++)
      PostSummary(
        id: 'Bconversation$i',
        authorId: _author.id,
        authorName: _author.displayName,
        rootExcerpt: 'Conversation $i',
        lastActivityAt: post.lastActivityAt.subtract(Duration(minutes: i + 1)),
      ),
  ];

  @override
  Future<PostSummary?> postSummary(String id) async =>
      id == post.id ? post : null;
}

class _ConversationLinkDispatch extends HomeTabReselectCubit {
  final results = <({String postId, String messageId, bool handled})>[];

  @override
  bool openConversationMessage(String postId, String messageId) {
    final handled = super.openConversationMessage(postId, messageId);
    results.add((postId: postId, messageId: messageId, handled: handled));
    return handled;
  }
}

final _conversationList = find.descendant(
  of: find.byKey(TenturaListDetailLayout.listPaneKey),
  matching: find.byType(ListView),
);
final _selectedPostRow = find.descendant(
  of: _conversationList,
  matching: find.byKey(const ValueKey(_postId)),
);
final _postScreen = find.byType(PostViewScreen);

enum _OpeningMessageAvailability { loaded, fetchable, absent }

Future<({RootRouter router, _ConversationLinkDispatch dispatch})>
_pumpWideConversation(WidgetTester tester, RoomHintWireServer server) async {
  final repo = await _wirePostRoom(tester, server);
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  final dispatch = _ConversationLinkDispatch();
  await _register<HomeTabReselectCubit>(dispatch);
  addTearDown(() async {
    await GetIt.I.unregister<HomeTabReselectCubit>();
    await dispatch.close();
  });
  final router = RootRouter(
    Logger('ConversationMessageLinks'),
    _Auth(),
    _Settings(),
    PostJoinNavigationCubit(),
  );
  addTearDown(router.dispose);
  await _pumpRoute(
    tester,
    id: _postId,
    kinds: _FakeBeaconKindRepository({_postId: BeaconKind.post}),
    beacons: _BeaconOnlyRepository({
      _postId: _beacon(
        _postId,
        BeaconKind.post,
      ).copyWith(postRootMessageId: _openingMessageId),
    }),
    withRequestCollaborators: true,
    activityCase: buildTestPostsCase(
      _ConversationPosts(otherPostCount: 24),
      sync.case_,
    ),
    homeReselect: dispatch,
    roomRepo: repo,
    rootRouter: router,
    initialLocation: kPathConversations,
    home: AutoTabsRouter(
      routes: [for (final spec in HomeTabSpec.all) spec.shell()],
      duration: Duration.zero,
      transitionBuilder: (_, child, _) => child,
      builder: (_, child) => child,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(_selectedPostRow);
  await tester.pumpAndSettle();
  expect(_postScreen, findsOneWidget);
  expect(server.queried, contains('RoomMessageList'));
  return (router: router, dispatch: dispatch);
}

Future<void> _deliverConversationLink(
  WidgetTester tester,
  RootRouter router,
  _ConversationLinkDispatch dispatch,
  String messageId,
) async {
  final previousCount = dispatch.results.length;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {
        'location': '$_postUrl?message=$messageId',
      }),
    ),
    (_) {},
  );
  await tester.pumpAndSettle(
    _frame,
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
  expect(
    dispatch.results.skip(previousCount),
    [(postId: _postId, messageId: messageId, handled: true)],
  );
  expect(router.stackData.map((route) => route.name), [HomeRoute.name]);
}

Future<void> _waitForConversationHighlightToClear(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1200));
  expect(_chatState(tester).highlightedMessageId.value, isNull);
  expect(tester.widget<PostRootPinCard>(_openingCard).highlighted, isFalse);
}

void main() {
  group('Message links in the wide Conversations pane', () {
    testWidgets(
      'reply links restore the target highlight and viewport on every open',
      (tester) async {
        const latestReply = 25;
        final olderReply = _numberedReplyId(1);
        final newerReply = _numberedReplyId(latestReply);
        final server = RoomHintWireServer()
          ..messageRows = [
            _postMessageRow(_openingMessageId, _openingBody, 0),
            for (var i = 1; i <= latestReply; i++)
              _postMessageRow(_numberedReplyId(i), 'Reply $i', i),
          ];
        final (:router, :dispatch) = await _pumpWideConversation(
          tester,
          server,
        );

        final listPosition = tester
            .widget<ListView>(_conversationList)
            .controller!
            .position;
        const listOffset = 24.0;
        expect(listPosition.maxScrollExtent, greaterThan(listOffset));
        listPosition.jumpTo(listOffset);
        await tester.pumpAndSettle();
        final noConversation = L10n.of(
          tester.element(_conversationList),
        )!.postsTabSelectConversation;
        final locationResults = <({String? highlight, bool visible})>[];
        final targets = [
          olderReply,
          olderReply,
          olderReply,
          newerReply,
          olderReply,
        ];
        for (final target in targets) {
          final position = _replyScroll(tester);
          position.jumpTo(
            target == olderReply
                ? position.maxScrollExtent
                : position.minScrollExtent,
          );
          await tester.pumpAndSettle();
          final targetBubble = _tile(
            target,
          ).hitTestable(at: const Alignment(-0.65, 0));
          expect(targetBubble, findsNothing);

          await _deliverConversationLink(tester, router, dispatch, target);
          locationResults.add((
            highlight: _chatState(tester).highlightedMessageId.value,
            visible: targetBubble.evaluate().isNotEmpty,
          ));
          expect(
            tester.widget<PostViewScreen>(_postScreen).id,
            _postId,
          );
          expect(find.text(noConversation), findsNothing);
          expect(
            tester.widget<PostConversationRow>(_selectedPostRow).selected,
            isTrue,
          );
          expect(
            tester.widget<ListView>(_conversationList).controller!.offset,
            closeTo(listOffset, 1),
          );
          await _waitForConversationHighlightToClear(tester);
        }
        expect(locationResults, [
          for (final target in targets) (highlight: target, visible: true),
        ]);
      },
    );

    for (final availability in _OpeningMessageAvailability.values) {
      testWidgets(
        switch (availability) {
          _OpeningMessageAvailability.loaded =>
            'opening-message links expand and highlight the card on every open',
          _OpeningMessageAvailability.fetchable =>
            'opening-message links expand and highlight the card beyond the loaded page',
          _OpeningMessageAvailability.absent =>
            'opening-message links expand and highlight the card when the root stays outside the room messages',
        },
        (tester) async {
          final opening = _postMessageRow(_openingMessageId, _openingBody, 0);
          final server = RoomHintWireServer()
            ..messageRows = [
              if (availability == _OpeningMessageAvailability.loaded) opening,
              for (var i = 1; i <= 25; i++)
                _postMessageRow(_numberedReplyId(i), 'Reply $i', i),
            ];
          if (availability == _OpeningMessageAvailability.fetchable) {
            server.messageTargets[_openingMessageId] = opening;
          }
          final (:router, :dispatch) = await _pumpWideConversation(
            tester,
            server,
          );
          final room = tester
              .element(_postScreen)
              .read<ThreadHostCubit>()
              .roomCubit!;
          expect(
            room.state.messages.any((m) => m.id == _openingMessageId),
            availability == _OpeningMessageAvailability.loaded,
          );
          final openingResults = <({bool expanded, bool highlighted})>[];
          for (var open = 0; open < 2; open++) {
            final position = _replyScroll(tester);
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(_collapsedOpening, findsOneWidget);

            await _deliverConversationLink(
              tester,
              router,
              dispatch,
              _openingMessageId,
            );
            openingResults.add((
              expanded: _expandedOpening.hitTestable().evaluate().isNotEmpty,
              highlighted: tester
                  .widget<PostRootPinCard>(_openingCard)
                  .highlighted,
            ));
            await _waitForConversationHighlightToClear(tester);
          }
          expect(openingResults, [
            (expanded: true, highlighted: true),
            (expanded: true, highlighted: true),
          ]);
        },
      );
    }
  });

  group('Links to the Post opening message', () {
    testWidgets(
      'a phone deep link flashes the opening card above two replies',
      (
        tester,
      ) async {
        final server = RoomHintWireServer()
          ..messageRows = [
            _postMessageRow(_openingMessageId, _openingBody, 0),
            _postMessageRow(_firstReply, 'Первый ответ', 1),
            _postMessageRow(_secondReply, 'Второй ответ', 2),
          ];
        final repo = await _wirePostRoom(tester, server);
        final router = await _pumpDetailRoot(
          tester,
          _rootLink,
          roomRepo: repo,
          postRootMessageId: _openingMessageId,
          phoneRu: true,
        );

        expect(router.currentUrl, _rootLink);
        expect(find.byType(PostViewScreen), findsOneWidget);
        expect(server.queried, contains('RoomMessageList'));
        expect(_expandedOpening.hitTestable(), findsOneWidget);
        expect(_tile(_firstReply).hitTestable(), findsOneWidget);
        expect(_tile(_secondReply).hitTestable(), findsOneWidget);
        final card = tester.widget<PostRootPinCard>(_openingCard);
        final l10n = L10n.of(tester.element(_openingCard))!;
        expect(l10n.localeName, 'ru');
        expect(
          find
              .descendant(
                of: _expandedOpening,
                matching: find.textContaining(
                  RegExp('^$_openingBody\uFFFC?\$'),
                ),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(
          find.text(
            card.forwardPolicyOpen
                ? l10n.postCardMetaCanShare(card.peopleCount!, 2)
                : l10n.postCardMetaInviteOnly(card.peopleCount!, 2),
          ),
          findsOneWidget,
        );
        _expectOnlyOpeningCard(tester, 2);
        expect(tester.takeException(), isNull);

        expect(
          await _waitForChatSelection(tester, _openingMessageId),
          _openingMessageId,
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          _chatState(tester).highlightedMessageId.value,
          _openingMessageId,
        );
        final flashing = _openingAppearance();
        await _remainingFlash(tester, _openingMessageId);
        await tester.pumpAndSettle();
        expect(_openingAppearance(), isNot(equals(flashing)));
        _expectOnlyOpeningCard(tester, 2);

        final resting = _openingAppearance();
        await router.navigatePath('$_postUrl?message=$_firstReply');
        await tester.pump();
        expect(await _waitForHighlight(tester, _firstReply), _firstReply);
        await tester.pump(_frame);
        expect(_openingAppearance(), equals(resting));
        await _remainingFlash(tester, _firstReply);

        await router.navigatePath('$_postUrl?message=$_unknownReply');
        await tester.pumpAndSettle();
        // The final GraphQL response can schedule Ferry's zero-delay cleanup
        // without scheduling a Flutter frame.
        await tester.pump(_frame);
        _expectUnfocusedChat(tester);
      },
    );

    for (final rootIsInLatestPage in [true, false]) {
      testWidgets(
        rootIsInLatestPage
            ? 'a deep link opens a long Post chat at the opening card'
            : 'a deep link opens the opening card beyond the latest reply page',
        (tester) async {
          final replyCount = rootIsInLatestPage ? 25 : 50;
          final opening = _postMessageRow(_openingMessageId, _openingBody, 0);
          final server = RoomHintWireServer()
            ..messageRows = [
              if (rootIsInLatestPage) opening,
              for (var i = 1; i <= replyCount; i++)
                _postMessageRow(_numberedReplyId(i), 'Ответ $i', i),
            ]
            ..messageTargets[_openingMessageId] = opening;
          final repo = await _wirePostRoom(tester, server);
          await _pumpDetailRoot(
            tester,
            _rootLink,
            roomRepo: repo,
            postRootMessageId: _openingMessageId,
            phoneRu: true,
          );

          expect(find.byType(PostViewScreen), findsOneWidget);
          expect(server.queried, contains('RoomMessageList'));
          expect(_replyScroll(tester).maxScrollExtent, greaterThan(0));
          expect(
            tester.widget<BasicChatBody>(_chat).messages.map((m) => m.id),
            containsAll([_numberedReplyId(1), _numberedReplyId(replyCount)]),
          );
          _expectOnlyOpeningCard(tester, replyCount);

          // Read all three outcomes in one assertion, even when the card
          // stays collapsed and the selection is missing on the baseline.
          final selected = await _waitForChatSelection(
            tester,
            _openingMessageId,
          );
          await tester.pump(const Duration(milliseconds: 200));
          final position = _replyScroll(tester);
          expect(
            (
              atTop: (position.pixels - position.minScrollExtent).abs() < 1,
              openingVisible: _expandedOpening
                  .hitTestable()
                  .evaluate()
                  .isNotEmpty,
              selected: selected,
            ),
            (atTop: true, openingVisible: true, selected: _openingMessageId),
          );
          expect(
            _chatState(tester).highlightedMessageId.value,
            _openingMessageId,
          );
          expect(
            tester
                .widgetList<RoomMessageTile>(find.byType(RoomMessageTile))
                .where(
                  (tile) => tile.highlightedMessageId?.value == tile.message.id,
                ),
            isEmpty,
          );
          _expectOnlyOpeningCard(tester, replyCount);
        },
      );
    }

    testWidgets(
      'an open conversation pane honors a new opening-message target once',
      (
        tester,
      ) async {
        const replies = 25;
        final repo = _postChat(
          ids: [
            _openingMessageId,
            for (var i = 1; i <= replies; i++) _numberedReplyId(i),
          ],
        );
        final selection = ValueNotifier<String?>(null);
        addTearDown(selection.dispose);
        final sync = buildTestRealtimeSync();
        addTearDown(sync.port.dispose);
        final posts = PostsCase(_ConversationPosts(), sync.case_);
        final beacons = _BeaconOnlyRepository({
          _postId: _beacon(
            _postId,
            BeaconKind.post,
          ).copyWith(postRootMessageId: _openingMessageId),
        });
        final router = await _pumpRoute(
          tester,
          id: _postId,
          kinds: _FakeBeaconKindRepository({_postId: BeaconKind.post}),
          beacons: beacons,
          withRequestCollaborators: true,
          activityCase: posts,
          roomRepo: repo,
          conversations: ConversationsScreen(
            postPaneBuilder: (id, onClose) => ValueListenableBuilder<String?>(
              valueListenable: selection,
              builder: (_, messageId, _) => PostViewScope(
                id: id,
                myProfile: _viewer,
                onClose: onClose,
                messageId: messageId,
              ),
            ),
          ),
        );
        addTearDown(router.dispose);
        await tester.pumpAndSettle();
        final list = find.byKey(TenturaListDetailLayout.listPaneKey);
        expect(list, findsOneWidget);
        await tester.tap(
          find.descendant(
            of: list,
            matching: find.byKey(const ValueKey(_postId)),
          ),
        );
        await tester.pumpAndSettle();

        final screen = tester.state(find.byType(PostViewScreen));
        final newest = _numberedReplyId(replies);
        // Incoming bubbles occupy the leading side of a wide reply row.
        final newestBubble = _tile(
          newest,
        ).hitTestable(at: const Alignment(-0.65, 0));
        expect(newestBubble, findsOneWidget);
        expect(_collapsedOpening, findsOneWidget);
        final position = _replyScroll(tester);
        expect(position.pixels, closeTo(position.maxScrollExtent, 1));
        _expectOnlyOpeningCard(tester, replies);
        await tester.tap(
          find.descendant(
            of: _collapsedOpening,
            matching: find.byIcon(Icons.push_pin_outlined),
          ),
        );
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(position.minScrollExtent, 1));
        expect(_expandedOpening.hitTestable(), findsOneWidget);

        // Exercise the same input a new link supplies to the visible pane.
        selection.value = newest;
        await tester.pump();
        expect(await _waitForChatSelection(tester, newest), newest);
        expect(newestBubble, findsOneWidget);
        expect(
          tester
              .widget<RoomMessageTile>(newestBubble)
              .highlightedMessageId
              ?.value,
          newest,
        );
        await tester.pump(const Duration(milliseconds: 200));
        final replyFlash = await _remainingFlash(tester, newest);
        expect(replyFlash, greaterThan(Duration.zero));

        selection.value = _unknownReply;
        await tester.pumpAndSettle();
        expect(newestBubble, findsOneWidget);
        expect(_chatState(tester).highlightedMessageId.value, isNull);
        final chat = tester.widget<BasicChatBody>(_chat);
        expect(chat.hasError, isFalse);
        expect(chat.isLoading, isFalse);
        expect(_collapsedOpening, findsOneWidget);

        selection.value = Uri.parse(_rootLink).queryParameters['message'];
        await tester.pump();
        expect(tester.state(find.byType(PostViewScreen)), same(screen));
        expect(
          await _waitForChatSelection(tester, _openingMessageId),
          _openingMessageId,
        );
        // Start the expansion animation before advancing its clock.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(position.pixels, closeTo(position.minScrollExtent, 1));
        expect(_expandedOpening.hitTestable(), findsOneWidget);
        expect(
          _chatState(tester).highlightedMessageId.value,
          _openingMessageId,
        );
        final openingFlash = await _remainingFlash(tester, _openingMessageId);
        expect(
          openingFlash.inMilliseconds,
          closeTo(replyFlash.inMilliseconds, 16),
        );
        await tester.pumpAndSettle();
        expect(_expandedOpening.hitTestable(), findsOneWidget);
        expect(position.pixels, closeTo(position.minScrollExtent, 1));
        _expectOnlyOpeningCard(tester, replies);

        final room = tester
            .element(find.byType(PostViewScreen))
            .read<ThreadHostCubit>()
            .roomCubit!;
        expect(room.state.scrollToMessageId, isNull);

        await tester.drag(_replyList, const Offset(0, -260));
        await tester.pumpAndSettle();
        final afterUserScroll = position.pixels;
        expect(afterUserScroll, greaterThan(position.minScrollExtent + 12));
        expect(afterUserScroll, lessThan(position.maxScrollExtent - 100));

        final incoming = _postChat(
          ids: [_numberedReplyId(replies + 1)],
        ).messages.single.copyWith(createdAt: DateTime.utc(2026, 1, 1, 13, 1));
        final highlight = _chatState(tester).highlightedMessageId;
        final selections = <String?>[];
        void recordSelection() => selections.add(highlight.value);
        highlight.addListener(recordSelection);
        repo.messages = [...repo.messages, incoming];
        await room.reloadMessages(silent: true);
        await tester.pumpAndSettle();
        highlight.removeListener(recordSelection);
        expect(
          tester.widget<BasicChatBody>(_chat).messages.last.id,
          incoming.id,
        );
        expect(position.pixels, closeTo(afterUserScroll, 1));
        expect(_chatState(tester).highlightedMessageId.value, isNull);
        expect(selections, isEmpty);
        expect(room.state.scrollToMessageId, isNull);
        _expectOnlyOpeningCard(tester, replies + 1);
      },
    );
  });

  group(_messageLinkTests, () {
    testWidgets(
      'a refreshed Post chat keeps the linked older reply highlighted',
      (tester) async {
        const target = 'Mpostolder01';
        const edited = _secondReply;
        const editedBody = 'Исправленный ответ';
        final server = RoomHintWireServer()
          ..messageRows = [
            _postMessageRow(_firstReply, 'Первый ответ', 1),
            _postMessageRow(edited, 'Второй ответ', 2),
          ]
          ..messageTargets[target] = _postMessageRow(target, 'Ранний ответ', 0);
        final wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
        addTearDown(() => tester.runAsync(wire.close));
        final repo = _PostChatPageRecorder(wire.repository);
        final router = await _pumpDetailRoot(
          tester,
          _postUrl,
          roomRepo: repo,
          phoneRu: true,
        );

        Future<void> invalidateReply(String id) async {
          await tester.runAsync(() async {
            final delivered = repo.beaconRoomInvalidations.first.timeout(
              const Duration(seconds: 2),
            );
            wire.socket.frames.add(
              jsonEncode({
                'type': 'subscription',
                'path': 'entity_changes',
                'payload': {
                  'entity': 'room_message',
                  'id': _postId,
                  'event': 'update',
                  'actor_user_id': _author.id,
                  'message_id': id,
                },
              }),
            );
            await delivered;
          });
          await tester.pump();
        }

        // Start batching an earlier hint before opening the link. That lets the
        // next hint join a refresh already due during the short highlight.
        await invalidateReply(_firstReply);
        await tester.pump(
          BurstCoalescer.window - const Duration(milliseconds: 850),
        );
        await router.navigatePath('$_postUrl?message=$target');
        await tester.pump();
        expect(await _waitForHighlight(tester, target), target);
        final room = tester
            .element(find.byType(PostViewScreen))
            .read<ThreadHostCubit>()
            .roomCubit!;
        expect(
          room.state.messages.map((message) => message.id),
          contains(target),
        );
        final started = tester.binding.clock.now();
        final pagesBeforeInvalidation = repo.pages.length;

        server.messageRows = [
          server.messageRows.first,
          _postMessageRow(edited, editedBody, 2),
        ];
        await invalidateReply(edited);

        bool refreshed() => tester
            .widget<BasicChatBody>(_chat)
            .messages
            .any(
              (message) => message.id == edited && message.body == editedBody,
            );
        for (var frame = 0; frame < 65 && !refreshed(); frame++) {
          await tester.pump(_frame);
        }
        expect(refreshed(), isTrue, reason: 'the new GraphQL page was applied');
        final refreshedPage = repo.pages
            .skip(pagesBeforeInvalidation)
            .singleWhere(
              (page) => page.any(
                (message) => message.id == edited && message.body == editedBody,
              ),
            );
        expect(refreshedPage.map((message) => message.id), [
          _firstReply,
          edited,
        ]);
        expect(
          tester.binding.clock.now().difference(started),
          lessThan(const Duration(milliseconds: 1200)),
        );
        expect(
          (
            retainedInRoom: room.state.messages.any(
              (message) => message.id == target,
            ),
            pinnedInRoom: room.state.pinnedJumpMessageIds.contains(target),
            tilePresent: _tile(target).evaluate().isNotEmpty,
            highlighted: _chatState(tester).highlightedMessageId.value,
          ),
          (
            retainedInRoom: true,
            pinnedInRoom: true,
            tilePresent: true,
            highlighted: target,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'going back from a linked Post drops its pinned reply when reopened',
      (tester) async {
        const target = 'Mpostolder01';
        final repo = _postChat(ids: [_secondReply]);
        final recent = repo.messages.single;
        repo.fetchMessageTargetsById[target] = recent.copyWith(
          id: target,
          body: 'Ранний ответ',
          createdAt: recent.createdAt.subtract(const Duration(minutes: 1)),
        );
        final router = await _pumpDetailRoot(
          tester,
          '$_postUrl?message=$target',
          roomRepo: repo,
          phoneRu: true,
        );
        final screen = find.byType(PostViewScreen);
        expect(await _waitForHighlight(tester, target), target);
        final linkedRoom = tester
            .element(screen)
            .read<ThreadHostCubit>()
            .roomCubit!;
        expect(
          linkedRoom.state.messages.map((message) => message.id),
          contains(target),
        );
        final pinsBeforeLeaving = linkedRoom.state.pinnedJumpMessageIds;

        await tester.tap(
          find.descendant(of: screen, matching: find.byType(BackButton)),
        );
        await tester.pumpAndSettle();
        expect(screen, findsNothing);
        expect(linkedRoom.isClosed, isTrue);

        unawaited(router.pushPath(_postUrl));
        await tester.pumpAndSettle();
        expect(router.currentUrl, _postUrl);
        expect(screen, findsOneWidget);
        final reopenedRoom = tester
            .element(screen)
            .read<ThreadHostCubit>()
            .roomCubit!;
        expect(reopenedRoom, isNot(same(linkedRoom)));
        expect(reopenedRoom.state.messages.map((message) => message.id), [
          _secondReply,
        ]);
        expect(reopenedRoom.state.pinnedJumpMessageIds, isEmpty);
        expect(_tile(target), findsNothing);
        expect(_tile(_secondReply), findsOneWidget);
        expect(pinsBeforeLeaving, [target]);
      },
    );

    testWidgets(
      'a deleted reply link leaves Chat loaded without highlighting or retrying the reply',
      (tester) async {
        const body = 'Другой ответ';
        final server = RoomHintWireServer()
          ..messageRows = [
            roomHintWireMessageRow(
              id: _secondReply,
              authorId: _author.id,
              authorTitle: _author.displayName,
              createdAt: DateTime.utc(2026, 1, 1, 12).toIso8601String(),
              body: body,
            )..['beaconId'] = _postId,
          ]
          ..messageTargetResponses[_unknownReply] =
              roomMessageTargetNotFoundResponse;
        final wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
        addTearDown(() => tester.runAsync(wire.close));
        GetIt.I.registerSingleton<Logger>(Logger('PostChatLinks'));
        addTearDown(() => GetIt.I.unregister<Logger>());
        final effects = FakeUiEffectPort();
        final repo = _LinkedPostChatRepository(wire.repository);
        await _pumpDetailRoot(
          tester,
          '$_postUrl?message=$_unknownReply',
          roomRepo: repo,
          phoneRu: true,
          effects: effects,
        );

        for (
          var frame = 0;
          frame < 90 && !repo.targetLookupFinished.isCompleted;
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(repo.targetLookupFinished.isCompleted, isTrue);
        await repo.targetLookupFinished.future;
        await tester.pumpAndSettle();

        void expectChatLoaded() {
          expect(find.byType(SnackBar), findsNothing);
          expect(effects.emitted.whereType<ShowError>(), isEmpty);
          _expectUnfocusedChat(tester);
          expect(_tile(_unknownReply), findsNothing);
          expect(
            find.textContaining(RegExp('^$body\uFFFC?\$')).hitTestable(),
            findsOneWidget,
          );
        }

        expect(server.requestedMessageTargetIds, [_unknownReply]);
        expectChatLoaded();

        final room = tester
            .element(find.byType(PostViewScreen))
            .read<ThreadHostCubit>()
            .roomCubit!;
        await room.reloadMessages(silent: true);
        await tester.pumpAndSettle();

        expectChatLoaded();
        expect(server.requestedMessageTargetIds, [_unknownReply]);
      },
    );

    testWidgets(
      'selects an older reply returned by GraphQL outside the latest page',
      (tester) async {
        const target = 'Mpostolder01';
        const targetBody = 'Первый ответ';
        Map<String, dynamic> row(String id, String body, int minute) =>
            roomHintWireMessageRow(
              id: id,
              authorId: _author.id,
              authorTitle: _author.displayName,
              createdAt: DateTime.utc(2026, 1, 1, 12, minute).toIso8601String(),
              body: body,
            )..['beaconId'] = _postId;

        final server = RoomHintWireServer()
          ..messageRows = [
            for (var i = 1; i <= 50; i++)
              row('Mrecent${i.toString().padLeft(5, '0')}', 'Ответ $i', i),
          ]
          ..messageTargets[target] = row(target, targetBody, 0);
        final wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
        addTearDown(() => tester.runAsync(wire.close));
        final repo = _WirePostChatRepository(wire.repository);
        await _pumpDetailRoot(
          tester,
          '$_postUrl?message=$target',
          roomRepo: repo,
          phoneRu: true,
        );
        expect(find.byType(PostViewScreen), findsOneWidget);
        final selected = await _waitForHighlight(tester, target);
        expect(server.queried, contains('RoomMessageList'));
        final chat = tester.widget<BasicChatBody>(find.byType(BasicChatBody));
        expect(chat.isLoading, isFalse);
        expect(chat.hasError, isFalse);
        expect(
          chat.messages.any((message) => message.body == 'Ответ 50'),
          isTrue,
        );
        expect(
          selected,
          target,
          reason: 'the historical tile must be visible and highlighted',
        );
        // The rich text may end with an invisible inline timestamp spacer.
        expect(
          find.textContaining(RegExp('^$targetBody\uFFFC?\$')).hitTestable(),
          findsOneWidget,
        );
      },
    );

    testWidgets('retargets an open Post without remounting its screen', (
      tester,
    ) async {
      final router = await _pumpDetailRoot(
        tester,
        '$_postUrl?message=$_firstReply',
        roomRepo: _postChat(
          ids: [
            _secondReply,
            for (var i = 0; i < 25; i++)
              'Mmiddle${i.toString().padLeft(5, '0')}',
            _firstReply,
          ],
        ),
      );
      final screen = tester.state(find.byType(PostViewScreen));
      final firstSelection = await _waitForHighlight(tester, _firstReply);
      expect(_tile(_firstReply).hitTestable(), findsOneWidget);
      expect(_tile(_secondReply).hitTestable(), findsNothing);
      await router.navigatePath('$_postUrl?message=$_secondReply');
      await tester.pump();
      expect(
        Uri.parse(router.currentUrl).queryParameters['message'],
        _secondReply,
      );
      final secondSelection = await _waitForHighlight(tester, _secondReply);
      expect(tester.state(find.byType(PostViewScreen)), same(screen));
      expect([firstSelection, secondSelection], [_firstReply, _secondReply]);
    });

    testWidgets(
      'selects a reply when a Request URL resolves to a Post',
      (tester) async {
        const link = '/beacon/view/$_postId?message=$_firstReply';
        final lookup = Completer<void>();
        final router = await _pumpDetailRoot(
          tester,
          link,
          lookupGates: {_postId: lookup},
          roomRepo: _postChat(),
        );
        expect(router.currentUrl, link);
        expect(router.stackData.last.name, BeaconViewRoute.name);

        lookup.complete();
        await tester.pumpAndSettle();
        expect(router.currentUrl, '$_postUrl?message=$_firstReply');
        expect(find.byType(PostViewScreen), findsOneWidget);
        expect(await _waitForHighlight(tester, _firstReply), _firstReply);
      },
    );

    for (final (description, query) in [
      ('no target', ''),
      ('an empty target', '?message='),
      ('a whitespace-only target', '?message=%20%20'),
    ]) {
      testWidgets('opens normally with $description and honors a later link', (
        tester,
      ) async {
        final room = _postChat();
        final router = await _pumpDetailRoot(
          tester,
          '$_postUrl$query',
          roomRepo: room,
        );
        _expectUnfocusedChat(tester);
        expect(room.fetchMessagesCallCount, 1);
        expect(room.fetchParticipantsCallCount, 1);
        expect(room.requestedTargets, isEmpty);

        await router.navigatePath('$_postUrl?message=$_firstReply');
        await tester.pump();
        expect(await _waitForHighlight(tester, _firstReply), _firstReply);
      });
    }

    testWidgets('reloads the chat and stays usable when a reply is missing', (
      tester,
    ) async {
      final room = _postChat();
      final router = await _pumpDetailRoot(
        tester,
        '$_postUrl?message=$_unknownReply',
        roomRepo: room,
      );
      expect(router.currentUrl, '$_postUrl?message=$_unknownReply');
      _expectUnfocusedChat(tester);
      expect(
        room.fetchMessagesCallCount,
        greaterThan(1),
        reason: 'a missing reply requires a second chat load',
      );
      expect(
        room.fetchParticipantsCallCount,
        greaterThan(1),
        reason: 'the retry reloads the full room snapshot',
      );
      expect(
        room.requestedTargets,
        contains(_unknownReply),
        reason: 'the chat must stay usable after the server reports no match',
      );
    });
  });

  testWidgets(
    'a legacy Post URL becomes canonical and selects its chat reply',
    (
      tester,
    ) async {
      const query = {
        'is_deep_link': 'true',
        'tab': 'threads',
        'thread': 'general',
        'message': _firstReply,
      };
      final router = await _pumpDetailRoot(
        tester,
        Uri(
          path: '/beacon/view/$_postId',
          queryParameters: query,
        ).toString(),
        roomRepo: _postChat(),
      );
      final routes = router.routes.where(
        (route) => route.path == '/post/view/:id',
      );
      expect(routes.map((route) => route.name), [PostViewRoute.name]);
      expect(
        router.routes.where((route) => route.name == PostViewRoute.name),
        hasLength(1),
      );
      expect(
        beaconDetailPathFor(
          'B1',
          isPost: true,
          queryParameters: {'is_deep_link': 'true'},
        ),
        '/post/view/B1?is_deep_link=true',
      );

      expect(find.byType(PostViewScreen), findsOneWidget);
      expect(find.byType(BeaconViewScreen), findsNothing);
      expect(router.stackData.last.name, PostViewRoute.name);
      expect(router.navigationHistory.urlState.uri.path, '/post/view/$_postId');
      expect(router.navigationHistory.urlState.uri.queryParameters, query);
      expect(
        router.navigationHistory.canNavigateBack,
        isFalse,
        reason: 'rewriting the initial URL must not create a second entry',
      );
      expect(await _waitForHighlight(tester, _firstReply), _firstReply);
    },
  );

  testWidgets('a cold canonical Post link opens the Post at the same URL', (
    tester,
  ) async {
    const url = '/post/view/$_postId?is_deep_link=true';
    final router = await _pumpDetailRoot(tester, url);
    expect(find.byType(PostViewScreen), findsOneWidget);
    expect(find.byType(BeaconViewScreen), findsNothing);
    expect(router.stackData.last.name, PostViewRoute.name);
    expect(router.currentUrl, url);
    expect(router.navigationHistory.canNavigateBack, isFalse);
  });

  testWidgets('a cold Request link opens the Request without a Post redirect', (
    tester,
  ) async {
    const path = '/beacon/view/$_requestId';
    final router = await _pumpDetailRoot(tester, path);
    expect(find.byType(BeaconViewScreen), findsOneWidget);
    expect(find.byType(PostViewScreen), findsNothing);
    expect(router.stackData.last.name, BeaconViewRoute.name);
    expect(Uri.parse(router.currentUrl).path, path);
    expect(router.navigationHistory.canNavigateBack, isFalse);
  });

  testWidgets('ScreenCubit opens the Post and Request through the app router', (
    tester,
  ) async {
    final effects = UiEffectBus();
    final screen = ScreenCubit.local(effects);
    addTearDown(screen.close);
    final gates = {_postId: Completer<void>(), _requestId: Completer<void>()};
    final router = await _pumpDetailRoot(
      tester,
      kPathMyWork,
      effects: effects,
      lookupGates: gates,
      home: Column(
        children: [
          TextButton(
            onPressed: () => screen.showBeacon(_postId, kind: BeaconKind.post),
            child: const Text('Open Post'),
          ),
          TextButton(
            onPressed: () =>
                screen.showBeacon(_requestId, kind: BeaconKind.request),
            child: const Text('Open Request'),
          ),
        ],
      ),
    );

    await tester.tap(find.text('Open Post'));
    await _expectDetail(
      tester,
      router,
      _postId,
      '/post/view',
      PostViewScreen,
      gates,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Request'));
    await _expectDetail(
      tester,
      router,
      _requestId,
      '/beacon/view',
      BeaconViewScreen,
      gates,
    );
  });

  testWidgets('tapping Updates receipts opens the Post and Request details', (
    tester,
  ) async {
    final receipts = await _wireAttentionReceipts();
    final sync = buildTestRealtimeSync();
    final attention = buildAttentionCase(
      repository: MarkUnreadServerFake(receipts),
      accounts: _ViewerAccount(),
      realtimeSyncCase: sync.case_,
      blockCase: noopBlockCase(),
      feedSessions: FeedSessionRegistry(),
      logger: Logger('PostDetailAttention'),
    );
    final feed = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.activityStream,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('PostDetailUpdates'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    addTearDown(() async {
      await feed.close();
      await attention.dispose();
      await sync.port.dispose();
    });

    final gates = {_postId: Completer<void>(), _requestId: Completer<void>()};
    final router = await _pumpDetailRoot(
      tester,
      kPathMyWork,
      lookupGates: gates,
      home: BlocProvider.value(value: feed, child: const UpdatesFeedPane()),
    );

    await tester.tap(find.byKey(const ValueKey('receipt-$_postId')));
    await _expectDetail(
      tester,
      router,
      _postId,
      '/post/view',
      PostViewScreen,
      gates,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receipt-$_requestId')));
    await _expectDetail(
      tester,
      router,
      _requestId,
      '/beacon/view',
      BeaconViewScreen,
      gates,
    );
  });

  group('kind-aware beacon route', () {
    testWidgets('shows the loading view until the beacon kind resolves', (
      tester,
    ) async {
      final kinds = _FakeBeaconKindRepository({_postId: BeaconKind.post})
        ..gated = true;
      final beacons = _BeaconOnlyRepository({
        _postId: _beacon(_postId, BeaconKind.post),
      });
      await _pumpRoute(tester, id: _postId, kinds: kinds, beacons: beacons);
      await tester.pump();

      expect(find.byType(BeaconViewLoadingShellFrame), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(PostViewScreen), findsNothing);
      expect(find.byType(BeaconViewScreen), findsNothing);

      kinds.gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PostViewScreen), findsOneWidget);
    });

    testWidgets(
      'a Post id renders the Post screen with its room and never touches '
      'Request-only data',
      (tester) async {
        final kinds = _FakeBeaconKindRepository({_postId: BeaconKind.post});
        final beacons = _BeaconOnlyRepository({
          _postId: _beacon(_postId, BeaconKind.post),
        });
        await _pumpRoute(
          tester,
          id: _postId,
          kinds: kinds,
          beacons: beacons,
          withThrowingRequestCollaborators: true,
        );
        await tester.pumpAndSettle();

        expect(
          kinds.requested.where((id) => id == _postId).length,
          greaterThanOrEqualTo(1),
        );
        expect(_requestOnlyTouches, isEmpty);
        expect(find.byType(PostViewScreen), findsOneWidget);
        expect(find.byType(BeaconViewScreen), findsNothing);
        expect(find.byType(BeaconRoomSurface), findsOneWidget);
        expect(
          beacons.fetched.where((id) => id == _postId).length,
          greaterThanOrEqualTo(1),
        );
        expect(tester.takeException(), isNull);

        final context = tester.element(find.byType(PostViewScreen));
        final surface = tester.widget<BeaconRoomSurface>(
          find.byType(BeaconRoomSurface),
        );
        expect(surface.host, same(context.read<PostViewCubit>()));
        expect(context.read<ThreadsCubit>(), isA<ThreadsCubit>());
        expect(
          context.read<ThreadHostCubit>().capabilities,
          const RoomCapabilities.post(),
        );
        expect(
          context.read<PostViewCubit>().capabilities,
          const RoomCapabilities.post(),
        );
      },
    );

    testWidgets('a Request id renders the Request screen', (tester) async {
      final kinds = _FakeBeaconKindRepository({
        _requestId: BeaconKind.request,
      });
      final beacons = TrackingBeaconRepository()
        ..fetchByIdHandler = (id) async => _beacon(id, BeaconKind.request);
      addTearDown(beacons.dispose);
      await _pumpRoute(
        tester,
        id: _requestId,
        kinds: kinds,
        beacons: beacons,
        withRequestCollaborators: true,
      );
      await tester.pumpAndSettle();

      expect(kinds.requested, contains(_requestId));
      expect(find.byType(BeaconViewScreen), findsOneWidget);
      expect(find.byType(PostViewScreen), findsNothing);
    });
  });

  group('PostViewCubit', () {
    late _BeaconOnlyRepository beacons;
    late PostViewCubit cubit;

    setUp(() {
      beacons = _BeaconOnlyRepository({
        _postId: _beacon(_postId, BeaconKind.post),
      });
      cubit = PostViewCubit(
        id: _postId,
        myProfile: _viewer,
        beaconRepository: beacons,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
    });

    test('is a RoomHost with Post capabilities', () {
      expect(cubit, isA<RoomHost>());
      expect(cubit.beaconId, _postId);
      expect(cubit.capabilities, const RoomCapabilities.post());
    });

    test(
      'loads only the beacon itself and exposes author and status',
      () async {
        await cubit.fetch();
        await Future<void>.delayed(Duration.zero);

        expect(beacons.fetched, [_postId]);
        expect(cubit.author.id, _author.id);
        expect(cubit.status, BeaconStatus.open);
      },
    );
  });

  group('PostViewScreen', () {
    testWidgets('renders the room surface under a plain app bar with back', (
      tester,
    ) async {
      final beacons = _BeaconOnlyRepository({
        _postId: _beacon(_postId, BeaconKind.post),
      });
      await registerBeaconViewHarnessGetIt(profile: _viewer);
      addTearDown(unregisterBeaconViewHarnessGetIt);
      final cubit = PostViewCubit(
        id: _postId,
        myProfile: _viewer,
        beaconRepository: beacons,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await cubit.fetch();

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: BeaconViewResizableMediaQuery(
            size: kBeaconViewHarnessCompact,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<PostViewCubit>.value(value: cubit),
                BlocProvider<ThreadsCubit>(
                  create: (_) => ThreadsCubit(beaconId: _postId),
                ),
                BlocProvider<ThreadHostCubit>(
                  create: (_) => ThreadHostCubit(
                    beaconId: _postId,
                    capabilities: const RoomCapabilities.post(),
                  ),
                ),
              ],
              child: const PostViewScreen(id: _postId),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      final surface = tester.widget<BeaconRoomSurface>(
        find.byType(BeaconRoomSurface),
      );
      expect(surface.host, same(cubit));
    });
  });
}
