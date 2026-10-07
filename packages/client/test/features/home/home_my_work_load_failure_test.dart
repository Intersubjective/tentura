// Home's eager desk load calls MyWorkCase.loadDeskInit -> fetchInit ->
// AttentionRepository.liveObligationBeacons, then MyWorkRepository.fetchInit.
// Both repositories, and fetchArchived, use firstWhere(DataSource.Link).
// A completed stream with no link response currently throws No element.
// Keep those real call sites and the real Home/My Work widgets under test;
// substitute only HTTP and unrelated shell dependencies.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/domain/entity/post_join_destination.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/domain/port/post_join_beacon_handoff_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/home/ui/screen/home_screen.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';
import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import '../../support/remote_load_failure_matcher.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_view/beacon_view_case_test_support.dart'
    show FakeBeaconDisplayRepository;
import '../block/support/controllable_block_case.dart' show noopBlockCase;
import '../my_work/my_work_test_support.dart';

const _userId = 'Uauthor000001';

/// Real Ferry requests are left in flight until the service is disposed.
/// HTTP is the only substituted boundary in the desk's load chain.
class _RemoteFailureScenario {
  _RemoteFailureScenario(this.failedOperation);

  final String failedOperation;
  bool recovered = false;
  final operations = <String>[];
  final started = Completer<void>();
  final pendingResponse = Completer<http.Response>();

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
    if (!recovered && name == failedOperation) {
      if (!started.isCompleted) started.complete();
      return pendingResponse.future;
    }
    final data = switch (name) {
      'AttentionLiveObligations' => <String, dynamic>{
        'liveObligationBeacons': <String>[],
      },
      'MyWorkInit' => <String, dynamic>{
        'authoredNonArchived': <Object>[],
        'helpOfferedNonArchived': <Object>[],
        'obligationBeacons': <Object>[],
        'archivedIdHints': <Object>[],
      },
      'MyWorkArchived' => <String, dynamic>{
        'archivedRows': <Object>[],
        'helpOfferedArchived': <Object>[],
      },
      _ => throw UnsupportedError('Unexpected operation: $name'),
    };
    return http.Response(
      jsonEncode({'data': data}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

Future<void> _withRemote(
  _RemoteFailureScenario scenario,
  Future<void> Function(RemoteApiService remote) body, {
  WidgetTester? tester,
}) => http.runWithClient(() async {
  final remote = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
  );
  try {
    if (tester == null) {
      await remote.setSessionAuth();
    } else {
      await tester.runAsync(remote.setSessionAuth);
    }
    await body(remote);
  } finally {
    if (tester == null) {
      await remote.close();
    } else {
      await tester.runAsync(remote.close);
    }
  }
}, scenario.createClient);

/// The attention port permits a stream that completes without a link result.
/// Keep the real repository's firstWhere, rather than faking a thrown error.
class _CompletingAttentionClient implements RemoteRequestClient {
  _CompletingAttentionClient({required this.cacheOnly});

  final bool cacheOnly;
  bool recovered = false;
  final operations = <String>[];

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    final name = request.operation.operationName!;
    operations.add(name);
    if (name != 'AttentionLiveObligations') {
      throw UnsupportedError('Unexpected attention operation: $name');
    }
    if (!recovered && !cacheOnly) return const Stream.empty();
    return Stream.value(
      OperationResponse(
        operationRequest: request,
        data: request.parseData({'liveObligationBeacons': <String>[]}),
        dataSource: recovered ? DataSource.Link : DataSource.Cache,
      ),
    );
  }
}

class _Accounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

MyWorkCase _deskCase(
  RemoteApiService remote, {
  RemoteRequestClient? attentionClient,
}) {
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
      AttentionRepository(attentionClient ?? remote),
      _Accounts(),
      realtime,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('home-desk-attention'),
    ),
    env: const Env(),
    logger: Logger('home-desk'),
  );
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

Future<MyWorkCubit> _pumpHome(
  WidgetTester tester, {
  required MyWorkCase deskCase,
}) async {
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
    ..registerSingleton<AuthCubit>(_SignedInAuthCubit())
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
    ..registerSingleton<Logger>(Logger('home-load'))
    ..registerSingleton<HomeAttentionCubit>(homeAttention)
    ..registerSingleton<PostJoinNavigationCubit>(postJoin)
    ..registerSingleton<PostJoinBeaconHandoffPort>(_NoInviteHandoff());

  // Use the real HomeRoute page and account wrapper: _InboxScope creates the
  // real eager MyWorkCubit through DI, alongside an empty unrelated Inbox.
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
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      routerConfig: router.config(),
      builder: (_, child) => TenturaResponsiveScope(child: child!),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(router.current.name, HomeRoute.name);
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(find.byType(MyWorkScreen), findsOneWidget);
  return tester.element(find.byType(MyWorkScreen)).read<MyWorkCubit>();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Home desk loads when attention ends without a link response', () {
    for (final cacheOnly in [false, true]) {
      final stream = cacheOnly ? 'cache-only' : 'empty';
      test(
        'loadDeskInit reports a remote failure when the $stream obligation stream has no link response',
        () async {
          final attention = _CompletingAttentionClient(cacheOnly: cacheOnly);
          final scenario = _RemoteFailureScenario('');
          await _withRemote(scenario, (remote) async {
            final deskCase = _deskCase(remote, attentionClient: attention);
            await expectLater(
              deskCase.loadDeskInit(userId: _userId),
              throwsA(remoteLoadFailure()),
            );
            expect(attention.operations, ['AttentionLiveObligations']);
            expect(
              scenario.operations,
              isEmpty,
              reason:
                  'The failed obligation prerequisite must stop MyWorkInit.',
            );
          });
        },
      );
    }
  });

  group('HomeRoute desk failure and retry', () {
    for (final cacheOnly in [false, true]) {
      final stream = cacheOnly ? 'cache-only' : 'empty';
      testWidgets(
        'the $stream obligation stream presents a recoverable load error and retries',
        (tester) async {
          final attention = _CompletingAttentionClient(cacheOnly: cacheOnly);
          final scenario = _RemoteFailureScenario('');
          await _withRemote(scenario, (remote) async {
            final desk = await _pumpHome(
              tester,
              deskCase: _deskCase(remote, attentionClient: attention),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byType(ScreenLoadErrorPanel), findsOneWidget);
            expect(desk.state.nonArchivedProjectionLoaded, isFalse);
            expect(desk.state.loadError, isNot(isA<StateError>()));
            expect(desk.state.loadError, remoteLoadFailure());
            expect(find.textContaining('Bad state: No element'), findsNothing);
            expect(attention.operations, ['AttentionLiveObligations']);
            expect(scenario.operations, isEmpty);

            attention.recovered = true;
            final l10n = L10n.of(
              tester.element(find.byType(ScreenLoadErrorPanel)),
            )!;
            await tester.tap(find.text(l10n.myWorkRetry));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byType(HomeScreen), findsOneWidget);
            expect(find.byType(ScreenLoadErrorPanel), findsNothing);
            expect(desk.state.loadError, isNull);
            expect(desk.state.nonArchivedProjectionLoaded, isTrue);
            expect(attention.operations, [
              'AttentionLiveObligations',
              'AttentionLiveObligations',
            ]);
            expect(scenario.operations, ['MyWorkInit']);
          }, tester: tester);
        },
      );
    }
  });
}
