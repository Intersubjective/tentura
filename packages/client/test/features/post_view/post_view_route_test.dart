import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
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
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';

import '../../support/attention_case_factory.dart';
import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
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
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: ConversationsRoute.page, path: '/conversations'),
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
  FakeBeaconThreadsRepository? roomRepo,
  RootRouter? rootRouter,
  String? initialLocation,
  bool phoneRu = false,
  Widget? home,
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
        createCase: BeaconCreateCase(_NoopWritePort(), ImageRepository()),
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
  final router = rootRouter ?? _TestRouter();
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
        BlocProvider(create: (_) => HomeTabReselectCubit()),
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
    ..fetchByIdHandler = (id) async => _beacon(id, kinds.kinds[id]!);
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

void main() {
  group(_messageLinkTests, () {
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
