import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/ui/bloc/realtime_status_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/realtime_status_presenter.dart';

import '../../support/test_realtime_sync.dart';

const _pausedDelay = Duration(milliseconds: 30);

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for the offline banner transition.');
}

const _authenticated = RealtimeConnectionStatus(
  connectionEpoch: 1,
  phase: RealtimeConnectionPhase.authenticated,
  accountId: 'U-me',
);

/// #513: the app must show that it is offline even when the live socket has
/// not (yet) dropped — from HTTP transport failures and from the browser
/// online/offline signal.
void main() {
  group('issue #513 offline banner without a socket disconnect', () {
    test('a reported transport failure shows the offline banner while the '
        'socket stays authenticated, and a success clears it', () async {
      final realtime = buildTestRealtimeSync();
      final reachability = NetworkReachability.forTesting();
      final cubit = RealtimeStatusCubit.forTesting(
        realtime.case_,
        pausedDelay: _pausedDelay,
        reachability: reachability,
      );
      addTearDown(() async {
        await cubit.close();
        await reachability.dispose();
        await realtime.port.dispose();
      });

      realtime.port.emitStatus(_authenticated);
      await _waitFor(
        () => cubit.state.phase == RealtimeConnectionPhase.authenticated,
      );
      expect(cubit.state.showOfflineBanner, isFalse);

      reachability.reportTransportFailure();
      await _waitFor(() => cubit.state.showOfflineBanner);

      expect(cubit.state.phase, RealtimeConnectionPhase.authenticated);

      reachability.reportSuccess();
      await _waitFor(() => !cubit.state.showOfflineBanner);
    });

    test('the browser going offline shows the banner and coming back online '
        'clears it', () async {
      final realtime = buildTestRealtimeSync();
      final browserOnline = StreamController<bool>.broadcast();
      final reachability = NetworkReachability.forTesting(
        browserOnline: browserOnline.stream,
      );
      final cubit = RealtimeStatusCubit.forTesting(
        realtime.case_,
        pausedDelay: _pausedDelay,
        reachability: reachability,
      );
      addTearDown(() async {
        await cubit.close();
        await reachability.dispose();
        await browserOnline.close();
        await realtime.port.dispose();
      });

      realtime.port.emitStatus(_authenticated);
      await _waitFor(
        () => cubit.state.phase == RealtimeConnectionPhase.authenticated,
      );
      expect(cubit.state.showOfflineBanner, isFalse);

      browserOnline.add(false);
      await _waitFor(() => cubit.state.showOfflineBanner);

      browserOnline.add(true);
      await _waitFor(() => !cubit.state.showOfflineBanner);
    });

    testWidgets('the presenter shows the localized offline banner', (
      tester,
    ) async {
      final l10n = lookupL10n(const Locale('en'));
      final realtime = buildTestRealtimeSync();
      final reachability = NetworkReachability.forTesting();
      final cubit = RealtimeStatusCubit.forTesting(
        realtime.case_,
        pausedDelay: Duration.zero,
        reachability: reachability,
      );
      addTearDown(() async {
        await reachability.dispose();
        await realtime.port.dispose();
      });
      await tester.pumpWidget(
        BlocProvider(
          create: (_) => cubit,
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const RealtimeStatusPresenter(child: Placeholder()),
          ),
        ),
      );
      realtime.port.emitStatus(_authenticated);
      await tester.pump();

      expect(find.text(l10n.connectivityOfflineBanner), findsNothing);

      reachability.reportTransportFailure();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text(l10n.connectivityOfflineBanner), findsOneWidget);

      reachability.reportSuccess();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text(l10n.connectivityOfflineBanner), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
