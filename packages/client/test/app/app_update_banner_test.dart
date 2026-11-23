@Tags(['repo-files'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/app.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/app_update_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/bloc/app_update_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/realtime_status_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../support/phone_surface.dart';
import '../support/test_realtime_sync.dart';

const _installedVersion = '7.64.7';
const _accountId = 'Uviewer000001';

void main() {
  testWidgets(
    'an installed client below the announced floor sees the update banner',
    (
      tester,
    ) async {
      // The server's PostgreSQL-backed websocket test verifies that the deployed
      // default is sent in this frame. Use that default as wire input here.
      final serverEnv = File('../server/lib/env.dart').readAsStringSync();
      final floor = RegExp(
        "const kDefaultMinClientVersion = '([^']+)';",
      ).firstMatch(serverEnv)!.group(1)!;

      final socket = _PongSocket();
      final remote = RemoteApiService(const Env(), socket);
      final update = AppUpdateCubit(
        appUpdateRepository: AppUpdateRepository(remote),
        platformRepository: _InstalledPlatform(),
      );
      final sync = buildTestRealtimeSync();
      final realtime = RealtimeStatusCubit.forTesting(
        sync.case_,
        pausedDelay: Duration.zero,
      );
      final effects = UiEffectBus();
      final screen = ScreenCubit(effects);
      final auth = _SignedInAuth();
      final settings = _AppSettings();
      final postJoin = PostJoinNavigationCubit();
      final router = _AppRouter(auth, settings, postJoin);
      addTearDown(() async {
        await update.dispose();
        await remote.close();
        await realtime.close();
        await sync.port.dispose();
        await screen.close();
      });
      GetIt.I.pushNewScope(
        init: (getIt) {
          getIt
            ..registerSingleton<RootRouter>(router)
            ..registerSingleton<AuthCubit>(auth)
            ..registerSingleton<SettingsCubit>(settings)
            ..registerSingleton<ProfileCubit>(_UnusedProfile())
            ..registerSingleton<PresenceCubit>(_UnusedPresence())
            ..registerSingleton<ScreenCubit>(screen)
            ..registerSingleton<UiEffectPort>(effects)
            ..registerSingleton<AppUpdateCubit>(update)
            ..registerSingleton<RealtimeStatusCubit>(realtime);
        },
      );
      try {
        await usePhoneSurface(tester);
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();
        expect(find.text('Signed-in page'), findsOneWidget);

        await remote.bindRealtimeAccount(_accountId);
        socket.pong(_installedVersion);
        await tester.pumpAndSettle();
        expect(find.byType(MaterialBanner), findsNothing);

        socket.pong(floor);
        await tester.pumpAndSettle();
        expect(
          find.text('A new version is available. Please update the app.'),
          findsOneWidget,
          reason:
              'Client $_installedVersion received min_client_version $floor.',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await GetIt.I.popScope();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

class _PongSocket implements RealtimeSocket, RealtimeSocketFactory {
  final _incoming = StreamController<String>.broadcast();
  final _connection =
      StreamController<RealtimeSocketConnectionState>.broadcast();

  @override
  RealtimeSocket create(Uri uri) => this;

  @override
  Stream<RealtimeSocketConnectionState> get connection => _connection.stream;

  @override
  Stream<String> get messages => _incoming.stream;

  void receive(Map<String, String> frame) => _incoming.add(jsonEncode(frame));

  void pong(String floor) =>
      receive({'type': 'pong', 'min_client_version': floor});

  @override
  void send(Object message) {}

  @override
  Future<void> close() async {
    await _incoming.close();
    await _connection.close();
  }
}

class _InstalledPlatform extends Fake implements PlatformRepositoryPort {
  @override
  Future<String> getAppVersion() async => _installedVersion;
}

class _SignedInAuth extends Fake implements AuthCubit {
  @override
  final state = AuthState(
    updatedAt: DateTime.utc(2026),
    currentAccountId: _accountId,
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _AppSettings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(localePreference: 'ru');

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

class _UnusedProfile extends Fake implements ProfileCubit {}

class _UnusedPresence extends Fake implements PresenceCubit {}

class _AppRouter extends RootRouter {
  _AppRouter(
    AuthCubit auth,
    SettingsCubit settings,
    PostJoinNavigationCubit postJoin,
  ) : super(Logger('AppUpdateBannerTest'), auth, settings, postJoin);

  @override
  List<AutoRoute> get routes => [
    NamedRouteDef(
      name: 'SignedInPage',
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('Signed-in page')),
    ),
  ];
}
