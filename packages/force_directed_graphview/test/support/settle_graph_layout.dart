import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

/// Advances fake async until [controller] reports a complete layout or [maxPumps]
/// is reached. Avoids [WidgetTester.pumpAndSettle], which can run unbounded when
/// [InteractiveViewer] keeps scheduling frames.
Future<void> settleGraphLayout(
  WidgetTester tester,
  GraphController<dynamic, dynamic> controller, {
  int maxPumps = 30,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(step);
    if (controller.canLayout) {
      return;
    }
  }
  throw TestFailure(
    'Graph layout did not settle within $maxPumps pumps (canLayout=false)',
  );
}
