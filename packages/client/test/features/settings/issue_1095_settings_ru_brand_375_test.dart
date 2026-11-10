// #1095: on the RU Settings screen at 375×667 no rendered text carries the
// Latin «Tentura»; the hint under the mute-people switch reads «Тентура».

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
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

import 'noisy_wall_screen_support.dart';
import 'settings_reset_counters_support.dart';

import '../../support/phone_surface.dart';
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

Iterable<String> _renderedTexts(WidgetTester tester) => tester
    .renderObjectList<RenderParagraph>(find.byType(RichText))
    .map((p) => p.text.toPlainText());

void main() {
  testWidgets('RU 375×667: Settings never shows Latin «Tentura»', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final getIt = GetIt.I;
    final authCubit = _FakeAuthCubit();
    final settingsCubit = _FakeSettingsCubit();
    final registered = <Future<void> Function()>[];
    void register<T extends Object>(T value) {
      if (getIt.isRegistered<T>()) return;
      getIt.registerSingleton<T>(value);
      registered.add(() async {
        if (getIt.isRegistered<T>()) await getIt.unregister<T>();
      });
    }

    register<AuthCubit>(authCubit);
    register<SettingsCubit>(settingsCubit);
    register<CapabilityRepositoryPort>(_FakeCapabilityRepository());
    register<UiEffectPort>(FakeUiEffectPort());
    addTearDown(registerReconcilePortForScreenTest());
    addTearDown(registerNoisyWallForScreenTest());

    final router = RootRouter(
      Logger('test'),
      authCubit,
      settingsCubit,
      PostJoinNavigationCubit(),
    );
    addTearDown(() async {
      router.dispose();
      for (final undo in registered) {
        await undo();
      }
    });

    final ru = lookupL10n(const Locale('ru'));
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('ru'),
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

    // Walk the whole screen: every text that is built on the way down is
    // checked, so a lazily built row cannot hide a Latin brand.
    final seen = <String>{..._renderedTexts(tester)};
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 40; i++) {
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
      final before = seen.length;
      seen.addAll(_renderedTexts(tester));
      if (seen.length == before &&
          seen.any((t) => t.contains(ru.settingsNoisyWallHint))) {
        break;
      }
    }

    expect(
      seen.where((t) => t.contains('Tentura')),
      isEmpty,
      reason: 'RU Settings rendered a Latin brand',
    );

    // The hint under «Глушить тех, чьи пересылки я игнорирую» (#1095 QA).
    expect(ru.settingsNoisyWall, 'Глушить тех, чьи пересылки я игнорирую');
    expect(find.text(ru.settingsNoisyWall), findsOneWidget);
    final hint = find.text(ru.settingsNoisyWallHint);
    expect(hint, findsOneWidget);
    expect(ru.settingsNoisyWallHint, contains('Тентура'));
    final paragraph = tester.renderObject<RenderParagraph>(hint);
    expect(paragraph.size.width, lessThanOrEqualTo(kPhoneSurface.width));
    expect(tester.takeException(), isNull);
  });
}
