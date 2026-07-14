import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/bloc/realtime_status_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/realtime_status_presenter.dart';

import '../../support/test_realtime_sync.dart';

void main() {
  testWidgets('presents and clears the localized paused banner', (
    tester,
  ) async {
    final realtime = buildTestRealtimeSync();
    final cubit = RealtimeStatusCubit.forTesting(
      realtime.case_,
      pausedDelay: Duration.zero,
    );
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => cubit,
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const RealtimeStatusPresenter(child: Placeholder()),
        ),
      ),
    );

    realtime.port.emitStatus(
      const RealtimeConnectionStatus(
        connectionEpoch: 1,
        phase: RealtimeConnectionPhase.disconnected,
        accountId: 'U-me',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.textContaining('Live updates are paused'), findsOneWidget);

    realtime.port.emitStatus(
      const RealtimeConnectionStatus(
        connectionEpoch: 2,
        phase: RealtimeConnectionPhase.authenticated,
        accountId: 'U-me',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Live updates are paused'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
