import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/bloc/realtime_status_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';
import 'package:tentura/ui/widget/realtime_status_presenter.dart';

import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';

const _childKey = Key('presenter-child');

const _disconnected = RealtimeConnectionStatus(
  connectionEpoch: 1,
  phase: RealtimeConnectionPhase.disconnected,
  accountId: 'U-me',
);

Future<void> _pumpPresenter(
  WidgetTester tester,
  RealtimeStatusCubit cubit, {
  Locale locale = const Locale('ru'),
}) async {
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        locale: locale,
        scaffoldMessengerKey: snackbarKey,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(
          body: RealtimeStatusPresenter(
            child: Placeholder(key: _childKey),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('paused notice is a snack that does not move the child (#1061)', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final realtime = buildTestRealtimeSync();
    const pausedDelay = Duration(milliseconds: 50);
    final cubit = RealtimeStatusCubit.forTesting(
      realtime.case_,
      pausedDelay: pausedDelay,
    );
    addTearDown(() async {
      await cubit.close();
      await realtime.port.dispose();
    });
    await _pumpPresenter(tester, cubit);

    realtime.port.emitStatus(_disconnected);
    await tester.pump();
    final topBefore = tester.getTopLeft(find.byKey(_childKey)).dy;

    await tester.pump(pausedDelay);
    await tester.pump();

    expect(cubit.state.showPausedBanner, isTrue);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byIcon(Icons.sync_problem_outlined), findsNothing);
    expect(tester.getTopLeft(find.byKey(_childKey)).dy, topBefore);

    realtime.port.emitStatus(
      const RealtimeConnectionStatus(
        connectionEpoch: 2,
        phase: RealtimeConnectionPhase.authenticated,
        accountId: 'U-me',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(cubit.state.showPausedBanner, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('only one paused snack per outage episode', (tester) async {
    final realtime = buildTestRealtimeSync();
    const shortDelay = Duration(milliseconds: 30);
    final cubit = RealtimeStatusCubit.forTesting(
      realtime.case_,
      pausedDelay: shortDelay,
    );
    addTearDown(() async {
      await cubit.close();
      await realtime.port.dispose();
    });
    await _pumpPresenter(tester, cubit, locale: const Locale('en'));

    realtime.port.emitStatus(_disconnected);
    await tester.pump();
    await tester.pump(shortDelay);
    await tester.pump();

    expect(cubit.state.showPausedBanner, isTrue);
    expect(find.byType(SnackBar), findsOneWidget);
    var snackBars = tester.widgetList<SnackBar>(find.byType(SnackBar));
    expect(snackBars.length, 1);

    realtime.port.emitStatus(
      const RealtimeConnectionStatus(
        connectionEpoch: 1,
        phase: RealtimeConnectionPhase.connecting,
        accountId: 'U-me',
      ),
    );
    await tester.pump();
    await tester.pump(shortDelay);
    await tester.pump();

    snackBars = tester.widgetList<SnackBar>(find.byType(SnackBar));
    expect(snackBars.length, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
