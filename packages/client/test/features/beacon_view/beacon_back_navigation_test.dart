import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/data/service/beacon_room_composer_draft_store.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/fake_app_navigator.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import 'beacon_view_screen_harness.dart';

Future<void> _tapPeopleTab(WidgetTester tester) async {
  await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabPeople)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

TenturaUnderlineTabs _tabs(WidgetTester tester) =>
    tester.widget<TenturaUnderlineTabs>(find.byType(TenturaUnderlineTabs));

class _LeaveHarnessNavigator extends FakeAppNavigator {
  _LeaveHarnessNavigator({this.router});

  final BeaconViewHarnessRouter? router;

  @override
  Future<void> leaveRequestDetail({bool retargetOwnerHomeTab = false}) async {
    await super.leaveRequestDetail(
      retargetOwnerHomeTab: retargetOwnerHomeTab,
    );
    final stackRouter = router;
    if (stackRouter != null && stackRouter.canPop()) {
      await stackRouter.maybePop();
    }
  }
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  group('app / Android back (T7 / D4)', () {
    testWidgets('PopScope.canPop is true on NOW', (tester) async {
      await pumpBeaconViewHarness(
        tester,
        plan: kBeaconViewHarnessOneStepPlan,
        size: kBeaconViewHarnessCompact,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
      );
      expect(_tabs(tester).selectedIndex, 0);
      expect(beaconViewPopScope(tester).canPop, isFalse);
    });

    testWidgets('back on CHAT selects NOW without leaving request', (
      tester,
    ) async {
      final router = BeaconViewHarnessRouter();
      await pumpBeaconViewHarness(
        tester,
        plan: kBeaconViewHarnessOneStepPlan,
        size: kBeaconViewHarnessCompact,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        router: router,
      );
      await tapBeaconChatTabAndWaitForRoom(tester);
      expect(beaconViewPopScope(tester).canPop, isFalse);

      final handled = await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(handled, isTrue);
      expect(router.maybePopCalls, 0);
      expect(router.popCount, 0);
      expect(_tabs(tester).selectedIndex, 0);
      expect(find.byType(ThreadDetail), findsNothing);
      expect(beaconViewPopScope(tester).canPop, isFalse);
    });

    testWidgets('back on PEOPLE selects NOW without leaving request', (
      tester,
    ) async {
      final router = BeaconViewHarnessRouter();
      await pumpBeaconViewHarness(
        tester,
        plan: kBeaconViewHarnessOneStepPlan,
        size: kBeaconViewHarnessCompact,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        router: router,
      );
      await _tapPeopleTab(tester);
      expect(_tabs(tester).selectedIndex, 3);
      expect(beaconViewPopScope(tester).canPop, isFalse);

      final handled = await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(handled, isTrue);
      expect(router.maybePopCalls, 0);
      expect(router.popCount, 0);
      expect(_tabs(tester).selectedIndex, 0);
      expect(beaconViewPopScope(tester).canPop, isFalse);
    });

    testWidgets('back on NOW with draft asks before leaving', (tester) async {
      resetBeaconRoomComposerDraftStoreForTest();
      await pumpBeaconViewHarness(
        tester,
        plan: kBeaconViewHarnessOneStepPlan,
        size: kBeaconViewHarnessCompact,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        locale: const Locale('en'),
      );
      writeBeaconRoomComposerDraft(
        beaconId: kBeaconViewHarnessBeaconId,
        body: 'Draft before system back on overview.',
      );
      expect(beaconViewPopScope(tester).canPop, isFalse);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.text('Leave without saving?'), findsOneWidget);
    });

    testWidgets('app bar back on NOW leaves via leaveRequestDetail', (
      tester,
    ) async {
      final router = BeaconViewHarnessRouter();
      await GetIt.I.unregister<AppNavigator>();
      GetIt.I.registerSingleton<AppNavigator>(
        _LeaveHarnessNavigator(router: router),
      );
      addTearDown(() async {
        if (GetIt.I.isRegistered<AppNavigator>()) {
          await GetIt.I.unregister<AppNavigator>();
        }
        await registerBeaconViewHarnessGetIt();
      });

      await pumpBeaconViewHarness(
        tester,
        plan: kBeaconViewHarnessOneStepPlan,
        size: kBeaconViewHarnessCompact,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        router: router,
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      final navigator = GetIt.I<AppNavigator>() as FakeAppNavigator;
      expect(navigator.named('leaveRequestDetail'), isNotEmpty);
    });

  });

  // --- merged from beacon_surface_selection_test.dart ---

  TestWidgetsFlutterBinding.ensureInitialized();

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
          plan: kBeaconViewHarnessOneStepPlan,
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
        expect(_tabs(tester).selectedIndex, 2);

        final roomBeforeFetch = recorder.created.single;
        final roomsBefore = recorder.created.length;

        unawaited(harness.threadsCubit.fetch());
        await tester.pump();
        expect(harness.threadsCubit.state.isLoading, isTrue);

        expect(find.byType(TenturaVerticalResizeHandle), findsOneWidget);
        expect(_tabs(tester).selectedIndex, 2);
        expect(recorder.created.length, roomsBefore);
        expect(roomBeforeFetch.closeCallCount, 0);

        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();

        expect(find.byType(TenturaVerticalResizeHandle), findsOneWidget);
        expect(_tabs(tester).selectedIndex, 2);
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
        plan: kBeaconViewHarnessOneStepPlan,
        size: kBeaconViewHarnessCompact,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(threads: threads),
        host: beaconViewHarnessHost(recorder: recorder),
        recorder: recorder,
      );
      await tapBeaconChatTabAndWaitForRoom(tester);
      expect(_tabs(tester).selectedIndex, 2);

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

    testWidgets('expanded split → compact selects CHAT surface', (
      tester,
    ) async {
      final threads = [
        ...beaconViewHarnessThreadsState().threads,
        _semanticThread(id: 'edge-room'),
      ];
      final recorder = BeaconViewRoomCubitRecorder();
      final harness = await pumpBeaconViewHarness(
        tester,
        plan: kBeaconViewHarnessOneStepPlan,
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
      expect(_tabs(tester).selectedIndex, 2);
      expect(find.byType(ThreadDetail), findsOneWidget);
      expect(harness.router.pushCount, 0);
    });
  });
}
