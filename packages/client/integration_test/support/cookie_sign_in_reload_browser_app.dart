// Test-only browser entrypoint. The browser test reloads this document with a
// different HttpOnly cookie, then taps the production saved-account tile.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake, Mock;
import 'package:web/web.dart' as web;

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/service/auth_platform_cleanup.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/auth/ui/widget/auth_recovery_listener.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../test/features/auth/auth_test_helpers.dart';
import '../../test/features/auth/cookie_sign_in_test_support.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
  final storage = web.window.sessionStorage;
  final documentId =
      int.parse(storage.getItem('cookieSignIn.document') ?? '0') + 1;
  storage.setItem('cookieSignIn.document', '$documentId');
  FlutterError.onError = (details) {
    storage.setItem('cookieSignIn.flutterError', details.toString());
    FlutterError.presentError(details);
  };

  final log = Logger('CookieSignInReloadBrowser');
  final transport = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
  );
  final remote = ObservedCookieSignInRemote(
    remoteApiService: transport,
    log: log,
  );
  final local = _StoredAccounts();
  final profiles = _UnusedProfiles();
  final effects = UiEffectBus();
  final authCase = AuthCase(
    local,
    remote,
    TestDevicePush(),
    AuthPlatformCleanup(),
    TestSettingsRepository(),
    env: const Env(),
    logger: log,
  );
  final cubit = await AuthCubit.hydrated(
    const Env(),
    authCase,
    AccountCase(
      local,
      remote,
      _UnusedPlatform(),
      profiles,
      env: const Env(),
      logger: log,
    ),
    profiles,
    effects,
  );
  final selected = (await local.getAccountById(selectedAccountId))!;
  final published = <String>[];
  cubit.stream.listen((state) => published.add(state.currentAccountId));
  final profileCubit = _UnrelatedProfile();
  GetIt.I
    ..registerSingleton<Logger>(log)
    ..registerSingleton<RootRouter>(_UnusedRouter())
    ..registerSingleton<AuthCubit>(cubit)
    ..registerSingleton<ProfileCubit>(profileCubit);

  globalContext['cookieSignInState'] = (() => jsonEncode({
    'document': documentId,
    'account': cubit.state.currentAccountId,
    'storedAccount': storage.getItem('cookieSignIn.current'),
    'boundAccount': transport.realtimeAccountId,
    'isLoading': cubit.state.isLoading,
    'hasValidToken': transport.hasValidToken,
    'isSessionAuth': transport.isSessionAuth,
    'parsedSubjects': remote.parsedSessionSubjects,
    'published': published,
  }).toJS).toJS;

  runApp(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('en'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<AuthCubit>.value(value: cubit),
          BlocProvider<ProfileCubit>.value(value: profileCubit),
        ],
        child: UiEffectHandler(
          effects: effects,
          child: AuthRecoveryListener(
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Column(
                  children: [
                    BlocBuilder<AuthCubit, AuthState>(
                      builder: (context, state) =>
                          Text('Current account: ${state.currentAccountId}'),
                    ),
                    Semantics(
                      identifier: 'select-saved-alice',
                      child: ListTile(
                        title: Text(selected.displayName),
                        onTap: () async {
                          try {
                            await authCase.signIn(userId: selectedAccountId);
                          } catch (error) {
                            effects.emit(ShowError(error));
                          }
                        },
                      ),
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
}

/// Preserve the same account pointer across new documents. Only AuthCase
/// writes it; the browser test never changes Flutter's stored account state.
final class _StoredAccounts extends CookieSignInLocal {
  _StoredAccounts()
    : super(
        currentAccountId:
            web.window.sessionStorage.getItem('cookieSignIn.current') ?? '',
      );

  @override
  Future<void> setCurrentAccountId(String? id) async {
    await super.setCurrentAccountId(id);
    web.window.sessionStorage.setItem('cookieSignIn.current', id ?? '');
  }
}

final class _UnrelatedProfile extends Fake implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

final class _UnusedRouter extends Mock implements RootRouter {}

final class _UnusedPlatform extends Fake implements PlatformRepositoryPort {}

final class _UnusedProfiles extends Fake implements ProfileRepositoryPort {
  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();
}
