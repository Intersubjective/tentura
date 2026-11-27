import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_remote_repository.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/auth/ui/bloc/register_invite_cubit.dart';
import 'package:tentura/features/auth/ui/screen/auth_register_screen.dart';
import 'package:tentura/features/home/domain/entity/post_join_destination.dart';
import 'package:tentura/features/home/domain/port/post_join_beacon_handoff_port.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/home/ui/widget/home_post_join_listener.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/ui/bloc/accept_invite_cubit.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_accept_dialog.dart';
import 'package:tentura/features/invitation/ui/message/accept_invite_messages.dart';
import 'package:tentura/features/invitation/ui/screen/accept_invite_screen.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import '../../data/service/_session_account_test_harness.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';

const _code = 'I806d29daebbe';
const _requestId = 'B1';
const _title = 'Fix the roof';
const _inviter = 'Vadim';
const _accountId = 'Uviewer000001';
const _ru = Locale('ru');
const _previewPath = '/api/v2/invite/$_code/preview';
const _acceptPath = '/api/v2/invite/$_code/accept-as-existing';
const _requestAccepted = BeaconInviteAcceptedMessage(
  inviterName: _inviter,
  beaconId: _requestId,
  beaconTitle: _title,
);

void main() {
  for (final lapsed in [true, false]) {
    final requestState = lapsed ? 'a closed Request' : 'an open Request';
    test(
      'confirming $requestState invite consumes it and '
      '${lapsed ? 'returns to Home' : 'hands the Request to Inbox'}',
      () async {
        final wire = _InviteHttp(lapsed: lapsed, existingAccount: true);
        await wire.run((repository) async {
          final effects = FakeUiEffectPort();
          final postJoin = PostJoinNavigationCubit();
          final cubit = AcceptInviteCubit(repository, effects, postJoin);
          addTearDown(cubit.close);

          await cubit.start(_code);
          expect(cubit.state.needsConfirmation, isTrue);
          expect(cubit.state.pendingBeacon?.lapsed, lapsed);
          expect(cubit.state.pendingBeacon?.id, _requestId);
          await cubit.confirmAccept();

          expect(wire.inviteRequests, [
            'GET $_previewPath',
            'POST $_acceptPath',
          ]);
          expect(effects.emitted.whereType<ShowError>(), isEmpty);
          expect(_requestMessages(effects), isEmpty);
          expect(
            <String, Object?>{
              'destination': postJoin.takeDestination(),
              'targets': effects.emitted
                  .whereType<NavigateReplace>()
                  .map((effect) => effect.target)
                  .toList(),
            },
            <String, Object>{
              'destination': lapsed ? isNull : _openRequestDestination,
              'targets': [
                if (lapsed)
                  NavigateReplaceTarget.home
                else
                  NavigateReplaceTarget.homeInboxTab,
              ],
            },
          );
        });
      },
    );
  }

  group('Request invite completion uses the server outcome', () {
    test(
      'confirmation opens Activity only when the Request remains open',
      () async {
        for (final requestLapsed in [false, true]) {
          final wire = _InviteHttp(
            lapsed: false,
            existingAccount: true,
            completionLapsed: requestLapsed,
          );
          await wire.run((repository) async {
            final effects = FakeUiEffectPort();
            final postJoin = _ObservedPostJoin();
            final cubit = AcceptInviteCubit(repository, effects, postJoin);
            addTearDown(cubit.close);

            await cubit.start(_code);
            expect(cubit.state.needsConfirmation, isTrue);
            expect(cubit.state.pendingBeacon?.lapsed, isFalse);
            expect(cubit.state.pendingBeacon?.id, _requestId);
            await cubit.confirmAccept();

            expect(wire.inviteRequests, [
              'GET $_previewPath',
              'POST $_acceptPath',
            ]);
            expect(effects.emitted.whereType<ShowError>(), isEmpty);
            final messages = effects.emitted.whereType<ShowMessage>().map(
              (effect) => effect.message,
            );
            expect(messages.whereType<BeaconInviteAcceptedMessage>(), isEmpty);
            expect(messages.whereType<InviteAcceptedMessage>(), isEmpty);
            expect(
              {
                'destinations registered': postJoin.handoffs,
                'destination': postJoin.takeDestination(),
                'navigation': effects.emitted
                    .whereType<NavigateReplace>()
                    .map((effect) => effect.target)
                    .toList(),
              },
              {
                'destinations registered': requestLapsed ? 0 : 1,
                'destination': requestLapsed ? isNull : _openRequestDestination,
                'navigation': [
                  if (requestLapsed)
                    NavigateReplaceTarget.home
                  else
                    NavigateReplaceTarget.homeInboxTab,
                ],
              },
              reason: 'accept response requestLapsed=$requestLapsed',
            );
          });
        }
      },
    );

    for (final requestLapsed in [false, true]) {
      testWidgets(
        requestLapsed
            ? 'registration leaves the closed Request and its snackbar behind'
            : 'registration confirms the Request is open and shows its snackbar',
        (tester) async {
          await usePhoneSurface(tester);
          addTearDown(_replaceUnrelatedPages());
          final wire = _InviteHttp(
            lapsed: false,
            existingAccount: false,
            completionLapsed: requestLapsed,
          );
          await wire.run((repository) async {
            final auth = (await tester.runAsync(
              () => _signupAuth(wire.remote),
            ))!;
            final app = await _openInviteLink(
              tester,
              repository: repository,
              existingAccount: false,
              signupAuth: auth,
            );
            expect(find.byType(AuthRegisterScreen), findsOneWidget);
            expect(app.register.state.preview?.beacon?.lapsed, isFalse);
            expect(app.register.state.preview?.beacon?.id, _requestId);
            expect(app.postJoin.handoffs, 0);
            final l10n = lookupL10n(_ru);
            final name = find.widgetWithText(
              TextFormField,
              l10n.labelDisplayName,
            );
            await tester.enterText(name, 'New member');
            final choice = find.text(l10n.buttonNo);
            await tester.ensureVisible(choice);
            await tester.tap(choice);
            await tester.pump();
            final submit = find.widgetWithText(FilledButton, l10n.buttonCreate);
            await tester.ensureVisible(submit);
            // Ferry and HTTP callbacks may settle between rendered frames.
            await tester.runAsync(() async {
              await tester.tap(submit);
              await waitUntil(
                'The signup result did not authenticate the new member',
                () => auth.state.currentAccountId == _accountId,
              );
            });
            await _pumpPage(tester);

            expect(wire.signupQueries, hasLength(1));
            expect(auth.state.currentAccountId, _accountId);
            expect(find.byType(AuthRegisterScreen), findsNothing);
            expect(tester.takeException(), isNull);
            _expectHomeOutcome(app, opensRequest: !requestLapsed);
            expect(app.postJoin.handoffs, requestLapsed ? 0 : 1);
            expect(wire.signupQueries.single, contains('requestLapsed'));
          });
        },
        timeout: const Timeout(Duration(seconds: 15)),
      );
    }
  });

  group('after opening a Request invite link', () {
    late void Function() restorePages;
    setUp(() => restorePages = _replaceUnrelatedPages());
    tearDown(() => restorePages());

    for (final lapsed in [true, false]) {
      testWidgets(
        lapsed
            ? 'accepting a closed Request in Russian on a phone stays on Home'
            : 'accepting an open Request opens it and shows the accepted message',
        (tester) async {
          await usePhoneSurface(tester);
          tester.view
            ..physicalSize = kPhoneSurface
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final wire = _InviteHttp(lapsed: lapsed, existingAccount: true);
          await wire.run((repository) async {
            final app = await _openInviteLink(
              tester,
              repository: repository,
              existingAccount: true,
            );
            final l10n = lookupL10n(_ru);
            final dialog = find.byType(InvitationAcceptDialog);
            expect(tester.takeException(), isNull);
            expect(find.byType(AcceptInviteScreen), findsOneWidget);
            expect(wire.inviteRequests, ['GET $_previewPath']);
            expect(app.accept.state.pendingBeacon?.lapsed, lapsed);
            expect(dialog, findsOneWidget);
            if (lapsed) {
              final closureCopy = find.text(
                'Vadim пригласил вас в запрос «Fix the roof», но он уже закрыт.',
                findRichText: true,
              );
              expect(closureCopy, findsOneWidget);
              expect(
                tester
                    .renderObject<RenderParagraph>(closureCopy)
                    .didExceedMaxLines,
                isFalse,
              );
            } else {
              expect(find.text(_title), findsOneWidget);
            }
            expect(tester.takeException(), isNull);

            await tester.tap(
              find.descendant(
                of: dialog,
                matching: find.widgetWithText(
                  TextButton,
                  lapsed ? l10n.inviteAccept : l10n.buttonYes,
                ),
              ),
            );
            await _pumpPage(tester);

            expect(wire.inviteRequests, [
              'GET $_previewPath',
              'POST $_acceptPath',
            ]);
            expect(dialog, findsNothing);
            expect(tester.takeException(), isNull);
            _expectHomeOutcome(app, opensRequest: !lapsed);
          });
        },
      );

      testWidgets(
        lapsed
            ? 'signup through a closed Request invite leaves no Request to open'
            : 'signup through an open Request invite opens it with the accepted message',
        (tester) async {
          final wire = _InviteHttp(lapsed: lapsed, existingAccount: false);
          await wire.run((repository) async {
            final app = await _openInviteLink(
              tester,
              repository: repository,
              existingAccount: false,
            );

            expect(find.byType(AuthRegisterScreen), findsOneWidget);
            expect(app.auth.state.isAuthenticated, isFalse);
            expect(wire.inviteRequests, ['GET $_previewPath']);
            expect(app.register.state.preview?.beacon?.id, _requestId);
            expect(app.register.state.preview?.beacon?.lapsed, lapsed);
            expect(app.postJoin.hasPending, isFalse);

            app.auth.completeSignup();
            await _pumpPage(tester);

            expect(find.byType(AuthRegisterScreen), findsNothing);
            expect(tester.takeException(), isNull);
            _expectHomeOutcome(app, opensRequest: !lapsed);
          });
        },
      );
    }
  });
}

Matcher get _openRequestDestination => isA<PostJoinDestination>()
    .having((destination) => destination.beaconId, 'beaconId', _requestId)
    .having((destination) => destination.beaconTitle, 'beaconTitle', _title)
    .having((destination) => destination.inviterName, 'inviterName', _inviter)
    .having((destination) => destination.showSnackbar, 'showSnackbar', true);

Iterable<BeaconInviteAcceptedMessage> _requestMessages(
  FakeUiEffectPort effects,
) => effects.emitted
    .whereType<ShowMessage>()
    .map((effect) => effect.message)
    .whereType<BeaconInviteAcceptedMessage>();

class _InviteHttp {
  _InviteHttp({
    required this.lapsed,
    required this.existingAccount,
    this.completionLapsed,
  });

  final bool lapsed;
  final bool existingAccount;
  final bool? completionLapsed;
  late final RemoteApiService remote;
  final signupQueries = <String>[];
  final inviteRequests = <String>[];

  Future<void> run(Future<void> Function(InvitationRepository) body) =>
      http.runWithClient(
        () async {
          remote = testRealtimeClient();
          final repository = InvitationRepository(remote);
          addTearDown(remote.close);
          addTearDown(repository.dispose);
          if (existingAccount) await remote.setSessionAuth();
          await body(repository);
        },
        () => MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/v2/session/access-token') {
            expect(existingAccount, isTrue);
            expect(request.method, 'POST');
            return _json({
              'subject': _accountId,
              'access_token': 'invite-test-token',
              'expires_in': 3600,
            });
          }
          if (path.endsWith('/graphql')) {
            final query = jsonDecode(request.body) as Map;
            expect(request.method, 'POST');
            expect(query['operationName'], 'SignUp');
            expect(
              query['variables'],
              containsPair('displayName', 'New member'),
            );
            final selection = query['query'] as String;
            signupQueries.add(selection);
            return _json({
              'data': {
                'signUp': {
                  'subject': _accountId,
                  if (selection.contains('requestLapsed'))
                    'requestLapsed': completionLapsed,
                },
              },
            });
          }
          inviteRequests.add('${request.method} $path');
          expect(
            request.headers['Authorization'],
            existingAccount ? 'Bearer invite-test-token' : isNull,
          );
          return switch ((request.method, path)) {
            ('GET', _previewPath) => _json({
              'codeStatus': 'available',
              'callerStatus': existingAccount ? 'existing-user' : 'anonymous',
              'suggestedAction': existingAccount
                  ? 'accept-as-existing'
                  : 'accept-as-new',
              'inviter': {'id': 'Uissuer000001', 'displayName': _inviter},
              'beacon': {
                'id': _requestId,
                'title': _title,
                'kind': 'request',
                'lapsed': lapsed,
              },
            }),
            ('POST', _acceptPath) =>
              completionLapsed == null
                  ? http.Response('', 204)
                  : _json({'ok': true, 'requestLapsed': completionLapsed}),
            _ => throw StateError(
              'Unexpected invite request ${request.method} $path',
            ),
          };
        }),
      );

  static http.Response _json(Map<String, Object?> value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json'},
  );
}

Future<AuthCubit> _signupAuth(RemoteApiService remote) {
  const env = Env(needInviteCode: true);
  final log = Logger('RequestInviteSignup');
  final local = _SignupLocal();
  addTearDown(local.dispose);
  final repository = AuthRemoteRepository(remoteApiService: remote, log: log);
  final profiles = _SignupProfiles();
  return AuthCubit.hydrated(
    env,
    AuthCase(
      local,
      repository,
      TestDevicePush(),
      _NativeAuthCleanup(),
      TestSettingsRepository(),
      env: env,
      logger: log,
    ),
    AccountCase(
      local,
      repository,
      _SignupPlatform(),
      profiles,
      env: env,
      logger: log,
    ),
    profiles,
    FakeUiEffectPort(),
  );
}

class _SignupLocal extends EmptyAuthLocal {
  final _accountChanges = StreamController<String>.broadcast();

  @override
  Stream<String> currentAccountChanges() => _accountChanges.stream;

  @override
  Future<void> setCurrentAccountId(String? id) async {
    _accountChanges.add(id ?? '');
  }

  @override
  Future<void> retainOnlyAccount(String keepId) =>
      Future<void>.delayed(Duration.zero);

  @override
  Future<void> dispose() => _accountChanges.close();
}

class _NativeAuthCleanup extends TestAuthPlatformCleanup {
  @override
  bool get skipSessionCookieBootstrap => true;
}

class _SignupProfiles extends Fake implements ProfileRepositoryPort {
  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();
}

class _SignupPlatform extends Fake implements PlatformRepositoryPort {}

class _Auth extends Cubit<AuthState> implements AuthCubit {
  _Auth({required bool authenticated})
    : super(
        AuthState(
          updatedAt: DateTime.utc(2026),
          currentAccountId: authenticated ? _accountId : '',
        ),
      );

  void completeSignup() => emit(state.copyWith(currentAccountId: _accountId));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

class _NativeHandoff implements PostJoinBeaconHandoffPort {
  @override
  PostJoinDestination? readAndClear() => null;
}

class _ObservedPostJoin extends PostJoinNavigationCubit {
  final destinations = <PostJoinDestination>[];

  int handoffs = 0;

  @override
  void setFromBeaconInvite({
    required String beaconId,
    required String beaconTitle,
    String inviterName = '',
    bool showSnackbar = true,
    bool isPost = false,
  }) {
    handoffs++;
    super.setFromBeaconInvite(
      beaconId: beaconId,
      beaconTitle: beaconTitle,
      inviterName: inviterName,
      showSnackbar: showSnackbar,
      isPost: isPost,
    );
  }

  @override
  PostJoinDestination? takeDestination() {
    final destination = super.takeDestination();
    if (destination != null) destinations.add(destination);
    return destination;
  }
}

class _RequestPushes extends NavigatorObserver {
  _RequestPushes(this.ids);

  final List<String> ids;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final page = route.settings;
    if (page is AutoRoutePage && page.name == BeaconViewRoute.name) {
      ids.add(page.routeData.params.getString('id'));
    }
  }
}

typedef _InviteApp = ({
  RootRouter router,
  _Auth auth,
  AcceptInviteCubit accept,
  RegisterInviteCubit register,
  _ObservedPostJoin postJoin,
  List<String> requests,
});

Future<_InviteApp> _openInviteLink(
  WidgetTester tester, {
  required InvitationRepository repository,
  required bool existingAccount,
  AuthCubit? signupAuth,
}) async {
  final fakeAuth = _Auth(authenticated: existingAccount);
  final auth = signupAuth ?? fakeAuth;
  final postJoin = _ObservedPostJoin();
  final effects = FakeUiEffectPort();
  final screen = ScreenCubit(effects);
  final accept = AcceptInviteCubit(repository, effects, postJoin);
  final register = RegisterInviteCubit(repository, effects);
  final router = RootRouter(
    Logger('RequestInviteRouter'),
    auth,
    _Settings(),
    postJoin,
  );
  final requests = <String>[];

  GetIt.I
    ..registerSingleton<AppNavigator>(router)
    ..registerSingleton<AuthCubit>(auth)
    ..registerSingleton<Env>(const Env(needInviteCode: true))
    ..registerSingleton<AcceptInviteCubit>(accept)
    ..registerSingleton<RegisterInviteCubit>(register)
    ..registerSingleton<PostJoinNavigationCubit>(postJoin)
    ..registerSingleton<PostJoinBeaconHandoffPort>(_NativeHandoff())
    ..registerSingleton<ScreenCubit>(screen)
    ..registerSingleton<UiEffectPort>(effects);

  tester.binding.platformDispatcher.defaultRouteNameTestValue =
      '/invite/$_code';
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
    await GetIt.I.reset();
    router.dispose();
    await fakeAuth.close();
    await signupAuth?.dispose();
    await screen.close();
    if (!accept.isClosed) await accept.close();
    if (!register.isClosed) await register.close();
  });

  await tester.pumpWidget(
    MaterialApp.router(
      locale: _ru,
      theme: TenturaTheme.light(),
      scaffoldMessengerKey: snackbarKey,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => TenturaResponsiveScope(
        child: UiEffectHandler(effects: effects, child: child!),
      ),
      routerConfig: router.config(
        deepLinkBuilder: router.deepLinkBuilder,
        deepLinkTransformer: router.deepLinkTransformer,
        reevaluateListenable: router.reevaluateListenable,
        includePrefixMatches: false,
        navigatorObservers: () => [
          ClearSnackBarsOnPushObserver(),
          _RequestPushes(requests),
        ],
      ),
    ),
  );
  await _pumpPage(tester);
  return (
    router: router,
    auth: fakeAuth,
    accept: accept,
    register: register,
    postJoin: postJoin,
    requests: requests,
  );
}

Future<void> _pumpPage(WidgetTester tester) async {
  // Allow the two end-of-frame waits in Home's real handoff and the snackbar
  // animation, while keeping the snackbar within its display window.
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _expectHomeOutcome(_InviteApp app, {required bool opensRequest}) {
  final snack = find.descendant(
    of: find.byType(SnackBar),
    matching: find.text(_requestAccepted.toRu, findRichText: true),
  );
  expect(
    <String, Object>{
      'root routes': app.router.stackData.map((route) => route.name).toList(),
      'Request detail routes pushed': app.requests,
      'Request acceptance snackbars': snack.evaluate().length,
      'consumed post-join destinations': app.postJoin.destinations,
      'pending post-join destination': app.postJoin.hasPending,
    },
    <String, Object>{
      'root routes': [HomeRoute.name, if (opensRequest) BeaconViewRoute.name],
      'Request detail routes pushed': opensRequest ? [_requestId] : [],
      'Request acceptance snackbars': opensRequest ? 1 : 0,
      'consumed post-join destinations': opensRequest
          ? [_openRequestDestination]
          : [],
      'pending post-join destination': false,
    },
  );
}

class _HomeShell extends StatelessWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: [for (final spec in HomeTabSpec.all) spec.shell()],
    duration: Duration.zero,
    transitionBuilder: (_, child, _) => child,
    builder: (context, child) => HomePostJoinListener(
      tabsRouter: context.tabsRouter,
      child: Scaffold(body: child),
    ),
  );
}

void Function() _replaceUnrelatedPages() {
  final restore = <void Function()>[];

  void replace(
    PageInfo original,
    void Function(PageInfo) assign,
    Widget child,
  ) {
    assign(PageInfo(original.name, builder: (_) => child));
    restore.add(() => assign(original));
  }

  // Use the actual router and Home's handoff, with inert tab and detail bodies.
  replace(HomeRoute.page, (page) => HomeRoute.page = page, const _HomeShell());
  for (final (original, assign) in <(PageInfo, void Function(PageInfo))>[
    (MyWorkRoute.page, (page) => MyWorkRoute.page = page),
    (ConversationsRoute.page, (page) => ConversationsRoute.page = page),
    (InboxRoute.page, (page) => InboxRoute.page = page),
    (ConstellationRoute.page, (page) => ConstellationRoute.page = page),
    (FriendsRoute.page, (page) => FriendsRoute.page = page),
    (ProfileRoute.page, (page) => ProfileRoute.page = page),
    (
      BeaconViewOperationalRoute.page,
      (page) => BeaconViewOperationalRoute.page = page,
    ),
  ]) {
    replace(original, assign, const SizedBox.shrink());
  }
  replace(
    BeaconViewRoute.page,
    (page) => BeaconViewRoute.page = page,
    const Scaffold(body: AutoRouter()),
  );
  return () {
    for (final reset in restore.reversed) {
      reset();
    }
  };
}
