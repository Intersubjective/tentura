import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'beacon_view_screen_harness.dart';
import 'dart:async';
import 'package:tentura/design_system/components/tentura_underline_tabs.dart';
import 'package:tentura/design_system/components/tentura_vertical_resize_handle.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import '../beacon_threads/room_cubit_fakes.dart';

Future<void> _tapPeopleTab(WidgetTester tester) async {
  await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabPeople)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

TenturaUnderlineTabs _tabs(WidgetTester tester) =>
    tester.widget<TenturaUnderlineTabs>(find.byType(TenturaUnderlineTabs));

class _HarnessThreadsCubitForShell extends Cubit<ThreadsState>
    implements ThreadsCubit {
  _HarnessThreadsCubitForShell(super.initial);

  void emitState(ThreadsState value) => emit(value);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

class _TwoPageShell extends StatefulWidget {
  const _TwoPageShell({required this.threadsCubit, super.key});

  final ThreadsCubit threadsCubit;

  @override
  State<_TwoPageShell> createState() => _TwoPageShellState();
}

class _TwoPageShellState extends State<_TwoPageShell> {
  late List<Page<void>> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const MaterialPage<void>(
        child: Text('my-work', textDirection: TextDirection.ltr),
      ),
      MaterialPage<void>(
        child: StackRouterScope(
          controller: BeaconViewHarnessRouter(),
          stateHash: 0,
          child: buildBeaconViewHarnessWidget(
            beaconState: beaconViewHarnessAuthorState(),
            threadsState: beaconViewHarnessThreadsState(),
            threadsCubit: widget.threadsCubit,
          ),
        ),
      ),
    ];
  }

  bool get poppedBeacon => _pages.length == 1;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      pages: _pages,
      onPopPage: (route, result) {
        if (!route.didPop(result)) return false;
        setState(() => _pages = [_pages.first]);
        return true;
      },
    );
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
        size: kBeaconViewHarnessCompact,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
      );
      expect(_tabs(tester).selectedIndex, 0);
      expect(beaconViewPopScope(tester).canPop, isTrue);
    });

    testWidgets('back on CHAT selects NOW without leaving request', (
      tester,
    ) async {
      final router = BeaconViewHarnessRouter();
      await pumpBeaconViewHarness(
        tester,
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
      expect(beaconViewPopScope(tester).canPop, isTrue);
    });

    testWidgets('back on PEOPLE selects NOW without leaving request', (
      tester,
    ) async {
      final router = BeaconViewHarnessRouter();
      await pumpBeaconViewHarness(
        tester,
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
      expect(beaconViewPopScope(tester).canPop, isTrue);
    });

    testWidgets('back on NOW pops the request route', (tester) async {
      final shellKey = GlobalKey<_TwoPageShellState>();
      final threadsCubit = _HarnessThreadsCubitForShell(
        beaconViewHarnessThreadsState().copyWith(
          status: const StateIsLoading(),
        ),
      );

      await tester.binding.setSurfaceSize(kBeaconViewHarnessCompact);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: BeaconViewResizableMediaQuery(
            size: kBeaconViewHarnessCompact,
            child: _TwoPageShell(
              key: shellKey,
              threadsCubit: threadsCubit,
            ),
          ),
        ),
      );
      threadsCubit.emitState(beaconViewHarnessThreadsState());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final innerNavigator = tester.state<NavigatorState>(
        find.descendant(
          of: find.byType(_TwoPageShell),
          matching: find.byType(Navigator),
        ),
      );

      expect(beaconViewPopScope(tester).canPop, isTrue);
      expect(innerNavigator.canPop(), isTrue);
      expect(find.text('my-work'), findsNothing);

      // Nested request Navigator receives the pop when PopScope allows it.
      final popped = await innerNavigator.maybePop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(popped, isTrue);
      expect(shellKey.currentState!.poppedBeacon, isTrue);
      expect(find.text('my-work'), findsOneWidget);
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
