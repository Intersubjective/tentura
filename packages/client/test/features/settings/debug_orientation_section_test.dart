import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/settings/ui/message/debug_settings_messages.dart';
import 'package:tentura/features/settings/ui/screen/debug_settings_screen.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

const _accountId = 'user-orientation-debug';

final class _FakePreferences implements HomeOrientationPreferencesPort {
  final activated = <String, bool>{};
  final dismissed = <String, bool>{};
  var debugOverride = OrientationDebugOverride.auto;
  int setDebugOverrideCalls = 0;
  int resetFirstRunStateCalls = 0;

  @override
  Future<bool> isActivated({required String userId}) async {
    return activated[userId] ?? false;
  }

  @override
  Future<void> setActivated({required String userId}) async {
    activated[userId] = true;
  }

  @override
  Future<bool> isOrientationDismissed({required String userId}) async {
    return dismissed[userId] ?? false;
  }

  @override
  Future<void> setOrientationDismissed({required String userId}) async {
    dismissed[userId] = true;
  }

  @override
  Future<void> resetFirstRunState({required String userId}) async {
    resetFirstRunStateCalls++;
    activated.remove(userId);
    dismissed.remove(userId);
  }

  @override
  Future<OrientationDebugOverride> getDebugOverride() async => debugOverride;

  @override
  Future<void> setDebugOverride(OrientationDebugOverride value) async {
    setDebugOverrideCalls++;
    debugOverride = value;
  }
}

Future<void> _settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Future<void> _bindAndHydrate(
  HomeActivationCubit cubit,
  String accountId,
) async {
  await cubit.bindAccount(accountId);
  await _settle();
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required HomeActivationCubit homeActivation,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: BlocProvider<HomeActivationCubit>.value(
          value: homeActivation,
          child: const Scaffold(
            body: SingleChildScrollView(
              child: FirstRunOrientationDebugSection(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late _FakePreferences preferences;
  late HomeActivationCubit cubit;
  late FakeUiEffectPort effects;

  setUp(() {
    preferences = _FakePreferences();
    cubit = HomeActivationCubit(preferences);
    effects = FakeUiEffectPort();
    GetIt.I.registerSingleton<UiEffectPort>(effects);
  });

  tearDown(() async {
    await cubit.close();
    await GetIt.I.reset();
  });

  testWidgets('selecting each segment calls setDebugOverride with matching value',
      (tester) async {
    await _bindAndHydrate(cubit, _accountId);
    await _pumpSection(tester, homeActivation: cubit);

    await tester.tap(find.byKey(TestIds.key(TestIds.debugOrientationShow)));
    await tester.pump();
    await _settle();
    expect(preferences.debugOverride, OrientationDebugOverride.show);
    expect(cubit.state.debugOverride, OrientationDebugOverride.show);

    await tester.tap(find.byKey(TestIds.key(TestIds.debugOrientationHide)));
    await tester.pump();
    await _settle();
    expect(preferences.debugOverride, OrientationDebugOverride.hide);
    expect(cubit.state.debugOverride, OrientationDebugOverride.hide);

    await tester.tap(find.byKey(TestIds.key(TestIds.debugOrientationAuto)));
    await tester.pump();
    await _settle();
    expect(preferences.debugOverride, OrientationDebugOverride.auto);
    expect(cubit.state.debugOverride, OrientationDebugOverride.auto);
    expect(preferences.setDebugOverrideCalls, 3);
  });

  testWidgets('reset calls resetFirstRunState', (tester) async {
    preferences.activated[_accountId] = true;
    preferences.dismissed[_accountId] = true;
    await _bindAndHydrate(cubit, _accountId);
    expect(cubit.state.activatedLatch, isTrue);
    expect(cubit.state.dismissedLatch, isTrue);

    await _pumpSection(tester, homeActivation: cubit);
    await tester.tap(find.byKey(TestIds.key(TestIds.debugOrientationReset)));
    await tester.pump();
    await _settle();

    expect(preferences.resetFirstRunStateCalls, 1);
    expect(cubit.state.activatedLatch, isFalse);
    expect(cubit.state.dismissedLatch, isFalse);
    expect(
      effects.emitted.whereType<ShowMessage>().map((e) => e.message),
      contains(isA<DebugOrientationResetMessage>()),
    );
  });

  testWidgets('status readout reflects cubit state', (tester) async {
    await _bindAndHydrate(cubit, _accountId);
    cubit.reportMyWork(
      accountId: _accountId,
      myWorkCardCount: 2,
      draftCount: 1,
      archivedCountHint: 1,
      myWorkLoaded: true,
    );
    cubit.reportInbox(
      accountId: _accountId,
      inboxItemCount: 3,
      inboxLoaded: true,
      inboxFailed: false,
    );
    await cubit.dismiss();
    await _settle();

    await _pumpSection(tester, homeActivation: cubit);

    expect(
      find.text('Activated: true · Dismissed: true · Activity: 6'),
      findsOneWidget,
    );
  });
}
