import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
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
  _FakeCapabilityRepository({this.mutedSlugs = const []});

  List<String> mutedSlugs;
  String? lastMuteSlug;
  bool? lastMuteValue;
  int setMuteCalls = 0;

  @override
  Future<List<String>> fetchMyRoutingTags() async =>
      List<String>.from(mutedSlugs);

  @override
  Future<void> setRoutingMute({
    required String slug,
    required bool muted,
  }) async {
    setMuteCalls++;
    lastMuteSlug = slug;
    lastMuteValue = muted;
    if (muted) {
      if (!mutedSlugs.contains(slug)) {
        mutedSlugs = [...mutedSlugs, slug];
      }
    } else {
      mutedSlugs = mutedSlugs.where((s) => s != slug).toList();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeCapabilityRepository> _pumpRoutingMuteScreen(
  WidgetTester tester, {
  List<String> mutedSlugs = const [],
}) async {
  final getIt = GetIt.I;
  final authCubit = _FakeAuthCubit();
  final settingsCubit = _FakeSettingsCubit();
  final repository = _FakeCapabilityRepository(mutedSlugs: mutedSlugs);
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
    getIt.registerSingleton<CapabilityRepositoryPort>(repository);
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

  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp.router(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) =>
          TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
      routerConfig: router.config(
        deepLinkBuilder: (_) => DeepLink.path(kPathRoutingMute),
        includePrefixMatches: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Finder _transportSwitch(L10n l10n) =>
    find.widgetWithText(SwitchListTile, l10n.capabilityTagTransport);

void main() {
  final l10n = lookupL10n(const Locale('en'));

  testWidgets('renders all 37 capability mute toggles with an empty muted set', (
    tester,
  ) async {
    await _pumpRoutingMuteScreen(tester);

    expect(find.text(l10n.routingMuteScreenTitle), findsOneWidget);
    expect(find.text(l10n.routingMuteScreenDescription), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(CapabilityTag.values.length));
    final tiles = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(tiles.every((tile) => tile.value), isTrue);
  });

  testWidgets('muted transport switch is off and the rest stay on', (
    tester,
  ) async {
    await _pumpRoutingMuteScreen(tester, mutedSlugs: ['transport']);

    expect(
      tester.widget<SwitchListTile>(_transportSwitch(l10n)).value,
      isFalse,
    );
    final tiles = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(tiles.where((tile) => tile.value).length, CapabilityTag.values.length - 1);
  });

  testWidgets('turning transport off persists a mute', (tester) async {
    final repo = await _pumpRoutingMuteScreen(tester);

    await tester.tap(_transportSwitch(l10n));
    await tester.pumpAndSettle();

    expect(repo.setMuteCalls, 1);
    expect(repo.lastMuteSlug, 'transport');
    expect(repo.lastMuteValue, isTrue);
    expect(
      tester.widget<SwitchListTile>(_transportSwitch(l10n)).value,
      isFalse,
    );
  });
}
