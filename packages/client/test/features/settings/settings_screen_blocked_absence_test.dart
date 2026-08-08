import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _FakeAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime(2026), currentAccountId: 'U1');

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(visibleVersion: 'test');

  @override
  Stream<SettingsState> get stream => const Stream.empty();

  @override
  Future<String?> tryGetCurrentAccountSeed() async => null;
}

void main() {
  testWidgets('Settings does not expose blocked users action', (tester) async {
    final getIt = GetIt.I;
    final authCubit = _FakeAuthCubit();
    final settingsCubit = _FakeSettingsCubit();
    var registeredAuth = false;
    var registeredSettings = false;

    if (!getIt.isRegistered<AuthCubit>()) {
      getIt.registerSingleton<AuthCubit>(authCubit);
      registeredAuth = true;
    }
    if (!getIt.isRegistered<SettingsCubit>()) {
      getIt.registerSingleton<SettingsCubit>(settingsCubit);
      registeredSettings = true;
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

    expect(find.text(l10n.labelSettings), findsOneWidget);
    expect(find.text(l10n.blockedUsersTitle), findsNothing);
    expect(find.byIcon(Icons.block_outlined), findsNothing);
  });
}
