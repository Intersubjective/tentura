import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/components/tentura_vertical_resize_handle.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_surface_tabs.dart';

import 'beacon_view_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    resetBeaconSplitNowPaneWidth();
    await unregisterBeaconViewHarnessGetIt();
  });

  Future<void> pumpSplit(WidgetTester tester) async {
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessExpanded,
      beaconState: beaconViewHarnessAuthorState(),
      threadsState: beaconViewHarnessThreadsState(),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ThreadDetail).evaluate().isNotEmpty &&
          find.byType(TenturaVerticalResizeHandle).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  double nowPaneWidth(WidgetTester tester) =>
      tester.getSize(find.byType(BeaconSurfaceTabs)).width;

  testWidgets('dragging the split handle moves the Now pane edge 1:1', (
    tester,
  ) async {
    await pumpSplit(tester);
    final handle = find.byType(TenturaVerticalResizeHandle);
    final before = tester.getRect(handle).center.dx;
    final widthBefore = nowPaneWidth(tester);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    // Several pointer moves land between frames on a slow (debug web) build;
    // every one of them must count, not only the last before the frame.
    for (var frame = 0; frame < 4; frame++) {
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(-5, 0));
      }
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(tester.getRect(handle).center.dx, closeTo(before - 100, 2));
    expect(nowPaneWidth(tester), closeTo(widthBefore + 100, 2));
  });
}
