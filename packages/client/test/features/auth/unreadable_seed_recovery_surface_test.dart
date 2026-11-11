// An account whose stored seed can no longer be decrypted (on web: WebCrypto
// rejects with a DOMException, which is not a Dart Exception) stays listed
// and is surfaced on the existing auth recovery surface. The client has no
// separate account-list widget: the account list is AuthState.accounts, and
// «needs sign-in again» is the existing recovery marker (authRecoveryNeeded,
// shown on the Recover screen as the session-problem text):
//   * linked to email/Google (session account): the marker plus «Sign in
//     again», which opens the existing sign-in screen;
//   * seed-only: a clear localized message that the recovery seed is needed
//     (ARB key `authSeedUnreadableBody`, EN + RU), readable on a 375×667
//     phone in Russian.
// The cubit boots over the real AuthLocalRepository and LocalSecureStorage;
// only the secure-storage backend and the server are faked.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/database/database.dart' hide isNotNull, isNull;
import 'package:tentura/data/service/local_secure_storage.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_local_repository.dart';
import 'package:tentura/features/auth/domain/entity/auth_recovery_outcome.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/auth/ui/widget/auth_recovery_listener.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../support/phone_surface.dart';
import 'auth_test_helpers.dart';

const _accountId = 'U7f3c9a1b2d4e';
const _accountKey = 'Auth:Id:$_accountId';
const _sessionMarkerKey = 'Auth:Session:$_accountId';
const _currentAccountKey = 'Auth:currentAccountId';
const _ciphertext = 'q1w2e3r4t5y6u7i8o9p0aa==.ZmFrZS1jaXBoZXJ0ZXh0';

/// Name of the seed-only message in the ARB files.
const _seedOnlyMessageKey = 'authSeedUnreadableBody';

/// Raw secure-storage contents; reading a key in [undecryptable] throws an
/// object that is not a Dart Exception. Writes and deletes are recorded.
final class _UndecryptableBackend extends MapBase<String, String> {
  _UndecryptableBackend(Map<String, String> raw, this.undecryptable)
    : raw = Map.of(raw);

  final Map<String, String> raw;
  final Set<String> undecryptable;
  final changed = <String>[];

  @override
  String? operator [](Object? key) {
    if (undecryptable.contains(key)) {
      // A JS DOMException is not a Dart Exception/Error; neither is a String.
      // ignore: only_throw_errors
      throw 'OperationError: stand-in for a WebCrypto DOMException';
    }
    return raw[key];
  }

  @override
  void operator []=(String key, String value) {
    changed.add('write $key');
    raw[key] = value;
  }

  @override
  void clear() {
    changed.add('clear');
    raw.clear();
  }

  @override
  Iterable<String> get keys => raw.keys;

  @override
  String? remove(Object? key) {
    changed.add('delete $key');
    return raw.remove(key);
  }
}

String _arbMessage(String locale) {
  final arb =
      jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
          as Map<String, dynamic>;
  final value = arb[_seedOnlyMessageKey];
  expect(
    value,
    isA<String>().having((s) => s.trim(), 'text', isNotEmpty),
    reason:
        'l10n/app_$locale.arb needs "$_seedOnlyMessageKey": the message for '
        'a seed-only account whose seed cannot be read',
  );
  return value as String;
}

String? _arbMessageOrNull(String locale) {
  final arb =
      jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
          as Map<String, dynamic>;
  return arb[_seedOnlyMessageKey] as String?;
}

final class _Boot {
  _Boot(this.backend, this.remote, this.cubit);

  final _UndecryptableBackend backend;
  final EmptyAuthRemote remote;
  final AuthCubit cubit;
}

/// Boots [AuthCubit] the way the app does, over the real local repository,
/// with the account's seed undecryptable and no valid session cookie.
Future<_Boot> _boot(WidgetTester tester, {required bool linked}) async {
  final backend = _UndecryptableBackend(
    {
      _accountKey: _ciphertext,
      _currentAccountKey: _accountId,
      if (linked) _sessionMarkerKey: '1',
    },
    {_accountKey},
  );
  FlutterSecureStorage.setMockInitialValues(backend);
  final remote = EmptyAuthRemote(sessionRejected: true);
  final cubit = await tester.runAsync(() async {
    final database = Database(
      const Env(),
      Logger('unreadable-seed-surface'),
      NativeDatabase.memory(),
    );
    addTearDown(database.close);
    await database.managers.accounts.create((o) => o(id: _accountId));
    final local = AuthLocalRepository(
      Logger('unreadable-seed-surface'),
      database,
      LocalSecureStorage(),
    );
    return AuthCubit.hydrated(
      const Env(),
      AuthCase(
        local,
        remote,
        TestDevicePush(),
        _NativeSignInCleanup(),
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
      _FakeEffects(),
    );
  });
  addTearDown(cubit!.close);
  return _Boot(backend, remote, cubit);
}

class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: RecoverRoute.page, initial: true),
  ];
}

Future<void> _pumpRecover(
  WidgetTester tester,
  AuthCubit cubit,
  Locale locale, {
  bool withRecoveryListener = false,
}) async {
  final router = _TestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    BlocProvider<AuthCubit>.value(
      value: cubit,
      child: MaterialApp.router(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) {
          final page = child ?? const SizedBox.shrink();
          return TenturaResponsiveScope(
            child: withRecoveryListener
                ? AuthRecoveryListener(child: page)
                : page,
          );
        },
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('Seed-only account whose seed cannot be decrypted', () {
    testWidgets('stays listed and the Recover screen says, in Russian on a '
        '375×667 phone, that the recovery seed is needed', (tester) async {
      final ru = _arbMessage('ru');
      await usePhoneSurface(tester);
      final boot = await _boot(tester, linked: false);

      expect(boot.cubit.state.accounts.map((a) => a.id), contains(_accountId));
      expect(boot.cubit.state.authRecoveryNeeded, isTrue);

      await _pumpRecover(tester, boot.cubit, const Locale('ru'));

      expect(find.text(ru, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow at 375×667');
      expect(boot.backend.changed, isEmpty, reason: 'the seed is kept');
      expect(boot.backend.raw[_accountKey], _ciphertext);
    });

    testWidgets('the English Recover screen shows the English message', (
      tester,
    ) async {
      final en = _arbMessage('en');
      final boot = await _boot(tester, linked: false);

      await _pumpRecover(tester, boot.cubit, const Locale('en'));

      expect(find.text(en, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Email/Google-linked account whose seed cannot be decrypted', () {
    testWidgets('stays in the account list marked as needing sign-in again, '
        'and the Recover screen shows that marker instead of the seed '
        'message', (tester) async {
      final en = lookupL10n(const Locale('en'));
      final boot = await _boot(tester, linked: true);

      expect(
        boot.cubit.state.accounts.map((a) => a.id),
        contains(_accountId),
        reason: 'the account list keeps the account',
      );
      expect(
        boot.cubit.state.authRecoveryNeeded,
        isTrue,
        reason: 'the account is marked as needing sign-in again',
      );

      await _pumpRecover(tester, boot.cubit, const Locale('en'));

      expect(
        find.text(en.authSessionProblemBanner, skipOffstage: false),
        findsOneWidget,
        reason: 'the «needs sign-in again» marker is shown',
      );
      expect(
        find.widgetWithText(FilledButton, en.authRecoverySignInAgain),
        findsOneWidget,
      );
      final seedOnlyMessage = _arbMessageOrNull('en');
      if (seedOnlyMessage != null) {
        expect(
          find.text(seedOnlyMessage, skipOffstage: false),
          findsNothing,
          reason: 'a linked account signs in with email/Google, not the seed',
        );
      }
      expect(tester.takeException(), isNull);
      expect(boot.backend.changed, isEmpty, reason: 'the seed is kept');
    });

    testWidgets('choosing «Sign in again» opens the sign-in screen and '
        'keeps the undecryptable seed', (tester) async {
      final en = lookupL10n(const Locale('en'));
      final navigator = _RecordingNavigator();
      GetIt.I.registerSingleton<AppNavigator>(navigator);
      addTearDown(() => GetIt.I.unregister<AppNavigator>());
      final boot = await _boot(tester, linked: true);

      await _pumpRecover(
        tester,
        boot.cubit,
        const Locale('en'),
        withRecoveryListener: true,
      );
      final signInAgain = find.widgetWithText(
        FilledButton,
        en.authRecoverySignInAgain,
      );
      expect(signInAgain, findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(signInAgain);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump();

      expect(
        navigator.destinations,
        contains('sign-in'),
        reason: 'choosing the account opens the existing sign-in path',
      );
      expect(boot.cubit.state.isNotAuthenticated, isTrue);
      expect(tester.takeException(), isNull);
      expect(boot.backend.raw[_accountKey], _ciphertext);
      expect(
        boot.backend.changed,
        isNot(contains('write $_accountKey')),
        reason: 'the undecryptable seed is never overwritten',
      );
      expect(boot.backend.changed, isNot(contains('delete $_accountKey')));
    });
  });
}

/// Records where the app navigates; the sign-in screen is `sign-in`.
final class _RecordingNavigator extends Fake implements AppNavigator {
  final destinations = <String>[];

  @override
  Future<void> resetToLogin() async => destinations.add('sign-in');

  @override
  Future<void> openRecover() async => destinations.add('recover');

  @override
  Future<void> resetToRecover() async => destinations.add('recover');

  @override
  void back() => destinations.add('back');
}

/// Production native platform: «Sign in again» lands on the sign-in screen.
final class _NativeSignInCleanup extends TestAuthPlatformCleanup {
  @override
  AuthRecoveryNavigation get resetNavigationTarget =>
      AuthRecoveryNavigation.nativeLogin;
}

final class _FakePlatform extends Fake implements PlatformRepositoryPort {}

final class _FakeProfiles extends Fake implements ProfileRepositoryPort {
  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();
}

final class _FakeEffects extends Fake implements UiEffectPort {
  @override
  Stream<UiEffect> get effects => const Stream.empty();

  @override
  void emit(UiEffect effect) {}
}
