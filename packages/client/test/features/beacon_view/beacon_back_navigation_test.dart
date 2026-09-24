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

    testWidgets('back on CHAT selects NOW without leaving request', (tester) async {
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

    testWidgets('back on PEOPLE selects NOW without leaving request', (tester) async {
      final router = BeaconViewHarnessRouter();
      await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessCompact,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        router: router,
      );
      await _tapPeopleTab(tester);
      expect(_tabs(tester).selectedIndex, 2);
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
        beaconViewHarnessThreadsState().copyWith(status: const StateIsLoading()),
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
}
