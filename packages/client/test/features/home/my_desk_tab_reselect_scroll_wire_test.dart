// The real Home shell over real HTTP: the viewer taps the My desk destination
// of the bottom bar while My desk is open, and the desk list moves to the first
// Request that carries a dot. Only the HTTP transport and unrelated shell
// dependencies are substituted; the dot travels wire -> GQL mapper ->
// repository -> MyWorkCubit -> card -> HomeScreen's destination handler.
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
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/profile.dart';
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
import 'package:tentura/features/home/ui/widget/home_bottom_navigation_bar.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';
import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_plan/beacon_plan_test_support.dart';
import '../beacon_view/beacon_view_case_test_support.dart'
    show FakeBeaconDisplayRepository;
import '../block/support/controllable_block_case.dart' show noopBlockCase;
import '../my_work/my_work_test_support.dart';

const _userId = 'Uauthor000001';
const _requestCount = 10;

/// The Request carrying the dot; the third on the desk.
const _dotRequest = 3;

/// The Request carrying a live obligation; the desk lists it before every
/// Request that only has a dot.
const _obligationRequest = 7;

/// What the server says needs the viewer.
enum _Attention {
  /// A dot on Request 3 only.
  dot,

  /// A dot on Request 3 and a live obligation on Request 7.
  dotAndObligation,

  /// Nothing.
  none,
}

_Attention _attention = _Attention.dot;

String _title(int n) => 'Request $n';
String _id(int n) => 'b$n';

Map<String, Object?> _aggregate(String type) => {
  '__typename': '${type}_aggregate',
  'aggregate': {'__typename': '${type}_aggregate_fields', 'count': 0},
};

/// Newest first, so the desk's "recent" order is Request 1, 2, 3 …
Map<String, Object?> _authoredRequest(int n) => {
  '__typename': 'beacon',
  'id': _id(n),
  'title': _title(n),
  'description': '',
  'needs': '',
  'tags': '',
  'status': 0,
  'kind': 0,
  'forward_policy': 0,
  'cover_source': 0,
  'is_discoverable': true,
  'created_at': DateTime.utc(
    2026,
    9,
    28,
  ).subtract(Duration(days: n)).toIso8601String(),
  'updated_at': DateTime.utc(
    2026,
    9,
    28,
  ).subtract(Duration(days: n)).toIso8601String(),
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

Map<String, Object?> _receipt(String beaconId, {required bool obligation}) => {
  '__typename': 'v2_AttentionReceipt',
  'id': '${obligation ? 'ob' : 'dot'}-$beaconId',
  'category': obligation ? 'asksOfMe' : 'coordination',
  'kind': obligation ? 'needsMe' : 'roomMessagePosted',
  'priority': 'normal',
  'title': 'Update',
  'body': 'Something happened',
  'actionUrl': '/#/',
  'createdAt': '2026-09-10T12:00:00Z',
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': beaconId,
  'coordinationItemId': null,
  'actorUserId': null,
  'sourceEventKey': null,
  'destinationKind': null,
  'targetEntityId': null,
  'presentationKey': obligation ? null : 'room_message_posted',
  'presentationPayloadJson': '{}',
  'inAppPreferenceClass': null,
  'requiresAction': obligation,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'clearedAt': null,
  'clearReason': null,
  'surface': 'myWork',
  'itemKind': 'receipt',
  'forwardOutcome': null,
  'forwardCount': null,
  'digestCount': null,
};

Map<String, Object?> _wireData(
  String operationName,
  Map<String, dynamic> vars,
) => switch (operationName) {
  'AttentionLiveObligations' => {
    'liveObligationBeacons': [
      if (_attention == _Attention.dotAndObligation) _id(_obligationRequest),
    ],
  },
  'MyWorkInit' => {
    'authoredNonArchived': [
      for (var n = 1; n <= _requestCount; n++) _authoredRequest(n),
    ],
    'helpOfferedNonArchived': <Object>[],
    'obligationBeacons': <Object>[],
    'archivedIdHints': <Object>[],
  },
  'MyWorkLastActivityEvent' => {'myWorkLastActivityEvent': <Object>[]},
  'MyWorkArchived' => {
    'archivedRows': <Object>[],
    'helpOfferedArchived': <Object>[],
  },
  'MyWorkAttention' => {
    'myWorkAttention': [
      if (_attention != _Attention.none)
        {
          '__typename': 'v2_MyWorkBeaconAttention',
          'beaconId': _id(_dotRequest),
          'unseenCount': 1,
          'needsYouAt': null,
          'firstEntryAt': null,
          'latestUnseen': _receipt(_id(_dotRequest), obligation: false),
          'liveObligations': <Object>[],
        },
      if (_attention == _Attention.dotAndObligation)
        {
          '__typename': 'v2_MyWorkBeaconAttention',
          'beaconId': _id(_obligationRequest),
          'unseenCount': 0,
          'needsYouAt': '2026-09-20T12:00:00Z',
          'firstEntryAt': null,
          'latestUnseen': null,
          'liveObligations': [
            _receipt(_id(_obligationRequest), obligation: true),
          ],
        },
    ],
  },
  _ => throw UnsupportedError('Unexpected operation: $operationName'),
};

http.Client _createClient() => MockClient((request) async {
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
  final vars = ((payload['variables'] as Map?) ?? const {})
      .cast<String, dynamic>();
  return http.Response(
    jsonEncode({'data': _wireData(name, vars)}),
    200,
    headers: {'content-type': 'application/json'},
  );
});

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
      Logger('desk-reselect-attention'),
    ),
    FakeBeaconPlanRepository(BeaconPlan.decode(planJson())),
    env: const Env(),
    logger: Logger('desk-reselect'),
  );
}

Future<void> _pumpHome(WidgetTester tester, MyWorkCase deskCase) async {
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
    ..registerSingleton<Logger>(Logger('desk-reselect'))
    ..registerSingleton<HomeAttentionCubit>(homeAttention)
    ..registerSingleton<PostJoinNavigationCubit>(postJoin)
    ..registerSingleton<PostJoinBeaconHandoffPort>(_NoInviteHandoff());

  // The real HomeRoute and tab branches; only the pages of tabs other than My
  // desk are blank.
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
      locale: const Locale('ru'),
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
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(find.byType(MyWorkScreen), findsOneWidget);
}

ScrollController _deskList(WidgetTester tester) => tester
    .widget<CustomScrollView>(
      find
          .descendant(
            of: find.byType(MyWorkScreen),
            matching: find.byType(CustomScrollView),
          )
          .first,
    )
    .controller!;

bool _inView(WidgetTester tester, int n) {
  final title = find.text(_title(n));
  if (title.evaluate().isEmpty) return false;
  final rect = tester.getRect(title);
  final view = tester.getRect(
    find
        .descendant(
          of: find.byType(MyWorkScreen),
          matching: find.byType(CustomScrollView),
        )
        .first,
  );
  return rect.top >= view.top && rect.bottom <= view.bottom;
}

Finder _navLabel(String label) => find.descendant(
  of: find.byType(HomeBottomNavigationBar),
  matching: find.text(label),
);

/// [finder] matches one Text laid out inside the 375 px screen. (The test
/// font is monospaced Ahem, so ellipsis state is not a trustworthy signal
/// here; overflow shows up as a framework exception, which callers check.)
void _expectRendersInFull(WidgetTester tester, Finder finder, String what) {
  expect(finder, findsOneWidget, reason: '$what is on screen');
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0), reason: '$what leaves the screen');
  expect(
    rect.right,
    lessThanOrEqualTo(kPhoneSurface.width),
    reason: '$what leaves the screen',
  );
}

/// The My desk destination label and the desk's section header read in full
/// in ru, and nothing overflowed.
void _expectDeskCopyInFull(
  WidgetTester tester,
  L10nRu l10n, {
  required String sectionHeader,
}) {
  expect(tester.takeException(), isNull, reason: 'no overflow in ru');
  _expectRendersInFull(tester, _navLabel(l10n.myWork), 'My desk label');
  _expectRendersInFull(
    tester,
    find.textContaining(sectionHeader.toUpperCase()),
    'section header «$sectionHeader»',
  );
}

Future<void> _scrollDeskToEnd(WidgetTester tester) async {
  final controller = _deskList(tester);
  controller.jumpTo(controller.position.maxScrollExtent);
  await tester.pumpAndSettle();
  expect(
    controller.offset,
    greaterThan(0),
    reason:
        'the desk must be taller than the screen for this test to mean '
        'anything',
  );
}

/// 375×667 logical pixels in the view itself, so `MediaQuery` and the window
/// class see a phone (the surface size alone leaves them at 800×600).
Future<void> _usePhone(WidgetTester tester) async {
  await usePhoneSurface(tester);
  tester.view.physicalSize = kPhoneSurface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _withHome(
  WidgetTester tester,
  Future<void> Function() body,
) => http.runWithClient(() async {
  final remote = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
  );
  try {
    await tester.runAsync(remote.setSessionAuth);
    await _pumpHome(tester, _deskCase(remote));
    await body();
  } finally {
    await tester.runAsync(remote.close);
  }
}, _createClient);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = L10nRu();

  setUp(() => _attention = _Attention.dot);

  group('Home bottom bar, 375×667, ru', () {
    testWidgets(
      'tapping the open My desk destination brings the Request with a dot into view',
      (tester) async {
        await _usePhone(tester);
        await _withHome(tester, () async {
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('request-attention-dot')),
            findsOneWidget,
            reason: 'precondition: the wire dot reached exactly one card',
          );
          _expectDeskCopyInFull(
            tester,
            l10n,
            sectionHeader: l10n.myWorkSectionInProgress,
          );
          await _scrollDeskToEnd(tester);
          expect(
            find.text(_title(_dotRequest)).hitTestable(),
            findsNothing,
            reason: 'precondition: the viewer has scrolled past the dot',
          );

          await tester.tap(_navLabel(l10n.myWork));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(_inView(tester, _dotRequest), isTrue);
          expect(
            _inView(tester, _requestCount),
            isFalse,
            reason: 'it went to the Request needing attention, not the end',
          );
          _expectRendersInFull(tester, _navLabel(l10n.myWork), 'My desk label');
        });
      },
    );

    testWidgets(
      'tapping the open My desk destination brings the Request with a live obligation into view, ahead of a dot above it',
      (tester) async {
        _attention = _Attention.dotAndObligation;
        await _usePhone(tester);
        await _withHome(tester, () async {
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('request-attention-dot')),
            findsOneWidget,
            reason: 'precondition: the wire dot reached its card',
          );
          _expectDeskCopyInFull(
            tester,
            l10n,
            sectionHeader: l10n.myWorkSectionNeedsYou,
          );
          await _scrollDeskToEnd(tester);
          expect(
            find.text(_title(_obligationRequest)).hitTestable(),
            findsNothing,
            reason: 'precondition: the viewer has scrolled past the obligation',
          );

          await tester.tap(_navLabel(l10n.myWork));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            _inView(tester, _obligationRequest),
            isTrue,
            reason:
                'the wire obligation reached the desk and is what the tap '
                'lands on',
          );
          expect(_inView(tester, _requestCount), isFalse);
        });
      },
    );

    testWidgets(
      'tapping the open My desk destination goes to the top when no Request needs attention',
      (tester) async {
        _attention = _Attention.none;
        await _usePhone(tester);
        await _withHome(tester, () async {
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('request-attention-dot')),
            findsNothing,
            reason: 'precondition: the wire carries no attention at all',
          );
          _expectRendersInFull(
            tester,
            find.text(l10n.myWorkCaughtUp),
            'caught-up line',
          );
          await _scrollDeskToEnd(tester);

          await tester.tap(_navLabel(l10n.myWork));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(_deskList(tester).offset, 0);
          expect(_inView(tester, 1), isTrue);
          _expectDeskCopyInFull(
            tester,
            l10n,
            sectionHeader: l10n.myWorkSectionInProgress,
          );
        });
      },
    );

    testWidgets(
      'opening My desk from another tab leaves the desk list where it was',
      (tester) async {
        await _usePhone(tester);
        await _withHome(tester, () async {
          await tester.pumpAndSettle();
          await _scrollDeskToEnd(tester);
          final left = _deskList(tester).offset;

          await tester.tap(_navLabel(l10n.inbox));
          await tester.pumpAndSettle();
          await tester.tap(_navLabel(l10n.myWork));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(_deskList(tester).offset, left);
          expect(_inView(tester, _dotRequest), isFalse);
        });
      },
    );
  });
}
