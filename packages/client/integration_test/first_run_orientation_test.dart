import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

/// English [L10n.orientationWhereSemantics] for the Activity nav row
/// (`l10n.inbox`'s value; the nav label was renamed Inbox → Activity).
const _inboxNavSemanticsLabel =
    'Activity: Requests your friends have forwarded to you.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first-run orientation panel matrix', (tester) async {
    await launchApp(app.main);
    await tester.pumpAndSettle();

    final fixture = await bootstrapFixture(
      runId: uniqueRunId('first-run-orientation'),
    );
    final prefs = GetIt.I<HomeOrientationPreferencesPort>();
    final title = uniqueRequestTitle('IT orientation');

    await logout(tester);
    await loginAs(tester, fixture.authorEmail);
    await showMyWorkList(tester);
    await awaitActivationSettled(tester, fixture.authorUserId);
    await expectOrientationPanel(tester, visible: true);

    await runE2eStep('Activity nav row', () async {
      await tapAndSettle(
        tester,
        find.bySemanticsLabel(_inboxNavSemanticsLabel),
      );
      expect(currentAppUrl(), contains(kPathInbox));
    });

    await runE2eStep('back to Work tab', () async {
      await goToPath(tester, kPathMyWork);
      await awaitActivationSettled(tester, fixture.authorUserId);
      await expectOrientationPanel(tester, visible: true);
    });

    await runE2eStep('dismiss orientation', () async {
      await tapAndSettle(
        tester,
        find.byKey(TestIds.key(TestIds.orientationDismiss)),
      );
      await awaitActivationSettled(tester, fixture.authorUserId);
      await expectOrientationPanel(tester, visible: false);
    });

    await runE2eStep('dismiss persisted to Drift', () async {
      expect(
        await prefs.isOrientationDismissed(userId: fixture.authorUserId),
        isTrue,
      );
      expect(
        await prefs.isActivated(userId: fixture.authorUserId),
        isFalse,
      );
    });

    await runE2eStep('panel hidden after settings navigation', () async {
      await goToPath(tester, kPathSettings);
      await goToPath(tester, kPathMyWork);
      await awaitActivationSettled(tester, fixture.authorUserId);
      await expectOrientationPanel(tester, visible: false);
    });

    await runE2eStep('debug override show beats dismiss latch', () async {
      await openDebugSettings(tester);
      await setOrientationOverride(tester, OrientationDebugOverride.show);
      await goToPath(tester, kPathMyWork);
      await awaitActivationSettled(tester, fixture.authorUserId);
      await expectOrientationPanel(tester, visible: true);
    });

    await runE2eStep('debug override hide', () async {
      await openDebugSettings(tester);
      await setOrientationOverride(tester, OrientationDebugOverride.hide);
      await goToPath(tester, kPathMyWork);
      await awaitActivationSettled(tester, fixture.authorUserId);
      await expectOrientationPanel(tester, visible: false);
    });

    await runE2eStep('reset clears dismiss latch under auto', () async {
      await openDebugSettings(tester);
      await setOrientationOverride(tester, OrientationDebugOverride.auto);
      await resetFirstRunOrientation(tester);
      await goToPath(tester, kPathMyWork);
      await awaitActivationSettled(tester, fixture.authorUserId);
      await expectOrientationPanel(tester, visible: true);
    });

    await runE2eStep('activity latches activation', () async {
      await createAndForwardRequest(
        tester,
        fixture: fixture,
        title: title,
      );
      await goToPath(tester, kPathMyWork);
      await awaitActivationSettled(tester, fixture.authorUserId);
      expect(
        await prefs.isActivated(userId: fixture.authorUserId),
        isTrue,
      );
    });

    await runE2eStep('activation re-derived after reset (D3)', () async {
      await openDebugSettings(tester);
      await resetFirstRunOrientation(tester);
      await goToPath(tester, kPathMyWork);
      await showMyWorkList(tester);
      // Reset clears in-memory latches; [HomeActivationReporter] only
      // re-reports on projection changes, so pull-to-refresh is required to
      // re-derive activation from the still-non-empty My Work projection.
      final refresh = find.byType(RefreshIndicator);
      await pumpUntilVisible(tester, refresh);
      await tester.fling(refresh.first, const Offset(0, 400), 1500);
      await pumpUntil(
        tester,
        () => GetIt.I<HomeActivationCubit>().state.activatedLatch,
        label: 'activation re-latched in cubit',
        timeout: const Duration(seconds: 30),
      );
      await awaitActivationSettled(tester, fixture.authorUserId);
      expect(
        await prefs.isActivated(userId: fixture.authorUserId),
        isTrue,
      );
    });

    await runE2eStep('helper: hidden because activated, not author latch', () async {
      await logout(tester);
      await loginAs(tester, fixture.helperEmail);
      await showMyWorkList(tester);
      await awaitActivationSettled(tester, fixture.helperUserId);
      await expectOrientationPanel(tester, visible: false);
      expect(
        await prefs.isOrientationDismissed(userId: fixture.helperUserId),
        isFalse,
      );
      expect(
        await prefs.isActivated(userId: fixture.helperUserId),
        isTrue,
      );
    });

    await runE2eStep('teardown debug override', () async {
      await openDebugSettings(tester);
      await setOrientationOverride(tester, OrientationDebugOverride.auto);
    });
  });
}
