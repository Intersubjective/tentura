import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/design_system/components/tentura_vertical_resize_handle.dart';

import 'beacon_view_screen_harness.dart';

RequestThread _harnessSemanticThread({required String id}) => RequestThread(
  threadId: id,
  kind: RequestThreadKind.ask,
  unreadCount: 0,
  item: CoordinationItem(
    id: id,
    beaconId: kBeaconViewHarnessBeaconId,
    kind: CoordinationItemKind.ask,
    status: CoordinationItemStatus.open,
    creatorId: kBeaconViewHarnessAuthorId,
    createdAt: kBeaconViewHarnessNow,
    updatedAt: kBeaconViewHarnessNow,
    published: true,
    targetPersonId: 'helper',
    title: 'Ask',
  ),
  lastSeenAt: kBeaconViewHarnessSeenAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  testWidgets(
    'issue #168 expanded split shows one header overflow menu',
    (tester) async {
      final threads = [
        ...beaconViewHarnessThreadsState().threads,
        _harnessSemanticThread(id: 'coord-split-overflow'),
      ];

      await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessExpanded,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(threads: threads),
      );

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ThreadDetail).evaluate().isNotEmpty &&
            find.byType(TenturaVerticalResizeHandle).evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();

      expect(find.byType(TenturaVerticalResizeHandle), findsOneWidget);
      expect(find.byType(ThreadDetail), findsOneWidget);
      expect(find.byType(BeaconOverflowMenu), findsWidgets);

      // Acceptance (#168): one ⋮ per request header chrome when the
      // secondary (discussion) pane is open beside NOW.
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    },
  );
}
