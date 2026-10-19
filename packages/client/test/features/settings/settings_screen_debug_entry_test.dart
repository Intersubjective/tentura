import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/notification/domain/port/direct_notification_probe_port.dart';
import 'package:tentura/features/notification/domain/use_case/fcm_case.dart';
import 'package:tentura/features/notification/ui/bloc/fcm_cubit.dart';
import 'package:tentura/features/settings/domain/entity/email_test_send_result.dart';
import 'package:tentura/features/settings/domain/port/email_test_remote_repository_port.dart';
import 'package:tentura/features/settings/ui/bloc/debug_settings_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../notification/fcm_case_test.dart';
import 'bookkeeping_refresh_test_support.dart';
import 'noisy_wall_screen_support.dart';
import 'settings_reset_counters_support.dart';

// Issue #469: Debug is not in the main Settings list. It is revealed by a
// long press on the app version line (product decision 2026-10-19), and the
// Debug page opens without a generic error bar when this browser has no FCM
// token; the missing token is shown inline in red.

const _version = 'Tentura 9.9.9 (test)';

class _FakeAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime(2026), currentAccountId: 'U1');

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state =>
      const SettingsState(visibleVersion: _version, introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();

  @override
  Future<String?> tryGetCurrentAccountSeed() async => null;
}

/// A browser where Firebase cannot mint a token (permission not granted,
/// no push service in headless Chromium): `getToken` throws a non
/// "unsupported-browser" error, which the web service rethrows.
class _NoTokenFcmLocal extends FakeFcmLocal {
  @override
  Future<String?> getToken() async {
    getTokenCalls++;
    throw Exception(
      'FirebaseError: Messaging: The notification permission was not '
      'granted and blocked instead. (messaging/permission-blocked).',
    );
  }
}

final class _Preferences implements HomeOrientationPreferencesPort {
  @override
  Future<bool> isActivated({required String userId}) async => false;

  @override
  Future<void> setActivated({required String userId}) async {}

  @override
  Future<bool> isOrientationDismissed({required String userId}) async => false;

  @override
  Future<void> setOrientationDismissed({required String userId}) async {}

  @override
  Future<void> resetFirstRunState({required String userId}) async {}

  @override
  Future<OrientationDebugOverride> getDebugOverride() async =>
      OrientationDebugOverride.auto;

  @override
  Future<void> setDebugOverride(OrientationDebugOverride value) async {}
}

class _EmailRepo implements EmailTestRemoteRepositoryPort {
  @override
  Future<EmailTestSendResult> sendTestEmail() async =>
      const EmailTestSendResult(ok: true, mock: false);
}

final class _Probe implements DirectNotificationProbePort {
  @override
  Future<void> show() async {}
}

Future<L10n> _pumpSettings(
  WidgetTester tester, {
  required FakeUiEffectPort effects,
}) async {
  final getIt = GetIt.I;
  final authCubit = _FakeAuthCubit();
  final settingsCubit = _FakeSettingsCubit();
  getIt
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<AuthCubit>(authCubit)
    ..registerSingleton<SettingsCubit>(settingsCubit);
  addTearDown(registerReconcilePortForScreenTest());
  addTearDown(registerNoisyWallForScreenTest());

  final router = RootRouter(
    Logger('test'),
    authCubit,
    settingsCubit,
    PostJoinNavigationCubit(),
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) =>
          TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
      routerConfig: router.config(
        deepLinkBuilder: (_) => const DeepLink.path(kPathSettings),
        includePrefixMatches: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return lookupL10n(const Locale('en'));
}

void main() {
  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('Debug is not listed in Settings by default', (tester) async {
    final l10n = await _pumpSettings(tester, effects: FakeUiEffectPort());

    // Preconditions: the screen and the version line really rendered.
    expect(find.text(l10n.labelSettings), findsOneWidget);
    expect(find.text(_version), findsOneWidget);
    expect(find.text(l10n.attentionResetCounters), findsOneWidget);
    expect(find.text(l10n.settingsRoutingMute), findsOneWidget);

    expect(find.text(l10n.settingsDebug), findsNothing);
    expect(find.byIcon(Icons.bug_report_outlined), findsNothing);
  });

  testWidgets('only a long press on the version line reveals Debug', (
    tester,
  ) async {
    final l10n = await _pumpSettings(tester, effects: FakeUiEffectPort());

    // A plain tap on the version is not the gesture.
    await tester.tap(find.text(_version));
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsDebug), findsNothing);

    await tester.ensureVisible(find.text(_version));
    await tester.longPress(find.text(_version));
    await tester.pumpAndSettle();

    final debugTile = find.widgetWithText(TenturaMenuTile, l10n.settingsDebug);
    expect(debugTile, findsOneWidget);
    expect(tester.widget<TenturaMenuTile>(debugTile).onTap, isNotNull);
    // Nothing else in Settings changed.
    expect(find.text(l10n.attentionResetCounters), findsOneWidget);
    expect(find.text(l10n.settingsRoutingMute), findsOneWidget);
    expect(find.text(_version), findsOneWidget);
  });

  testWidgets(
    'revealed Debug opens without an error bar and shows the missing FCM '
    'token in red',
    (tester) async {
      final effects = FakeUiEffectPort();
      final fcmLocal = _NoTokenFcmLocal();
      final fcmCase = FcmCase(fcmLocal, FakeFcmRemote(), FakeSettings());
      final authCase = buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote());
      final fcmCubit = FcmCubit(fcmCase, authCase);
      addTearDown(fcmCubit.close);
      final homeActivation = HomeActivationCubit(_Preferences());
      addTearDown(homeActivation.close);
      GetIt.I
        ..registerSingleton<HomeActivationCubit>(homeActivation)
        ..registerFactory<DebugSettingsCubit>(
          () => DebugSettingsCubit(
            fcmCase,
            authCase,
            fcmCubit,
            _EmailRepo(),
            buildTestBookkeepingRefreshCase(),
            _Probe(),
            effects,
          ),
        );

      final l10n = await _pumpSettings(tester, effects: effects);
      await tester.ensureVisible(find.text(_version));
      await tester.longPress(find.text(_version));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.settingsDebug));
      await tester.tap(find.text(l10n.settingsDebug));
      await tester.pumpAndSettle();

      // We are on the Debug page and it asked the platform for a token.
      expect(find.text(l10n.settingsFcmRegistration), findsOneWidget);
      expect(fcmLocal.getTokenCalls, greaterThan(0));

      // No generic "Something went wrong" bar for a missing token.
      expect(effects.emitted.whereType<ShowError>(), isEmpty);

      // The missing token is an inline error, in the danger tone.
      final unavailable = find.widgetWithText(
        TenturaStatusText,
        l10n.settingsFcmTokenUnavailable,
      );
      expect(unavailable, findsOneWidget);
      expect(
        tester.widget<TenturaStatusText>(unavailable).tone,
        TenturaTone.danger,
      );
      // The rest of the page still reads the real state.
      expect(find.text(l10n.settingsFcmPermissionGranted), findsOneWidget);
    },
  );
}
