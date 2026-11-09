// Browser fixture for scripts/e2e_session_account/run.sh. Only unrelated local
// storage/profile dependencies are doubled: cookie fetch, Ferry, WebSocket,
// AuthCubit, snackbar dispatch and document navigation use production code.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/data/service/auth_platform_cleanup.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_remote_repository.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../test/features/auth/auth_test_helpers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep browser semantics enabled for the lifetime of this document.
  WidgetsBinding.instance.ensureSemantics();
  FlutterError.onError = (details) {
    web.window.sessionStorage.setItem(
      'sessionAccount.flutterError',
      details.toString(),
    );
    FlutterError.presentError(details);
  };
  final storage = web.window.sessionStorage;
  final locale = Locale(
    Uri.base.queryParameters['locale'] ??
        storage.getItem('sessionAccount.locale') ??
        'en',
  );
  storage.setItem('sessionAccount.locale', locale.languageCode);

  final log = Logger('SessionAccountBrowser');
  final transport = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
  );
  var phase = '';
  transport.realtimeTransportStatus.listen(
    (status) => phase = status.phase.name,
  );
  final remote = AuthRemoteRepository(remoteApiService: transport, log: log);
  final local = _SessionLocal();
  final effects = UiEffectBus();
  effects.effects.listen((effect) {
    if (effect case ShowError(:final error)) {
      final count = int.parse(
        storage.getItem('sessionAccount.noticeCount') ?? '0',
      );
      storage
        ..setItem('sessionAccount.noticeCount', '${count + 1}')
        ..setItem(
          'sessionAccount.notice',
          error is AuthSessionAccountChangedException
              ? 'accountChanged'
              : '$error',
        );
    }
  });
  final cubit = await AuthCubit.hydrated(
    const Env(),
    AuthCase(
      local,
      remote,
      TestDevicePush(),
      AuthPlatformCleanup(),
      TestSettingsRepository(),
      env: const Env(),
      logger: log,
    ),
    AccountCase(
      local,
      remote,
      _UnusedPlatform(),
      _UnusedProfiles(),
      env: const Env(),
      logger: log,
    ),
    _UnusedProfiles(),
    effects,
  );
  GetIt.I
    ..registerSingleton<Logger>(log)
    ..registerSingleton<AppNavigator>(_UnusedNavigator())
    ..registerSingleton<AuthCubit>(cubit);
  runApp(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: BlocProvider<AuthCubit>.value(
        value: cubit,
        child: UiEffectHandler(
          effects: effects,
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: Center(
                child: Text('Account ${cubit.state.currentAccountId}'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  globalContext['sessionAccountState'] = (() => jsonEncode({
    'account': cubit.state.currentAccountId,
    'boundAccount': transport.realtimeAccountId,
    'phase': phase,
  }).toJS).toJS;
  globalContext['sessionAccountRead'] = (() => _read(
    transport,
    cubit,
  ).toJS).toJS;
}

Future<JSString> _read(RemoteApiService transport, AuthCubit cubit) async {
  try {
    final result = await MyWorkRepository(
      transport,
    ).fetchInit(userId: cubit.state.currentAccountId);
    return jsonEncode({'archivedCount': result.archivedCountHint}).toJS;
  } on AuthSessionAccountChangedException {
    return jsonEncode({'error': 'accountChanged'}).toJS;
  }
}

final class _SessionLocal extends EmptyAuthLocal {
  String _current = '';

  @override
  Future<String> getCurrentAccountId() async => _current;

  @override
  Future<void> setCurrentAccountId(String? id) async => _current = id ?? '';

  @override
  Future<AccountEntity?> getAccountById(String id) async =>
      AccountEntity(id: id);

  @override
  Future<bool> isSessionAccount(String id) async => true;
}

final class _UnusedNavigator extends Mock implements AppNavigator {}

final class _UnusedPlatform extends Mock implements PlatformRepositoryPort {}

final class _UnusedProfiles extends Mock implements ProfileRepositoryPort {
  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();
}
