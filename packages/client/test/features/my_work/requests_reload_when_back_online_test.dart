// The Requests desk over real HTTP while the server is unreachable: every
// GraphQL request fails on transport (a stand-in for a server restart), the
// desk shows «No connection» + «Try again», and NetworkReachability goes
// offline through the real HTTP link. When reachability comes back online the
// desk must reload on its own — once — and show the Requests, with no tap.
//
// Only HTTP and unrelated shell dependencies are substituted; the load runs
// wire -> GQL mapper -> MyWorkRepository -> MyWorkCase -> MyWorkCubit (built
// by the real Home shell through DI) -> MyWorkScreen.
//
// The reachability probe itself is covered by
// test/data/service/network_reachability_probe_test.dart. Here the service is
// built with `NetworkReachability.forTesting()` and no probe injected: such a
// service must not probe (no network calls, no probe timers), and
// `reportSuccess()` stands in for a probe that reached the server.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/entity/post_join_destination.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/domain/port/post_join_beacon_handoff_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/home/ui/screen/home_screen.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';
import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_plan/beacon_plan_test_support.dart';
import '../beacon_view/beacon_view_case_test_support.dart'
    show FakeBeaconDisplayRepository;
import '../block/support/controllable_block_case.dart' show noopBlockCase;
import 'my_work_test_support.dart';

const _userId = 'Uauthor000001';
const _requestTitle = 'Fix the community garden fence';

Map<String, Object?> _aggregate(String type) => {
  '__typename': '${type}_aggregate',
  'aggregate': {'__typename': '${type}_aggregate_fields', 'count': 0},
};

Map<String, Object?> _authoredRequest() => {
  '__typename': 'beacon',
  'id': 'b1',
  'title': _requestTitle,
  'description': '',
  'needs': '',
  'tags': '',
  'status': 0,
  'kind': 0,
  'forward_policy': 0,
  'cover_source': 0,
  'is_discoverable': true,
  'created_at': '2026-09-27T12:00:00Z',
  'updated_at': '2026-09-27T12:00:00Z',
  'status_changed_at': '2026-09-01T12:00:00Z',
  'beacon_images': [],
  'help_offers': [],
  'active_help_offers': [],
  'participant_help_offers': [],
  'admitted_helpers': [],
  'help_offers_aggregate': _aggregate('beacon_help_offer'),
  'unanswered_help_offers': _aggregate('beacon_help_offer'),
  'admitted_helpers_aggregate': _aggregate('beacon_admitted_helper'),
  'author': {
    '__typename': 'user',
    'id': _userId,
    'display_name': 'Desk owner',
    'description': '',
    'scores': <Object>[],
  },
};

Map<String, Object?> _wireData(String operationName) => switch (operationName) {
  'AttentionLiveObligations' => {'liveObligationBeacons': <String>[]},
  'MyWorkInit' => {
    'authoredNonArchived': [_authoredRequest()],
    'helpOfferedNonArchived': <Object>[],
    'obligationBeacons': <Object>[],
    'archivedIdHints': <Object>[],
  },
  'MyWorkLastActivityEvent' => {'myWorkLastActivityEvent': <Object>[]},
  'MyWorkArchived' => {
    'archivedRows': <Object>[],
    'helpOfferedArchived': <Object>[],
  },
  'MyWorkAttention' => {'myWorkAttention': <Object>[]},
  _ => throw UnsupportedError('Unexpected operation: $operationName'),
};

/// The server behind `/api`: while [down], every GraphQL request fails on
/// transport the way an aborted browser fetch does.
final class _Server {
  bool down = false;

  /// Every GraphQL operation the client sent, in order.
  final operations = <String>[];

  int count(String operation, {int from = 0}) =>
      operations.skip(from).where((name) => name == operation).length;

  http.Client createClient() => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': _userId,
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    final name = payload['operationName'] as String;
    operations.add(name);
    if (down) throw http.ClientException('Failed to fetch', request.url);
    return http.Response(
      jsonEncode({'data': _wireData(name)}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

Future<void> _withServer(
  WidgetTester tester,
  _Server server,
  Future<void> Function(
    RemoteApiService remote,
    NetworkReachability reachability,
  )
  body,
) => http.runWithClient(() async {
  final reachability = NetworkReachability.forTesting();
  final remote = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
    reachability: reachability,
  );
  try {
    await tester.runAsync(remote.setSessionAuth);
    await body(remote, reachability);
  } finally {
    await tester.runAsync(remote.close);
    await tester.runAsync(reachability.dispose);
  }
}, server.createClient);

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _userId, displayName: 'Desk owner'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
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

class _NoInviteHandoff implements PostJoinBeaconHandoffPort {
  @override
  PostJoinDestination? readAndClear() => null;
}

class _SignedInAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(
    updatedAt: DateTime.utc(2026, 10, 7),
    currentAccountId: _userId,
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _EmptyInboxRepository implements InboxRepository {
  @override
  Stream<void> get localMutations => const Stream.empty();

  @override
  Future<List<InboxItem>> fetch({required String userId}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyForwardRepository extends FakeForwardRepository {
  @override
  Stream<String> get forwardCommandCompleted => const Stream.empty();
}

class _EmptyPostsRepository implements PostsRepositoryPort {
  @override
  Future<List<PostSummary>> myPosts() async => const [];

  @override
  Future<PostSummary?> postSummary(String id) async => null;
}

MyWorkCase _deskCase(RemoteApiService remote) {
  final realtime = buildTestRealtimeSync().case_;
  final hints = FakeRoomHints();
  return MyWorkCase(
    MyWorkRepository(remote),
    FakeArchiveRepository(),
    FakeForwardRepository(),
    FakeBeaconRepository(),
    buildTestBeaconThreadsCase(hints),
    hints,
    FakeBeaconDisplayRepository(),
    FakeMyWorkClosureRepository(),
    realtime,
    BookkeepingRefreshSignal(),
    AttentionCase(
      AttentionRepository(remote),
      _Accounts(),
      realtime,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('requests-recovery-attention'),
    ),
    FakeBeaconPlanRepository(BeaconPlan.decode(planJson())),
    env: const Env(),
    logger: Logger('requests-recovery'),
  );
}

/// The two surfaces every recovery claim is checked at.
typedef _Surface = ({String name, Locale locale, Size size});

const _phoneRu = (
  name: '375×667 RU',
  locale: Locale('ru'),
  size: kPhoneSurface,
);
const _desktopEn = (
  name: '1280×800 EN',
  locale: Locale('en'),
  size: Size(1280, 800),
);

Future<void> _pumpHome(
  WidgetTester tester, {
  required MyWorkCase deskCase,
  required NetworkReachability reachability,
  required _Surface surface,
}) async {
  await tester.binding.setSurfaceSize(surface.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final homeActivation = HomeActivationCubit(_OrientationPreferences());
  final homeAttention = HomeAttentionCubit(
    buildStubAttentionCase(),
    _Accounts(),
    Logger('home-attention'),
  );
  final inbox = InboxOperationalCubit();
  final reselect = HomeTabReselectCubit();
  final effects = FakeUiEffectPort();
  final screen = ScreenCubit.local(effects);
  final postJoin = PostJoinNavigationCubit();
  final realtime = buildTestRealtimeSync().case_;
  GetIt.I
    ..registerSingleton<NetworkReachability>(reachability)
    ..registerSingleton<NetworkReachabilityPort>(reachability)
    ..registerSingleton<AuthCubit>(_SignedInAuthCubit())
    ..registerSingleton<BeaconRepository>(FakeBeaconRepository())
    ..registerSingleton<ClosureRepository>(ClosureRepositoryMock())
    ..registerSingleton<MyWorkCase>(deskCase)
    ..registerSingleton<InboxCase>(
      InboxCase(
        _EmptyInboxRepository(),
        buildTestBeaconThreadsCase(FakeRoomHints()),
        _EmptyForwardRepository(),
        realtime,
        BookkeepingRefreshSignal(),
        noopBlockCase(),
        env: const Env(),
        logger: Logger('home-inbox'),
      ),
    )
    ..registerSingleton<PostsCase>(
      PostsCase(
        _EmptyPostsRepository(),
        realtime,
        env: const Env(),
        logger: Logger('home-posts'),
      ),
    )
    ..registerSingleton<ScreenCubit>(screen)
    ..registerSingleton<HomeTabReselectCubit>(reselect)
    ..registerSingleton<InboxOperationalCubit>(inbox)
    ..registerSingleton<HomeActivationCubit>(homeActivation)
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<Logger>(Logger('requests-recovery'))
    ..registerSingleton<HomeAttentionCubit>(homeAttention)
    ..registerSingleton<PostJoinNavigationCubit>(postJoin)
    ..registerSingleton<PostJoinBeaconHandoffPort>(_NoInviteHandoff());

  // The real HomeRoute and tab branches; only the pages of tabs other than the
  // Requests desk are blank.
  final router = RootStackRouter.build(
    routes: [
      AutoRoute(
        page: HomeRoute.page,
        path: '/home',
        initial: true,
        children: [
          for (final spec in HomeTabSpec.all)
            AutoRoute(
              page: spec.shell.page,
              path: spec.path.split('/').last,
              initial: spec.tab == HomeTab.work,
              children: [
                AutoRoute(
                  page: spec.tab == HomeTab.work
                      ? MyWorkRoute.page
                      : PageInfo(
                          spec.rootRoute().routeName,
                          builder: (_) => const SizedBox.shrink(),
                        ),
                  path: '',
                  initial: true,
                ),
              ],
            ),
        ],
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    await homeActivation.close();
    await homeAttention.close();
    await inbox.close();
    await reselect.close();
    await screen.close();
    router.dispose();
    await GetIt.I.reset();
  });
  await tester.pumpWidget(
    MaterialApp.router(
      theme: TenturaTheme.light(),
      locale: surface.locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      routerConfig: router.config(),
      builder: (_, child) => TenturaResponsiveScope(
        child: BlocProvider<ProfileCubit>.value(
          value: _TestProfileCubit(),
          child: child,
        ),
      ),
    ),
  );
  await _settle(tester);
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(find.byType(MyWorkScreen), findsOneWidget);
}

/// Bounded: lets requests, retries and rebuilds finish in fake time.
Future<void> _settle(
  WidgetTester tester, {
  Duration total = const Duration(seconds: 5),
}) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(MyWorkScreen)))!;

void _expectNoConnectionPanel(WidgetTester tester) {
  final l10n = _l10n(tester);
  expect(find.byType(ScreenLoadErrorPanel), findsOneWidget);
  expect(find.text(l10n.screenLoadErrorNetworkTitle), findsOneWidget);
  expect(find.text(l10n.myWorkRetry), findsOneWidget);
  expect(find.text(_requestTitle), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Requests desk reloads on its own when the app is back online', () {
    for (final surface in [_phoneRu, _desktopEn]) {
      testWidgets(
        'a desk whose load failed offline shows «No connection» and, once '
        'reachability is back, reloads once and shows the Requests with no '
        'tap (${surface.name})',
        (tester) async {
          final server = _Server()..down = true;
          await _withServer(tester, server, (remote, reachability) async {
            await _pumpHome(
              tester,
              deskCase: _deskCase(remote),
              reachability: reachability,
              surface: surface,
            );
            await _settle(tester, total: const Duration(seconds: 20));
            expect(tester.takeException(), isNull);
            _expectNoConnectionPanel(tester);
            expect(
              reachability.isOnline,
              isFalse,
              reason: 'the failed requests took the app offline',
            );

            // The server is back and a probe reached it; nobody taps.
            server.down = false;
            final sentBeforeRecovery = server.operations.length;
            reachability.reportSuccess();
            await _settle(tester, total: const Duration(seconds: 10));

            expect(tester.takeException(), isNull);
            expect(
              find.text(_requestTitle),
              findsOneWidget,
              reason: 'the desk reloaded by itself after recovery',
            );
            expect(find.byType(ScreenLoadErrorPanel), findsNothing);
            expect(
              server.count('MyWorkInit', from: sentBeforeRecovery),
              1,
              reason: 'one reload per recovery',
            );

            // Staying online issues no further reloads.
            await _settle(tester, total: const Duration(seconds: 60));
            expect(server.count('MyWorkInit', from: sentBeforeRecovery), 1);
          });
        },
      );
    }

    testWidgets(
      'a desk that is still failing shows «No connection» again and reloads '
      'again on the next recovery',
      (tester) async {
        final server = _Server()..down = true;
        await _withServer(tester, server, (remote, reachability) async {
          await _pumpHome(
            tester,
            deskCase: _deskCase(remote),
            reachability: reachability,
            surface: _desktopEn,
          );
          await _settle(tester, total: const Duration(seconds: 20));
          _expectNoConnectionPanel(tester);

          // A blip: online for a moment, but the reload fails again.
          final sentBeforeBlip = server.operations.length;
          reachability.reportSuccess();
          await _settle(tester);
          expect(
            server.operations.length,
            greaterThan(sentBeforeBlip),
            reason: 'the recovery started a reload of the failed desk',
          );
          _expectNoConnectionPanel(tester);
          expect(
            reachability.isOnline,
            isFalse,
            reason: 'the reload failed on transport and went offline again',
          );

          server.down = false;
          final sentBeforeRecovery = server.operations.length;
          reachability.reportSuccess();
          await _settle(tester, total: const Duration(seconds: 10));
          expect(find.text(_requestTitle), findsOneWidget);
          expect(find.byType(ScreenLoadErrorPanel), findsNothing);
          expect(server.count('MyWorkInit', from: sentBeforeRecovery), 1);
        });
      },
    );

    testWidgets(
      'a desk that loaded issues no reload when the app comes back online',
      (tester) async {
        final server = _Server();
        await _withServer(tester, server, (remote, reachability) async {
          await _pumpHome(
            tester,
            deskCase: _deskCase(remote),
            reachability: reachability,
            surface: _desktopEn,
          );
          await _settle(tester);
          expect(find.text(_requestTitle), findsOneWidget);
          final loadsBefore = server.count('MyWorkInit');
          expect(loadsBefore, 1);

          final changes = <bool>[];
          final sub = reachability.onlineChanges.listen(changes.add);
          addTearDown(sub.cancel);
          reachability.reportTransportFailure();
          await _settle(tester, total: const Duration(seconds: 1));
          expect(reachability.isOnline, isFalse);
          reachability.reportSuccess();
          await _settle(tester, total: const Duration(seconds: 30));

          expect(
            changes,
            contains(true),
            reason: 'the app did come back online during this test',
          );
          expect(reachability.isOnline, isTrue);
          expect(server.count('MyWorkInit'), loadsBefore);
          expect(find.text(_requestTitle), findsOneWidget);
        });
      },
    );
  });
}
