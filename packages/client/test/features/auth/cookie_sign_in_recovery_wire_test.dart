// Session authentication uses a REST access-token response rather than a GQL
// sign-in operation. Keep its production parser, repository, use case, cubit,
// account tile and recovery/error UI; fake only HTTP, sockets and local storage.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Mock;

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/auth/ui/widget/account_list_tile.dart';
import 'package:tentura/features/auth/ui/widget/auth_recovery_listener.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../data/service/_session_account_test_harness.dart';
import '../../support/phone_surface.dart';
import 'auth_test_helpers.dart';
import 'cookie_sign_in_test_support.dart';

void main() {
  setUp(() {
    GetIt.I
      ..registerSingleton<RootRouter>(_UnusedRouter())
      ..registerSingleton<Logger>(Logger('CookieSignInRecoveryWireTest'));
  });
  tearDown(GetIt.I.reset);

  group('Saved account sign-in recovery', () {
    for (final credentials in [
      (description: 'a session-only account', hasSession: true, seed: null),
      (
        description: 'a session account with a usable recovery seed',
        hasSession: true,
        seed: selectedAccountSeed,
      ),
      (
        description: 'a seed account without a session marker',
        hasSession: false,
        seed: selectedAccountSeed,
      ),
    ]) {
      for (final language in ['en', 'ru']) {
        testWidgets(
          'a parsed cookie identity mismatch displays a named '
          'sign-in-again instruction for ${credentials.description} '
          'at 375x667 $language',
          (tester) async {
            await usePhoneSurface(tester);
            var responseSubject = unrelatedAccountId;
            var holdMismatchResponse = false;
            final requests = <http.Request>[];
            final responses = <Map<String, dynamic>>[];
            final releaseMismatch = Completer<void>();
            final server = MockClient((request) async {
              requests.add(request);
              if (request.url.path == '/api/v2/session/access-token') {
                // The identity comes only from this HTTP body. In particular,
                // neither the local account nor the profile double supplies it.
                final body = jsonEncode({
                  'subject': responseSubject,
                  'access_token': 'token-$responseSubject',
                  'expires_in': 3600,
                });
                if (holdMismatchResponse) {
                  await releaseMismatch.future;
                }
                final response = http.Response(
                  body,
                  200,
                  headers: {'content-type': 'application/json'},
                );
                responses.add(
                  jsonDecode(response.body) as Map<String, dynamic>,
                );
                return response;
              }
              if (request.url.path.endsWith('/graphql')) {
                final operation =
                    jsonDecode(request.body) as Map<String, dynamic>;
                if (operation['operationName'] == 'SignIn') {
                  return http.Response(
                    jsonEncode({
                      'data': {
                        '__typename': 'mutation_root',
                        'signIn': {
                          '__typename': 'v2_AuthResponse',
                          'subject': selectedAccountId,
                          'access_token': 'seed-token-$selectedAccountId',
                          'expires_in': 3600,
                        },
                      },
                    }),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                if (operation['operationName'] == 'SignOut') {
                  return http.Response(
                    jsonEncode({
                      'data': {'__typename': 'mutation_root', 'signOut': true},
                    }),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                throw StateError(
                  'Unexpected operation: ${operation['operationName']}',
                );
              }
              return http.Response('{}', 200);
            });
            await tester.runAsync(
              () => http.runWithClient(() async {
                final transport = testRealtimeClient();
                final local = CookieSignInLocal(
                  selectedHasSession: credentials.hasSession,
                  selectedSeed: credentials.seed,
                );
                final effects = _Effects();
                AuthCubit? cubit;
                StreamSubscription<AuthState>? states;
                try {
                  final remote = ObservedCookieSignInRemote(
                    remoteApiService: transport,
                    log: Logger('CookieSignInRecoveryWireTest'),
                  );
                  if (credentials.seed != null) {
                    // Prove that the stored seed works through the real signing,
                    // GQL parsing and session-convergence path. A later fallback
                    // would really authenticate Alice, rather than fail because
                    // the seed or the fake HTTP response was malformed.
                    final storedSeed = await local.getSeedByAccountId(
                      selectedAccountId,
                    );
                    expect(
                      AccountCase.normalizeSeed(storedSeed),
                      selectedAccountSeed,
                    );
                    expect(await remote.signIn(storedSeed), selectedAccountId);
                    final seedToken = await transport.getAuthToken();
                    expect(seedToken.userId, selectedAccountId);
                    expect(
                      seedToken.accessToken,
                      'seed-token-$selectedAccountId',
                    );
                    expect(
                      requests
                          .where(
                            (request) =>
                                request.url.path ==
                                '/api/v2/session/from-bearer',
                          )
                          .last
                          .headers['Authorization'],
                      'Bearer seed-token-$selectedAccountId',
                    );
                  }
                  final profiles = _UnusedProfiles();
                  cubit = await AuthCubit.hydrated(
                    const Env(),
                    AuthCase(
                      local,
                      remote,
                      TestDevicePush(),
                      CookiePreferencePlatform(),
                      TestSettingsRepository(),
                      env: const Env(),
                      logger: Logger('CookieSignInRecoveryWireTest'),
                    ),
                    AccountCase(
                      local,
                      remote,
                      _UnusedPlatform(),
                      profiles,
                      env: const Env(),
                      logger: Logger('CookieSignInRecoveryWireTest'),
                    ),
                    profiles,
                    effects,
                  );
                  final auth = cubit;
                  expect(auth.state.currentAccountId, unrelatedAccountId);
                  expect(transport.realtimeAccountId, unrelatedAccountId);
                  expect(remote.parsedSessionSubjects.last, unrelatedAccountId);
                  expect(transport.hasValidToken, isTrue);
                  final published = <String>[];
                  states = auth.stream.listen(
                    (state) => published.add(state.currentAccountId),
                  );
                  final profileCubit = _CurrentProfile();
                  GetIt.I
                    ..registerSingleton<AuthCubit>(auth)
                    ..registerSingleton<ProfileCubit>(profileCubit);
                  final selected = (await local.getAccountById(
                    selectedAccountId,
                  ))!;
                  final other = (await local.getAccountById(
                    unrelatedAccountId,
                  ))!;
                  final cookieOwner = (await local.getAccountById(
                    cookieAccountId,
                  ))!;
                  await tester.pumpWidget(
                    MaterialApp(
                      theme: TenturaTheme.light(),
                      locale: Locale(language),
                      supportedLocales: L10n.supportedLocales,
                      localizationsDelegates: L10n.localizationsDelegates,
                      home: MultiBlocProvider(
                        providers: [
                          BlocProvider<AuthCubit>.value(value: auth),
                          BlocProvider<ProfileCubit>.value(value: profileCubit),
                        ],
                        child: UiEffectHandler(
                          effects: effects,
                          child: AuthRecoveryListener(
                            child: TenturaResponsiveScope(
                              child: Scaffold(
                                body: Column(
                                  children: [
                                    AccountListTile(
                                      key: const ValueKey(selectedAccountId),
                                      account: selected,
                                    ),
                                    AccountListTile(
                                      key: const ValueKey(unrelatedAccountId),
                                      account: other,
                                    ),
                                    AccountListTile(
                                      key: const ValueKey(cookieAccountId),
                                      account: cookieOwner,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  await tester.pump();
                  expect(tester.getSize(find.byType(Scaffold)), kPhoneSurface);
                  expect(find.text(selectedAccountName), findsOneWidget);
                  expect(tester.takeException(), isNull);

                  // Positive controls discriminate response-sensitive recovery
                  // from an implementation that rejects every saved-account tap.
                  // Both identities must actually pass through the parser and
                  // become current when the same tile and cookie agree.
                  for (final accountId in [
                    // Keep seed-only Alice unmarked until the mismatch tap.
                    if (credentials.hasSession)
                      selectedAccountId
                    else
                      cookieAccountId,
                    unrelatedAccountId,
                  ]) {
                    responseSubject = accountId;
                    final parsedBefore = remote.parsedSessionSubjects.length;
                    await tester.tap(find.byKey(ValueKey(accountId)));
                    await waitUntil(
                      'a matching cookie did not finish signing in',
                      () =>
                          remote.parsedSessionSubjects.length > parsedBefore &&
                          !auth.state.isLoading,
                    );
                    await tester.pump();
                    expect(responses.last['subject'], accountId);
                    expect(remote.parsedSessionSubjects.last, accountId);
                    final credentials = await transport.getAuthToken();
                    expect(credentials.userId, accountId);
                    expect(credentials.accessToken, 'token-$accountId');
                    expect(auth.state.currentAccountId, accountId);
                    expect(transport.realtimeAccountId, accountId);
                    expect(_instruction(language), findsNothing);
                  }
                  published.clear();

                  expect(
                    await local.isSessionAccount(selectedAccountId),
                    credentials.hasSession,
                  );
                  if (credentials.seed != null) {
                    expect(
                      await local.getSeedByAccountId(selectedAccountId),
                      selectedAccountSeed,
                    );
                  }

                  responseSubject = cookieAccountId;
                  holdMismatchResponse = true;
                  final probesBeforeTap = _cookieProbes(requests).length;
                  final seedSignInsBeforeTap = _seedSignIns(requests).length;
                  final parsedBeforeMismatch =
                      remote.parsedSessionSubjects.length;
                  await tester.tap(
                    find.byKey(const ValueKey(selectedAccountId)),
                  );
                  await waitUntil(
                    'the selected account never requested its cookie identity',
                    () => _cookieProbes(requests).length > probesBeforeTap,
                  );
                  await tester.pump();
                  expect(auth.state.isLoading, isTrue);
                  expect(
                    remote.parsedSessionSubjects.length,
                    parsedBeforeMismatch,
                  );
                  expect(_instruction(language), findsNothing);
                  releaseMismatch.complete();
                  for (var attempt = 0; attempt < 120; attempt++) {
                    await tester.pump(const Duration(milliseconds: 25));
                    if (remote.parsedSessionSubjects.length >
                            parsedBeforeMismatch &&
                        !auth.state.isLoading) {
                      break;
                    }
                    await Future<void>.delayed(const Duration(milliseconds: 5));
                  }
                  expect(
                    remote.parsedSessionSubjects.length,
                    greaterThan(parsedBeforeMismatch),
                  );
                  expect(auth.state.isLoading, isFalse);
                  await tester.pump();
                  await tester.pump(const Duration(milliseconds: 500));

                  expect(_cookieProbes(requests).last.method, 'POST');
                  expect(responses.last['subject'], cookieAccountId);
                  expect(
                    responses.last['access_token'],
                    'token-$cookieAccountId',
                  );
                  expect(
                    remote.parsedSessionSubjects.last,
                    cookieAccountId,
                    reason:
                        'the real repository must return Boris from the '
                        'HTTP response before the mismatch can drive recovery',
                  );
                  if (credentials.seed != null) {
                    expect(
                      published,
                      isNot(contains(selectedAccountId)),
                      reason:
                          'having a working seed does not authorize a '
                          'mismatched cookie to publish Alice as current',
                    );
                    expect(
                      auth.state.currentAccountId,
                      isNot(selectedAccountId),
                    );
                    expect(
                      await local.isSessionAccount(selectedAccountId),
                      isFalse,
                    );
                    expect(transport.hasValidToken, isFalse);
                    expect(transport.isSessionAuth, isFalse);
                    expect(transport.realtimeAccountId, isNull);
                    expect(
                      _seedSignIns(requests).length,
                      seedSignInsBeforeTap,
                      reason:
                          'a cookie mismatch requires explicit reauthentication '
                          'as Alice, rather than silently falling back to her seed',
                    );
                  }
                  final instruction = _instruction(language);
                  expect(
                    instruction,
                    findsOneWidget,
                    reason:
                        'the real cookie response names Boris; selecting '
                        'Alice must show "${selectedAccountSignInInstruction(language)}"',
                  );
                  final paragraph = tester.renderObject<RenderParagraph>(
                    instruction,
                  );
                  expect(paragraph.didExceedMaxLines, isFalse);
                  final bounds = tester.getRect(instruction);
                  expect(bounds.left, greaterThanOrEqualTo(0));
                  expect(bounds.top, greaterThanOrEqualTo(0));
                  expect(bounds.right, lessThanOrEqualTo(kPhoneSurface.width));
                  expect(
                    bounds.bottom,
                    lessThanOrEqualTo(kPhoneSurface.height),
                  );
                  expect(published, isNot(contains(selectedAccountId)));
                  expect(auth.state.currentAccountId, isNot(selectedAccountId));
                  expect(
                    await local.isSessionAccount(selectedAccountId),
                    isFalse,
                  );
                  expect(transport.hasValidToken, isFalse);
                  expect(transport.isSessionAuth, isFalse);
                  expect(transport.realtimeAccountId, isNull);
                  expect(tester.takeException(), isNull);
                } finally {
                  if (!releaseMismatch.isCompleted) releaseMismatch.complete();
                  await tester.pumpWidget(const SizedBox.shrink());
                  await tester.pump();
                  await states?.cancel();
                  await cubit?.dispose();
                  await transport.close();
                  await local.dispose();
                  await effects.close();
                }
              }, () => server),
            );
          },
        );
      }
    }
  });
}

List<http.Request> _seedSignIns(List<http.Request> requests) => requests
    .where(
      (request) =>
          request.url.path.endsWith('/graphql') &&
          (jsonDecode(request.body) as Map<String, dynamic>)['operationName'] ==
              'SignIn',
    )
    .toList();

Finder _instruction(String language) => find.byWidgetPredicate(
  (widget) =>
      widget is RichText &&
      namesSelectedAccountForSignIn(
        widget.text.toPlainText(),
        language,
      ),
);

List<http.Request> _cookieProbes(List<http.Request> requests) => requests
    .where((request) => request.url.path == '/api/v2/session/access-token')
    .toList();

final class _Effects implements UiEffectPort {
  final _controller = StreamController<UiEffect>.broadcast();

  @override
  Stream<UiEffect> get effects => _controller.stream;

  @override
  void emit(UiEffect effect) => _controller.add(effect);

  Future<void> close() => _controller.close();
}

final class _CurrentProfile extends Fake implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: unrelatedAccountId, displayName: 'Charlie'),
  );

  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

final class _UnusedRouter extends Mock implements RootRouter {}

final class _UnusedPlatform extends Fake implements PlatformRepositoryPort {}

final class _UnusedProfiles extends Fake implements ProfileRepositoryPort {
  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();
}
