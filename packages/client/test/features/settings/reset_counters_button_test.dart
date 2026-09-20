import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_reconcile_port.dart';
import 'package:tentura/features/settings/ui/bloc/reset_counters_cubit.dart';
import 'package:tentura/features/settings/ui/widget/reset_counters_button.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// D15's copy rules, as the user meets them.
void main() {
  final l10n = lookupL10n(const Locale('en'));

  setUpAll(() {
    // `showSnackBar` logs the error variant through the injected logger.
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('reset-counters-button-test'));
    }
  });

  Future<_FakeReconcile> pumpButton(
    WidgetTester tester, {
    double textScale = 1,
    double width = 400,
  }) async {
    final attention = _FakeReconcile();
    final cubit = ResetCountersCubit(attention: attention);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: TenturaResponsiveScope(
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(textScale),
              ),
              child: SingleChildScrollView(
                child: ResetCountersButton(cubit: cubit),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return attention;
  }

  testWidgets(
    'the command explains a recheck, and promises nothing is deleted',
    (tester) async {
      await pumpButton(tester);
      expect(
        find.byKey(const Key(TestIds.attentionResetCounters)),
        findsOneWidget,
      );
      expect(find.text(l10n.attentionResetCounters), findsOneWidget);
      expect(
        find.text(l10n.attentionResetCountersExplanation),
        findsOneWidget,
        reason: 'D15 — Reset must not suggest erasure, so it says what it does',
      );
    },
  );

  testWidgets('both lines are still built at 320 dp and 2x text scale', (
    tester,
  ) async {
    // The repo trap: a long line in a narrow, scaled column silently stops
    // building what follows it, with no overflow error to catch. So the
    // assertion is the positive one — the parts are there — not "did not
    // overflow", which an empty fixture satisfies too.
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await pumpButton(tester, textScale: 2, width: 320);
    expect(find.text(l10n.attentionResetCounters), findsOneWidget);
    final explanation = find.text(l10n.attentionResetCountersExplanation);
    expect(explanation, findsOneWidget);
    // Present is not enough: a one-line cap would find the widget too and
    // show the user a truncated promise. At 320 dp and 2x the sentence needs
    // several lines, so its box has to be several lines tall.
    expect(
      tester.getSize(explanation).height,
      greaterThan(60),
      reason: 'the "nothing is deleted" promise must be readable, not clipped',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a run shows progress and disables a second tap', (tester) async {
    final attention = await pumpButton(tester);

    await tester.tap(find.byKey(const Key(TestIds.attentionResetCounters)));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(l10n.attentionResetCountersProgress), findsOneWidget);
    expect(
      find.text(l10n.attentionResetCountersDone, findRichText: true),
      findsNothing,
      reason: 'a run in progress has not refreshed anything yet',
    );
    final button = tester.widget<TenturaCommandButton>(
      find.byKey(const Key(TestIds.attentionResetCounters)),
    );
    expect(
      button.onPressed,
      isNull,
      reason: 'the control the user can still see must not fire a second run',
    );

    await tester.tap(
      find.byKey(const Key(TestIds.attentionResetCounters)),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(attention.calls, 1);

    attention.pending.first.complete(_result());
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
    'a successful run says Counters refreshed even with work remaining',
    (tester) async {
      final attention = await pumpButton(tester);
      await tester.tap(find.byKey(const Key(TestIds.attentionResetCounters)));
      await tester.pump();
      attention.pending.first.complete(
        _result(needsYouTotal: 4, unrepairableObligationCount: 2),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(l10n.attentionResetCountersDone, findRichText: true), findsOneWidget);
      expect(
        find.text(l10n.attentionResetCountersFailed, findRichText: true),
        findsNothing,
        reason: 'a correct result may still contain dots and counts (D15)',
      );
    },
  );

  testWidgets('a failed run says so, and does not say refreshed', (
    tester,
  ) async {
    final attention = await pumpButton(tester);
    await tester.tap(find.byKey(const Key(TestIds.attentionResetCounters)));
    await tester.pump();
    attention.pending.first.completeError(StateError('offline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(l10n.attentionResetCountersFailed, findRichText: true), findsOneWidget);
    expect(find.text(l10n.attentionResetCountersDone, findRichText: true), findsNothing);
  });
}

AttentionReconcileResult _result({
  int needsYouTotal = 0,
  int unrepairableObligationCount = 0,
}) => AttentionReconcileResult(
  summary: AttentionSurfaceSummary(
    activityUnreadTotal: 0,
    myWorkUnreadTotal: 0,
    needsYouTotal: needsYouTotal,
  ),
  unrepairableObligationCount: unrepairableObligationCount,
);

final class _FakeReconcile implements AttentionReconcilePort {
  final List<Completer<AttentionReconcileResult>> pending = [];
  int calls = 0;

  @override
  Future<AttentionReconcileResult> reconcile() {
    calls++;
    final completer = Completer<AttentionReconcileResult>();
    pending.add(completer);
    return completer.future;
  }
}
