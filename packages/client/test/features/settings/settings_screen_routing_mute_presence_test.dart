import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

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
      const SettingsState(visibleVersion: 'test', introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();

  @override
  Future<String?> tryGetCurrentAccountSeed() async => null;
}

class _FakeCapabilityRepository implements CapabilityRepositoryPort {
  @override
  Future<List<String>> fetchMyRoutingTags() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Settings exposes routing mute entry and navigates to screen', (
    tester,
  ) async {
    final getIt = GetIt.I;
    final authCubit = _FakeAuthCubit();
    final settingsCubit = _FakeSettingsCubit();
    var registeredAuth = false;
    var registeredSettings = false;
    var registeredCapability = false;
    var registeredEffects = false;

    if (!getIt.isRegistered<AuthCubit>()) {
      getIt.registerSingleton<AuthCubit>(authCubit);
      registeredAuth = true;
    }
    if (!getIt.isRegistered<SettingsCubit>()) {
      getIt.registerSingleton<SettingsCubit>(settingsCubit);
      registeredSettings = true;
    }
    if (!getIt.isRegistered<CapabilityRepositoryPort>()) {
      getIt.registerSingleton<CapabilityRepositoryPort>(
        _FakeCapabilityRepository(),
      );
      registeredCapability = true;
    }
    if (!getIt.isRegistered<UiEffectPort>()) {
      getIt.registerSingleton<UiEffectPort>(FakeUiEffectPort());
      registeredEffects = true;
    }

    final router = RootRouter(
      Logger('test'),
      authCubit,
      settingsCubit,
      PostJoinNavigationCubit(),
    );
    addTearDown(() {
      router.dispose();
      if (registeredAuth && getIt.isRegistered<AuthCubit>()) {
        getIt.unregister<AuthCubit>();
      }
      if (registeredSettings && getIt.isRegistered<SettingsCubit>()) {
        getIt.unregister<SettingsCubit>();
      }
      if (registeredCapability && getIt.isRegistered<CapabilityRepositoryPort>()) {
        getIt.unregister<CapabilityRepositoryPort>();
      }
      if (registeredEffects && getIt.isRegistered<UiEffectPort>()) {
        getIt.unregister<UiEffectPort>();
      }
    });

    final l10n = lookupL10n(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) =>
            TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink.path(kPathSettings),
          includePrefixMatches: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.settingsRoutingMute), findsOneWidget);
    expect(find.byIcon(Icons.alt_route_outlined), findsOneWidget);

    await tester.tap(find.text(l10n.settingsRoutingMute));
    await tester.pumpAndSettle();

    expect(find.text(l10n.routingMuteScreenTitle), findsOneWidget);
  });
}
