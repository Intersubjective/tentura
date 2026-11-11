// Shared harness for the Posts tab filter and draft-row tests. Only HTTP is
// faked: the production Ferry client, the `MyPosts` mapper in
// PostsRepository, PostsCase, PostsCubit and the real ConversationsScreen
// (title + filter control + PostsTabView) stay in path. Deleting a draft
// reaches the same fake server as `BeaconDeleteById`, which then drops the
// draft from the next `MyPosts` answer, like the real server.

import 'dart:async';
import 'dart:convert';

import 'package:ferry/ferry.dart'
    show Client, OperationRequest, OperationResponse;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/conversations_screen.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/features/inbox/ui/widget/posts_tab_view.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_app_navigator.dart';
import '../beacon_create/fake_beacon_ports.dart' show FakeBeaconImagePort;
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart' show WireSent;
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

/// Phone (iPhone SE) and desktop widths every Posts tab check runs at.
const postsTabViewports = <({String name, Size size})>[
  (name: 'phone 375×667', size: kPhoneSurface),
  (name: 'desktop 1280×800', size: Size(1280, 800)),
];

const postsTabViewerId = 'Uviewer000001';

/// One `v2_PostSummary` row as the server's `myPosts` sends it.
/// [status] 3 is a draft (only its author ever receives it).
Map<String, dynamic> myPostsWireRow({
  required String id,
  required String excerpt,
  required DateTime lastActivityAt,
  bool isAuthor = false,
  int status = 0,
  DateTime? expiresAt,
  DateTime? pinnedAt,
}) => {
  '__typename': 'v2_PostSummary',
  'id': id,
  'authorId': isAuthor ? postsTabViewerId : 'Uauthor$id',
  'authorName': isAuthor ? 'Олег' : 'Анна',
  'authorAvatar': '',
  'forwardedByName': null,
  'rootImageUrl': null,
  'rootExcerpt': excerpt,
  'lastMessageExcerpt': null,
  'lastMessageIsRoot': status != 3,
  'lastMessageAt': status == 3 ? null : lastActivityAt.toIso8601String(),
  'lastActivityAt': lastActivityAt.toIso8601String(),
  'pinnedAt': pinnedAt?.toIso8601String(),
  'mutedUntil': null,
  'mutedForever': false,
  'unreadCount': 0,
  'participantCount': 0,
  'notOpenedCount': 0,
  'myDeclinedForwardCount': 0,
  'previewParticipants': <Object>[],
  'isAuthor': isAuthor,
  'status': status,
  'expiresAt': expiresAt?.toIso8601String(),
};

/// The fake server behind the Posts tab: answers `MyPosts` with [rows] and
/// `BeaconDeleteById` by removing that row. Any other operation is recorded
/// and answered with a GraphQL error.
class PostsTabWire {
  PostsTabWire(List<Map<String, dynamic>> rows) : rows = [...rows];

  final List<Map<String, dynamic>> rows;
  final sent = <WireSent>[];
  void Function(String id)? onWrite;

  /// When false the server refuses `BeaconDeleteById` (answers `false`) and
  /// keeps the row.
  bool deletesSucceed = true;

  List<WireSent> calls(String name) =>
      sent.where((r) => r.operationName == name).toList();

  /// Ids the client asked the server to delete.
  List<String> get deletedIds => [
    for (final call in calls('BeaconDeleteById'))
      call.variables['id'] as String,
  ];

  Future<http.Response> respond(http.Request request) async {
    final payload =
        jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;
    final call = (
      operationName: payload['operationName'] as String,
      variables: ((payload['variables'] as Map?) ?? const {})
          .cast<String, dynamic>(),
    );
    sent.add(call);
    final Map<String, dynamic> body;
    switch (call.operationName) {
      case 'MyPosts':
        body = {
          'data': {
            '__typename': 'query_root',
            'myPosts': [...rows],
          },
        };
      case 'BeaconFetchById':
        final row = rows.singleWhere((r) => r['id'] == call.variables['id']);
        body = {
          'data': {
            'beacon_by_pk': {
              '__typename': 'beacon',
              'id': row['id'],
              'title': '',
              'description': row['rootExcerpt'],
              'kind': 1,
              'status': 3,
              'forward_policy': 1,
              'post_lifetime_hours': 72,
              'post_draft_attachments': <Object>[],
              'cover_source': 0,
              'needs': '',
              'tags': '',
              'created_at': row['lastActivityAt'],
              'updated_at': row['lastActivityAt'],
              'is_discoverable': false,
              'beacon_images': <Object>[],
              'active_help_offers': <Object>[],
              'participant_help_offers': <Object>[],
              'admitted_helpers': <Object>[],
              'author': {
                '__typename': 'user',
                'id': postsTabViewerId,
                'display_name': 'Олег',
                'description': '',
                'scores': <Object>[],
              },
              for (final relation in [
                'help_offers_aggregate',
                'unanswered_help_offers',
                'admitted_helpers_aggregate',
              ])
                relation: {'aggregate': null},
            },
          },
        };
      case 'BeaconCreate':
        const id = 'Bcreatedpost01';
        rows.add(
          myPostsWireRow(
            id: id,
            excerpt: call.variables['description'] as String? ?? '',
            lastActivityAt: DateTime.now().toUtc(),
            isAuthor: true,
            status: 3,
          ),
        );
        body = {
          'data': {
            'beaconCreate': {'id': id},
          },
        };
      case 'PostUpdateDraft':
        final row = rows.singleWhere((r) => r['id'] == call.variables['id']);
        row['rootExcerpt'] = call.variables['body'];
        body = {
          'data': {
            'postUpdateDraft': {'id': row['id']},
          },
        };
      case 'BeaconDeleteById':
        final id = call.variables['id'];
        final before = rows.length;
        if (deletesSucceed) rows.removeWhere((row) => row['id'] == id);
        body = {
          'data': {
            '__typename': 'mutation_root',
            'beaconDeleteById': rows.length < before,
          },
        };
      default:
        body = {
          'data': null,
          'errors': [
            {'message': 'unexpected operation ${call.operationName}'},
          ],
        };
    }
    if (const {
      'BeaconCreate',
      'PostUpdateDraft',
      'BeaconDeleteById',
    }.contains(call.operationName)) {
      onWrite?.call(call.variables['id'] as String? ?? 'Bcreatedpost01');
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _FerryRemote implements RemoteRequestClient {
  const _FerryRemote(this.client);

  final Client client;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => client.request(request);

  Future<void> close() => client.dispose();
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: postsTabViewerId, displayName: 'Олег'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

/// Records pushes and paths instead of navigating.
class RecordingPostsTabRouter extends Fake implements StackRouter {
  final pushed = <PageRouteInfo>[];
  final paths = <String>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushed.add(route);
    return null;
  }

  @override
  Future<T?> pushPath<T extends Object?>(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) async {
    paths.add(path);
    return null;
  }

  @override
  Future<void> navigatePath(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) async => paths.add(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<dynamic>.value();
}

class _PresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream => const Stream.empty();
}

class _Clipboard extends Fake implements ClipboardImageRepository {}

/// Only the navigation host is substituted. The destination is the production
/// composer, which loads its content over HTTP through BeaconRepository.
class _ComposerNavigator extends FakeAppNavigator {
  late Future<void> Function(String draftId) open;

  @override
  Future<void> createPost({
    String draftId = '',
    String forwardToUserId = '',
    Set<String> initialRecipientIds = const {},
    void Function(Set<String>, Map<String, String>)? onRecipientsChanged,
    VoidCallback? onPublished,
  }) async {
    await super.createPost(draftId: draftId);
    await open(draftId);
  }
}

class PostsTabHarness {
  PostsTabHarness._({
    required this.wire,
    required this.navigator,
    required this.effects,
    required this.router,
    required this.openComposer,
    required this.beacons,
    required this.cubit,
  });

  final Future<void> Function(String draftId) openComposer;
  final BeaconRepository beacons;
  final PostsCubit cubit;
  final PostsTabWire wire;
  final FakeAppNavigator navigator;
  final FakeUiEffectPort effects;
  final RecordingPostsTabRouter router;

  /// Draft ids the screen opened the Post composer for, whichever navigation
  /// seam it went through (AppNavigator.createPost, a pushed PostCreateRoute,
  /// or a `/post/new?draft_id=` path).
  List<String> get composerDraftIds {
    final fromPaths = [
      ...router.paths,
      for (final e in effects.emitted.whereType<NavigatePush>()) e.path,
    ];
    return [
      for (final intent in navigator.named('createPost'))
        if (intent.args['draftId'] case final String id) id,
      for (final route in router.pushed)
        if (route.args case final PostCreateRouteArgs args) args.draftId,
      for (final path in fromPaths)
        if (path.startsWith('/post/new'))
          ?Uri.parse(path).queryParameters['draft_id'],
    ];
  }

  /// Every Post or Request the screen opened as a live chat instead.
  List<String> get openedChats => [
    for (final route in router.pushed)
      if (route.args case final PostViewRouteArgs args) args.id,
    for (final intent in navigator.named('openBeacon'))
      if (intent.args['id'] case final String id) id,
  ];
}

/// Pumps the real Conversations screen at [size] over the [wire] fake server,
/// runs [body], then tears everything down. Runs on real async so the Ferry
/// HTTP streams complete; [body] is bounded so a missing control fails fast.
Future<void> withPostsTab(
  WidgetTester tester, {
  required Size size,
  required PostsTabWire wire,
  required Future<void> Function(PostsTabHarness h) body,
  Locale locale = const Locale('ru'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.runAsync(() async {
    final getIt = GetIt.I;
    await getIt.reset();
    final sync = buildTestRealtimeSync();
    wire.onWrite = (id) => sync.port.emitChange(
      RealtimeEntityChange(
        kind: RealtimeEntityKind.beacon,
        aggregateId: id,
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
      ),
    );
    final remote = _FerryRemote(
      await buildClient(
        params: (
          apiEndpointUrl: 'https://posts.test/api/v1/graphql',
          apiEndpointUrlV2: 'https://posts.test/api/v2/graphql',
          userAgent: 'posts-tab-test',
          requestTimeout: const Duration(seconds: 3),
        ),
        getToken: () async => 'test-token',
        httpClient: MockClient(wire.respond),
      ),
    );
    final logger = Logger('posts-tab-wire-test');
    final beacons = BeaconRepository(remote, sync.port);
    final postsCase = PostsCase(
      PostsRepository(remote),
      sync.case_,
      beaconRepository: beacons,
      env: const Env(),
      logger: logger,
    );
    final effects = FakeUiEffectPort();
    final navigator = _ComposerNavigator();
    getIt.registerSingleton<AppNavigator>(navigator);
    final profile = _ProfileCubit();
    getIt
      ..registerSingleton<Logger>(logger)
      ..registerSingleton<RealtimeSyncCase>(sync.case_)
      ..registerSingleton<PostsCase>(postsCase)
      ..registerSingleton<BeaconRepository>(beacons)
      ..registerSingleton<ProfileCubit>(profile)
      ..registerSingleton<ImageRepository>(ImageRepository())
      ..registerSingleton<ClipboardImageRepository>(_Clipboard());
    final router = RecordingPostsTabRouter();
    final cubit = PostsCubit(postsCase: postsCase);
    final reselect = HomeTabReselectCubit();
    final navigatorKey = GlobalKey<NavigatorState>();
    Future<void> openComposer(String draftId) async {
      final forward = ForwardCubit(
        beaconId: '',
        embedded: true,
        effects: effects,
        debugSkipInitialLoad: true,
        debugInitialState: const ForwardState(
          candidatesLoad: ForwardCandidatesReady(),
        ),
      );
      // Route disposal owns both cubits, as it does in wrappedRoute.
      await navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ProfileCubit>.value(value: profile),
                  BlocProvider<PresenceCubit>.value(value: _PresenceCubit()),
                  BlocProvider<ScreenCubit>(
                    create: (_) => ScreenCubit(effects),
                  ),
                  BlocProvider<BeaconCreateCubit>(
                    create: (_) => BeaconCreateCubit(
                      kind: BeaconKind.post,
                      draftBeaconIdToLoad: draftId.isEmpty ? null : draftId,
                      beaconCreateCase: BeaconCreateCase(
                        beacons,
                        FakeBeaconImagePort(),
                      ),
                      effects: effects,
                    ),
                  ),
                  BlocProvider<ForwardCubit>(create: (_) => forward),
                ],
                child: PostCreateScreen(draftId: draftId),
              ),
            ),
          ),
        ),
      );
    }

    navigator.open = openComposer;
    final harness = PostsTabHarness._(
      wire: wire,
      navigator: navigator,
      effects: effects,
      router: router,
      openComposer: openComposer,
      beacons: beacons,
      cubit: cubit,
    );
    try {
      await tester.pumpWidget(
        StackRouterScope(
          controller: router,
          stateHash: 0,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<HomeTabReselectCubit>.value(value: reselect),
              BlocProvider<ProfileCubit>.value(value: _ProfileCubit()),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(effects)),
              BlocProvider<PostsCubit>.value(value: cubit),
            ],
            child: MaterialApp(
              navigatorKey: navigatorKey,
              locale: locale,
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: TenturaResponsiveScope(
                child: ConversationsScreen(
                  canCreatePost: true,
                  postPaneBuilder: (id, onClose) =>
                      Material(child: Text('chat:$id')),
                ),
              ),
            ),
          ),
        ),
      );
      await settlePostsTab(tester);
      expect(
        wire.calls('MyPosts'),
        isNotEmpty,
        reason: 'fixture sanity: the tab loads through the real MyPosts query',
      );
      await body(harness).timeout(const Duration(seconds: 20));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
      await reselect.close();
      await beacons.dispose();
      wire.onWrite = null;
      await sync.port.dispose();
      await remote.close();
      await getIt.reset();
    }
  });
}

/// Lets HTTP answers arrive and menus, dialogs and lists finish animating.
Future<void> settlePostsTab(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// The filter control beside the Posts title, labelled [label]: the
/// labelled form, or the collapsed icon whose tooltip ends with the label.
Finder postsFilterControl(String label) {
  final labelled = find.descendant(
    of: find.byType(TenturaTopBar),
    matching: find.text(label),
  );
  if (labelled.evaluate().isNotEmpty) return labelled;
  return find.descendant(
    of: find.byType(TenturaTopBar),
    matching: find.byWidgetPredicate(
      (w) => w is Tooltip && (w.message?.endsWith(': $label') ?? false),
    ),
  );
}

/// The items of the open popup menu.
Finder get openMenuItems => find.byWidgetPredicate((w) => w is PopupMenuItem);

/// The visible labels of the open popup menu, top to bottom.
List<String> openMenuLabels(WidgetTester tester) {
  final items = openMenuItems.evaluate().toList()
    ..sort(
      (a, b) => tester
          .getTopLeft(find.byElementPredicate((e) => e == a))
          .dy
          .compareTo(
            tester.getTopLeft(find.byElementPredicate((e) => e == b)).dy,
          ),
    );
  return [
    for (final item in items)
      [
        for (final text
            in find
                .descendant(
                  of: find.byElementPredicate((e) => e == item),
                  matching: find.byType(Text),
                )
                .evaluate())
          (text.widget as Text).data ??
              (text.widget as Text).textSpan?.toPlainText() ??
              '',
      ].join(' '),
  ];
}

/// Opens the filter menu from the control labelled [current] and picks
/// [next].
Future<void> pickPostsFilter(
  WidgetTester tester, {
  required String current,
  required String next,
}) async {
  final control = postsFilterControl(current);
  expect(
    control,
    findsOneWidget,
    reason: 'the filter control beside the Posts title names «$current»',
  );
  await tester.tap(control);
  await settlePostsTab(tester);
  final item = find.descendant(of: openMenuItems, matching: find.text(next));
  expect(item, findsOneWidget, reason: 'the filter menu offers «$next»');
  await tester.tap(item);
  await settlePostsTab(tester);
}

/// The Post row showing [excerpt].
Finder postRowWith(String excerpt) => find.ancestor(
  of: find.text(excerpt),
  matching: find.byType(PostConversationRow),
);

/// Empty state of the Posts list, excluding the independent empty chat pane
/// shown alongside it on desktop.
Finder get postsEmptyState => find.descendant(
  of: find.byType(PostsTabView),
  matching: find.byType(TenturaEmptyState),
);
