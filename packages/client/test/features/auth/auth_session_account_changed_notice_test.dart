// Cookie refresh -> production transport/repository/use case/cubit ->
// UiEffectHandler -> localized snackbar -> controlled reload request.
// Document navigation itself requires the web integration runner; these tests
// stop at the platform port and require the notice to be visible before unload.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Mock;

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/entity/localizable.dart';
import 'package:tentura/env.dart';
import 'package:tentura/data/service/remote_api_client/realtime_transport_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/auth/data/repository/auth_remote_repository.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:http/http.dart' as http;

import '../../data/service/_session_account_test_harness.dart';
import '../../support/phone_surface.dart';
import 'auth_test_helpers.dart';

const _accountA = 'account-a';
const _accountB = 'account-b';
const _tokenA = 'token-account-a';
const _tokenB = 'token-account-b';

void _acceptAuth(FakeRealtimeSocket socket) {
  socket.addMessage(
    jsonEncode({'type': 'auth', 'intent': 'sign_in', 'result': 'success'}),
  );
}

void main() {
  setUp(() {
    GetIt.I
      ..registerSingleton<AppNavigator>(_UnusedNavigator())
      ..registerSingleton<Logger>(Logger('SessionAccountChangeTest'));
  });
  tearDown(GetIt.I.reset);

  test(
    'a socket account change emits its dedicated notice before requesting '
    'one reload of the replacement session',
    () => _withSignedInSession((session) async {
      // Bootstrap and an ordinary reconnect must not be mistaken for recovery.
      await session.reconnectWithOriginalCookie();
      session
        ..expectNoRecovery()
        ..swapCookieAndReconnect();
      await waitUntil(
        'The swapped-cookie rejection never reached AuthCubit as ShowError',
        () => session.errors.isNotEmpty,
      );
      expect(session.errors, hasLength(1));
      final error = session.errors.single.error;
      expect(error, isSessionAccountChangedNotice);

      await waitUntil(
        'AuthCubit did not request controlled reload for the account change',
        () => session.platform.reloads.isNotEmpty,
      );
      session.expectRecoveryFor(error);
    }),
  );

  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'the account change notice is visible through the app error handler '
      'before reload at 375x667 ${locale.languageCode.toUpperCase()}',
      (tester) async {
        await usePhoneSurface(tester);
        await tester.runAsync(
          () => _withSignedInSession((session) async {
            GetIt.I.registerSingleton<AuthCubit>(session.cubit);
            try {
              await tester.pumpWidget(
                MaterialApp(
                  theme: TenturaTheme.light(),
                  locale: locale,
                  supportedLocales: L10n.supportedLocales,
                  localizationsDelegates: L10n.localizationsDelegates,
                  home: BlocProvider<AuthCubit>.value(
                    value: session.cubit,
                    child: UiEffectHandler(
                      effects: session.effects,
                      child: const TenturaResponsiveScope(
                        child: Scaffold(body: SizedBox.expand()),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pump();
              expect(tester.getSize(find.byType(Scaffold)), kPhoneSurface);
              expect(find.byType(SnackBar), findsNothing);

              await session.reconnectWithOriginalCookie();
              session.expectNoRecovery();
              expect(find.byType(SnackBar), findsNothing);

              // Observe what is actually mounted when production asks to
              // unload. Emitting ShowError immediately before unloading,
              // without ever painting it, must not satisfy the notice promise.
              session.platform.noticeIsVisible = () =>
                  _noticeFinder(session, locale)?.evaluate().length == 1;
              session.swapCookieAndReconnect();
              await _pumpUntil(
                tester,
                () => _noticeFinder(session, locale)?.evaluate().length == 1,
              );

              expect(
                session.errors,
                hasLength(1),
                reason:
                    'the cookie rejection must reach the real UI effect path',
              );
              final error = session.errors.single.error;
              expect(error, isSessionAccountChangedNotice);
              final notice = error as Localizable;
              final expectedText = notice.toL10n(locale.languageCode);
              final message = _noticeFinder(session, locale)!;
              expect(message, findsOneWidget);
              final paragraph = tester.renderObject<RenderParagraph>(message);
              expect(paragraph.text.toPlainText(), expectedText);
              expect(paragraph.didExceedMaxLines, isFalse);

              final snackbar = find.byType(SnackBar);
              expect(
                find.descendant(
                  of: snackbar,
                  matching: find.text(lookupL10n(locale).copyErrorDetails),
                ),
                findsOneWidget,
              );
              final bounds = tester.getRect(message);
              expect(bounds.left, greaterThanOrEqualTo(0));
              expect(bounds.top, greaterThanOrEqualTo(0));
              expect(bounds.right, lessThanOrEqualTo(kPhoneSurface.width));
              expect(bounds.bottom, lessThanOrEqualTo(kPhoneSurface.height));
              expect(tester.takeException(), isNull);

              await _pumpUntil(
                tester,
                () => session.platform.reloads.isNotEmpty,
              );
              session.expectRecoveryFor(error);
              expect(
                session.platform.reloads.single.noticeWasVisible,
                isTrue,
                reason: 'reload must not discard the notice before it renders',
              );
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
            }
          }),
        );
      },
    );
  }
}

Finder? _noticeFinder(_SignedInSession session, Locale locale) {
  if (session.errors.length != 1) return null;
  final error = session.errors.single.error;
  if (error is! Localizable) return null;
  return find.descendant(
    of: find.byType(SnackBar),
    matching: find.text(error.toL10n(locale.languageCode), findRichText: true),
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 120 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await tester.pump(const Duration(milliseconds: 25));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _withSignedInSession(
  Future<void> Function(_SignedInSession session) body,
) async {
  final session = _SignedInSession();
  await http.runWithClient(() async {
    try {
      await session.start();
      await body(session);
    } finally {
      await session.dispose();
    }
  }, () => session.server);
}

final class _SignedInSession {
  _SignedInSession() {
    server = fakeSessionServer(cookie, seen: requests);
    transport = testRealtimeClient(socketFactory: sockets);
    platform = _RecordingPlatformCleanup(effects);
  }

  final cookie = FakeSessionCookie(subject: _accountA, token: _tokenA);
  final sockets = FakeRealtimeSocketFactory();
  final requests = <http.Request>[];
  final effects = _RecordingEffects();
  late final http.Client server;
  late final RemoteApiService transport;
  late final _RecordingPlatformCleanup platform;
  AuthCubit? _cubit;
  StreamSubscription<RealtimeTransportStatus>? _statusSubscription;
  RealtimeTransportPhase? _phase;
  int _requestsBeforeSwap = 0;

  AuthCubit get cubit => _cubit!;
  List<ShowError> get errors => effects.emitted.whereType<ShowError>().toList();

  Future<void> start() async {
    _statusSubscription = transport.realtimeTransportStatus.listen(
      (status) => _phase = status.phase,
    );
    final remote = AuthRemoteRepository(
      remoteApiService: transport,
      log: Logger('SessionAccountChangeTest'),
    );
    final local = _SessionLocal();
    _cubit = await AuthCubit.hydrated(
      const Env(),
      AuthCase(
        local,
        remote,
        TestDevicePush(),
        platform,
        TestSettingsRepository(),
        env: const Env(),
        logger: Logger('test'),
      ),
      AccountCase(
        local,
        remote,
        _FakePlatform(),
        _FakeProfiles(),
        env: const Env(),
        logger: Logger('test'),
      ),
      _FakeProfiles(),
      effects,
    );
    expect(cubit.state.currentAccountId, _accountA);
    expect(cubit.state.isBootstrapping, isFalse);
    expect(transport.realtimeAccountId, _accountA);
    sockets.sockets.single.addConnection(
      RealtimeSocketConnectionState.connected,
    );
    await _acceptOriginalAccount();
    expectNoRecovery();
  }

  Future<void> _acceptOriginalAccount() async {
    final socket = sockets.sockets.single;
    await waitUntil(
      'original account auth frame missing',
      () => socket.sent.isNotEmpty,
    );
    expect(
      jsonDecode(socket.sent.single as String),
      containsPair('token', _tokenA),
    );
    _acceptAuth(socket);
    await waitUntil(
      'original account did not become authenticated',
      () => _phase == RealtimeTransportPhase.authenticated,
    );
  }

  Future<void> reconnectWithOriginalCookie() async {
    sockets.sockets.single
      ..sent.clear()
      ..addConnection(RealtimeSocketConnectionState.disconnected)
      ..addConnection(RealtimeSocketConnectionState.reconnected);
    await _acceptOriginalAccount();
  }

  void expectNoRecovery() {
    expect(cubit.state.currentAccountId, _accountA);
    expect(errors, isEmpty);
    expect(platform.reloads, isEmpty);
  }

  void swapCookieAndReconnect() {
    _requestsBeforeSwap = requests.length;
    cookie
      ..subject = _accountB
      ..token = _tokenB;
    sockets.sockets.single
      ..sent.clear()
      ..addConnection(RealtimeSocketConnectionState.disconnected)
      ..addConnection(RealtimeSocketConnectionState.reconnected);
  }

  void expectRecoveryFor(Object error) {
    expect(
      requests
          .skip(_requestsBeforeSwap)
          .where(
            (request) => request.url.path == '/api/v2/session/access-token',
          ),
      isNotEmpty,
      reason: 'reconnect must actually refresh from the swapped cookie',
    );
    expect(platform.reloads, hasLength(1));
    final reload = platform.reloads.single;
    expect(reload.notices, hasLength(1));
    expect(reload.notices.single, same(error));
    expect(reload.notices.single, isSessionAccountChangedNotice);
    expect(
      reload.clearAcknowledged,
      isTrue,
      reason:
          'the valid replacement session must be allowed to bootstrap on reload',
    );
    for (final request in requests.skip(_requestsBeforeSwap)) {
      expect(request.headers['Authorization'], isNot('Bearer $_tokenB'));
      expect(request.url.toString(), isNot(contains(_tokenB)));
      expect(request.body, isNot(contains(_tokenB)));
    }
    for (final socket in sockets.sockets) {
      for (final frame in socket.sent) {
        expect(frame.toString(), isNot(contains(_tokenB)));
      }
    }
  }

  Future<void> dispose() async {
    await _cubit?.dispose();
    await _statusSubscription?.cancel();
    await transport.close();
    await effects.close();
  }
}

final class _RecordingEffects implements UiEffectPort {
  final emitted = <UiEffect>[];
  final _controller = StreamController<UiEffect>.broadcast();

  @override
  Stream<UiEffect> get effects => _controller.stream;

  @override
  void emit(UiEffect effect) {
    emitted.add(effect);
    _controller.add(effect);
  }

  Future<void> close() => _controller.close();
}

typedef _ReloadObservation = ({
  bool clearAcknowledged,
  List<Object> notices,
  bool noticeWasVisible,
});

final class _RecordingPlatformCleanup extends TestAuthPlatformCleanup {
  _RecordingPlatformCleanup(this.effects);

  final _RecordingEffects effects;
  final reloads = <_ReloadObservation>[];
  bool Function()? noticeIsVisible;

  @override
  void reloadAfterRejectedSession({required bool clearAcknowledged}) {
    reloads.add((
      clearAcknowledged: clearAcknowledged,
      notices: effects.emitted
          .whereType<ShowError>()
          .map((e) => e.error)
          .toList(),
      noticeWasVisible: noticeIsVisible?.call() ?? false,
    ));
  }
}

final class _UnusedNavigator extends Mock implements AppNavigator {}

final class _SessionLocal implements AuthLocalRepositoryPort {
  String _current = _accountA;

  @override
  Stream<String> currentAccountChanges() => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getCurrentAccountId() async => _current;

  @override
  Future<String> getSeedByAccountId(String id) async => 'seed-$id';

  @override
  Future<List<AccountEntity>> getAccountsAll() async => <AccountEntity>[];

  @override
  Future<AccountEntity?> getAccountById(String id) async =>
      AccountEntity(id: id);

  @override
  Future<AccountEntity?> getCurrentAccount() async =>
      AccountEntity(id: _current);

  @override
  Future<void> removeAccount(String id) async {}

  @override
  Future<void> updateAccount(AccountEntity account) async {}

  @override
  Future<void> setCurrentAccountId(String? id) async => _current = id ?? '';

  @override
  Future<void> addAccount(
    String id,
    String seed, [
    String? displayName,
  ]) async {}

  @override
  Future<void> upsertAccountWithSeed(
    String id,
    String seed, [
    String? displayName,
  ]) async {}

  @override
  Future<void> storeLinkedSeedIfAbsent(String id, String seed) async {}

  @override
  Future<void> addSessionAccount(String id, [String? displayName]) async {}

  @override
  Future<bool> isSessionAccount(String id) async => true;

  @override
  Future<void> retainOnlyAccount(String keepId) async {}

  @override
  Future<void> clearAllAuthData() async {}
}

final class _FakePlatform extends Fake implements PlatformRepositoryPort {}

final class _FakeProfiles extends Fake implements ProfileRepositoryPort {
  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();
}
