import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/platform/lifecycle_handler.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import '../../support/test_realtime_sync.dart';

void main() {
  testWidgets('native resume requests projection catch-up', (tester) async {
    final realtime = buildTestRealtimeSync();
    GetIt.I.registerSingleton<RealtimeSyncCase>(realtime.case_);
    final catchUps = <RealtimeCatchUp>[];
    final sub = realtime.case_.catchUps.listen(catchUps.add);
    await tester.pumpWidget(
      const LifecycleHandler(
        attachNotificationRouting: false,
        child: SizedBox(),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();

    expect(catchUps, hasLength(1));
    expect(catchUps.single.reason, RealtimeCatchUpReason.appResumed);
    await tester.pumpWidget(const SizedBox());
    unawaited(sub.cancel());
  });
}
