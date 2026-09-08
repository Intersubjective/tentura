import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/components/tentura_underline_tabs.dart';
import 'package:tentura/design_system/components/tentura_vertical_resize_handle.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/ui/test_ids.dart';

import '../beacon_threads/room_cubit_fakes.dart';
import 'beacon_view_screen_harness.dart';

RequestThread _semanticThread({required String id}) => RequestThread(
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

class _DelayedThreadsRepository extends FakeBeaconThreadsRepository {
  _DelayedThreadsRepository({
    required super.userId,
    required this.threads,
    this.fetchDelay = Duration.zero,
  });

  final List<RequestThread> threads;
  final Duration fetchDelay;

  @override
  Future<List<RequestThread>> fetchThreads(String beaconId) async {
    if (fetchDelay > Duration.zero) {
      await Future<void>.delayed(fetchDelay);
    }
    return threads;
  }
}

TenturaUnderlineTabs _tabs(WidgetTester tester) =>
    tester.widget<TenturaUnderlineTabs>(find.byType(TenturaUnderlineTabs));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  group('split latch under non-silent threads refresh (T3 / F6)', () {
    testWidgets(
      'non-silent fetch while PEOPLE is selected keeps split and surface',
      (tester) async {
        final threads = [
          ...beaconViewHarnessThreadsState().threads,
          _semanticThread(id: 'coord-item'),
        ];
        final repo = _DelayedThreadsRepository(
          userId: kBeaconViewHarnessAuthorId,
          threads: threads,
          fetchDelay: const Duration(milliseconds: 200),
        );
        await registerBeaconViewHarnessGetIt(roomRepo: repo);

        final recorder = BeaconViewRoomCubitRecorder();
        final host = beaconViewHarnessHost(recorder: recorder);
        final threadsCubit = ThreadsCubit(beaconId: kBeaconViewHarnessBeaconId);

        final harness = await pumpBeaconViewHarness(
          tester,
          size: kBeaconViewHarnessExpanded,
          beaconState: beaconViewHarnessAuthorState(),
          threadsState: beaconViewHarnessThreadsState(threads: threads),
          host: host,
          recorder: recorder,
          threadsCubit: threadsCubit,
        );

        expect(find.byType(TenturaVerticalResizeHandle), findsOneWidget);

        await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabPeople)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(_tabs(tester).selectedIndex, 1);

        final roomBeforeFetch = recorder.created.single;
        final roomsBefore = recorder.created.length;

        unawaited(harness.threadsCubit.fetch());
        await tester.pump();
        expect(harness.threadsCubit.state.isLoading, isTrue);

        expect(find.byType(TenturaVerticalResizeHandle), findsOneWidget);
        expect(_tabs(tester).selectedIndex, 1);
        expect(recorder.created.length, roomsBefore);
        expect(roomBeforeFetch.closeCallCount, 0);

        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();

        expect(find.byType(TenturaVerticalResizeHandle), findsOneWidget);
        expect(_tabs(tester).selectedIndex, 1);
        expect(identical(recorder.created.single, roomBeforeFetch), isTrue);
        expect(roomBeforeFetch.closeCallCount, 0);
        expect(find.byType(ThreadDetail), findsOneWidget);
      },
    );
  });

  group('split edge surface reselection (§4.1)', () {
    testWidgets('non-split CHAT → expanded split selects NOW', (tester) async {
      final threads = [
        ...beaconViewHarnessThreadsState().threads,
        _semanticThread(id: 'edge-now'),
      ];
      final recorder = BeaconViewRoomCubitRecorder();
      final harness = await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessCompact,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(threads: threads),
        host: beaconViewHarnessHost(recorder: recorder),
        recorder: recorder,
      );
      await tapBeaconChatTabAndWaitForRoom(tester);
      expect(_tabs(tester).selectedIndex, 1);

      await resizeBeaconViewHarness(
        tester,
        harness,
        kBeaconViewHarnessExpanded,
      );

      expect(find.byType(TenturaVerticalResizeHandle), findsOneWidget);
      expect(_tabs(tester).selectedIndex, 0);
      expect(find.byType(ThreadDetail), findsOneWidget);
      expect(harness.router.pushCount, 0);
    });

    testWidgets('expanded split → compact selects CHAT surface', (tester) async {
      final threads = [
        ...beaconViewHarnessThreadsState().threads,
        _semanticThread(id: 'edge-room'),
      ];
      final recorder = BeaconViewRoomCubitRecorder();
      final harness = await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessExpanded,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(threads: threads),
        host: beaconViewHarnessHost(recorder: recorder),
        recorder: recorder,
      );

      expect(find.byType(TenturaVerticalResizeHandle), findsOneWidget);
      expect(_tabs(tester).selectedIndex, 0);

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ThreadDetail).evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.byType(ThreadDetail), findsOneWidget);

      await resizeBeaconViewHarness(
        tester,
        harness,
        kBeaconViewHarnessCompact,
      );

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ThreadDetail).evaluate().isNotEmpty) {
          break;
        }
      }

      expect(find.byType(TenturaVerticalResizeHandle), findsNothing);
      expect(_tabs(tester).selectedIndex, 1);
      expect(find.byType(ThreadDetail), findsOneWidget);
      expect(harness.router.pushCount, 0);
    });
  });
}
