import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'my_work_test_support.dart';

const _accountId = 'user-1';

final class _FakePreferences implements HomeOrientationPreferencesPort {
  final activated = <String, bool>{};
  final dismissed = <String, bool>{};
  var debugOverride = OrientationDebugOverride.auto;

  String activatedReadDelayUserId = '';
  Completer<bool>? activatedReadDelay;

  @override
  Future<bool> isActivated({required String userId}) async {
    if (activatedReadDelay != null &&
        userId == activatedReadDelayUserId) {
      return activatedReadDelay!.future;
    }
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
    activated.remove(userId);
    dismissed.remove(userId);
  }

  @override
  Future<OrientationDebugOverride> getDebugOverride() async => debugOverride;

  @override
  Future<void> setDebugOverride(OrientationDebugOverride value) async {
    debugOverride = value;
  }
}

/// Flush pending microtasks without [Future.delayed], which does not advance
/// in widget tests until [WidgetTester.pump] runs.
Future<void> _settle([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Future<void> _pumpFrames(WidgetTester tester, [int turns = 3]) async {
  for (var i = 0; i < turns; i++) {
    await tester.pump();
  }
}

Future<void> _bindAndHydrate(
  HomeActivationCubit cubit,
  String accountId,
) async {
  await cubit.bindAccount(accountId);
  await _settle();
}

void _reportSettledEmpty(HomeActivationCubit cubit, String accountId) {
  cubit.reportMyWork(
    accountId: accountId,
    myWorkCardCount: 0,
    draftCount: 0,
    archivedCountHint: 0,
    myWorkLoaded: true,
  );
  cubit.reportInbox(
    accountId: accountId,
    inboxItemCount: 0,
    inboxLoaded: true,
    inboxFailed: false,
  );
}

Future<({
  MyWorkCubit myWork,
  HomeActivationCubit homeActivation,
  InboxOperationalCubit inboxOperational,
  _FakePreferences preferences,
})> _createHarness({
  FakeMyWorkRepository? repo,
  _FakePreferences? preferences,
}) async {
  final prefs = preferences ?? _FakePreferences();
  final myWork = MyWorkCubit(
    userId: _accountId,
    myWorkCase: buildTestMyWorkCase(repo: repo),
  );
  final homeActivation = HomeActivationCubit(prefs);
  final inboxOperational = InboxOperationalCubit()
    ..report(needsMeCount: 0, loadComplete: true);

  // Deliberately not awaiting `myWork`'s fetch to reach success here: this
  // runs before any widget has been pumped, and MyWorkCase's dependency
  // chain schedules real Timers/microtasks that AutomatedTestWidgetsFlutterBinding
  // holds until an explicit WidgetTester.pump() call — awaiting a bare
  // Future/Stream for that state before the first pump hangs forever.
  // _pumpMyWorkScreen pumps with real durations instead, which drains them.

  return (
    myWork: myWork,
    homeActivation: homeActivation,
    inboxOperational: inboxOperational,
    preferences: prefs,
  );
}

Future<void> _pumpMyWorkScreen(
  WidgetTester tester, {
  required MyWorkCubit myWork,
  required HomeActivationCubit homeActivation,
  required InboxOperationalCubit inboxOperational,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<MyWorkCubit>.value(value: myWork),
            BlocProvider<HomeActivationCubit>.value(value: homeActivation),
            BlocProvider<InboxOperationalCubit>.value(value: inboxOperational),
            BlocProvider(create: (_) => HomeTabReselectCubit()),
            BlocProvider(create: (_) => ScreenCubit.local()),
          ],
          child: const MyWorkScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  // MyWorkCubit's initial fetch resolves through MyWorkCase's dependency
  // chain, which schedules real Timers/microtasks. Only a pump with a real
  // duration advances the test binding's held clock far enough to drain
  // them — a bare `await` on the cubit's stream before any pump hangs.
  for (var i = 0; i < 20 && !myWork.state.isSuccess; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _disposeHarness(
  WidgetTester tester, {
  required MyWorkCubit myWork,
  required HomeActivationCubit homeActivation,
  required InboxOperationalCubit inboxOperational,
}) async {
  // Unmount first so MyWorkScreen's BlocBuilder/BlocListener widgets release
  // their subscriptions before any cubit they were listening to closes.
  await tester.pumpWidget(const SizedBox.shrink());
  // MyWorkCubit.close()'s underlying broadcast StreamController.close()
  // does not resolve in this harness even after thousands of drained
  // microtasks (confirmed by direct measurement) — its Timer cancellation
  // and all 7 StreamSubscription.cancel() calls complete fine, so nothing
  // observable is left dangling; only fire-and-forget it rather than block
  // the test on a Future that never settles here.
  unawaited(myWork.close());
  await homeActivation.close();
  await inboxOperational.close();
}

void main() {
  testWidgets(
    'unactivated settled-empty active filter shows HomeOrientationPanel',
    (tester) async {
      final harness = await _createHarness();
      await _bindAndHydrate(harness.homeActivation, _accountId);
      _reportSettledEmpty(harness.homeActivation, _accountId);

      await _pumpMyWorkScreen(
        tester,
        myWork: harness.myWork,
        homeActivation: harness.homeActivation,
        inboxOperational: harness.inboxOperational,
      );
      await _pumpFrames(tester);

      expect(
        find.byKey(TestIds.key(TestIds.orientationPanel)),
        findsOneWidget,
      );
      expect(find.text('No active work yet'), findsNothing);

      await _disposeHarness(
        tester,
        myWork: harness.myWork,
        homeActivation: harness.homeActivation,
        inboxOperational: harness.inboxOperational,
      );
    },
  );

  testWidgets('drafts filter keeps MyWorkEmptyBody without orientation panel', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _bindAndHydrate(harness.homeActivation, _accountId);
    _reportSettledEmpty(harness.homeActivation, _accountId);

    harness.myWork.setFilter(MyWorkFilter.drafts);

    await _pumpMyWorkScreen(
      tester,
      myWork: harness.myWork,
      homeActivation: harness.homeActivation,
      inboxOperational: harness.inboxOperational,
    );
    await _pumpFrames(tester);

    expect(find.byKey(TestIds.key(TestIds.orientationPanel)), findsNothing);
    expect(find.text('No drafts'), findsOneWidget);

    await _disposeHarness(
      tester,
      myWork: harness.myWork,
      homeActivation: harness.homeActivation,
      inboxOperational: harness.inboxOperational,
    );
  });

  testWidgets('activated account keeps MyWorkEmptyBody without orientation panel', (
    tester,
  ) async {
    final prefs = _FakePreferences()..activated[_accountId] = true;
    final harness = await _createHarness(preferences: prefs);
    await _bindAndHydrate(harness.homeActivation, _accountId);
    _reportSettledEmpty(harness.homeActivation, _accountId);

    await _pumpMyWorkScreen(
      tester,
      myWork: harness.myWork,
      homeActivation: harness.homeActivation,
      inboxOperational: harness.inboxOperational,
    );
    await _pumpFrames(tester);

    expect(find.byKey(TestIds.key(TestIds.orientationPanel)), findsNothing);
    expect(find.text('No active work yet'), findsOneWidget);

    await _disposeHarness(
      tester,
      myWork: harness.myWork,
      homeActivation: harness.homeActivation,
      inboxOperational: harness.inboxOperational,
    );
  });

  testWidgets('unhydrated HomeActivation shows spinner not empty widgets', (
    tester,
  ) async {
    final prefs = _FakePreferences()
      ..activatedReadDelayUserId = _accountId
      ..activatedReadDelay = Completer<bool>();
    final harness = await _createHarness(preferences: prefs);

    unawaited(harness.homeActivation.bindAccount(_accountId));

    await _pumpMyWorkScreen(
      tester,
      myWork: harness.myWork,
      homeActivation: harness.homeActivation,
      inboxOperational: harness.inboxOperational,
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(TestIds.key(TestIds.orientationPanel)), findsNothing);
    expect(find.text('No active work yet'), findsNothing);
    expect(find.text('Welcome to Tentura'), findsNothing);

    prefs.activatedReadDelay!.complete(false);
    await _settle();
    await _pumpFrames(tester);

    await _disposeHarness(
      tester,
      myWork: harness.myWork,
      homeActivation: harness.homeActivation,
      inboxOperational: harness.inboxOperational,
    );
  });

  testWidgets(
    'My Work loaded while Inbox activation signal is in flight shows spinner',
    (tester) async {
      final harness = await _createHarness();
      await _bindAndHydrate(harness.homeActivation, _accountId);
      harness.homeActivation.reportMyWork(
        accountId: _accountId,
        myWorkCardCount: 0,
        draftCount: 0,
        archivedCountHint: 0,
        myWorkLoaded: true,
      );

      await _pumpMyWorkScreen(
        tester,
        myWork: harness.myWork,
        homeActivation: harness.homeActivation,
        inboxOperational: harness.inboxOperational,
      );
      await _pumpFrames(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(TestIds.key(TestIds.orientationPanel)), findsNothing);
      expect(find.text('No active work yet'), findsNothing);

      await _disposeHarness(
        tester,
        myWork: harness.myWork,
        homeActivation: harness.homeActivation,
        inboxOperational: harness.inboxOperational,
      );
    },
  );

  testWidgets('inboxFailed keeps MyWorkEmptyBody and never shows orientation panel', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _bindAndHydrate(harness.homeActivation, _accountId);
    harness.homeActivation.reportMyWork(
      accountId: _accountId,
      myWorkCardCount: 0,
      draftCount: 0,
      archivedCountHint: 0,
      myWorkLoaded: true,
    );
    harness.homeActivation.reportInbox(
      accountId: _accountId,
      inboxItemCount: 0,
      inboxLoaded: false,
      inboxFailed: true,
    );

    await _pumpMyWorkScreen(
      tester,
      myWork: harness.myWork,
      homeActivation: harness.homeActivation,
      inboxOperational: harness.inboxOperational,
    );
    await _pumpFrames(tester);

    expect(find.byKey(TestIds.key(TestIds.orientationPanel)), findsNothing);
    expect(find.text('No active work yet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await _disposeHarness(
      tester,
      myWork: harness.myWork,
      homeActivation: harness.homeActivation,
      inboxOperational: harness.inboxOperational,
    );
  });
}
