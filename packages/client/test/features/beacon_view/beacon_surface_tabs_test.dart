import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_surface_tabs.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_constants.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

class _StaticThreadsCubit extends Cubit<ThreadsState> implements ThreadsCubit {
  _StaticThreadsCubit(ThreadsState state) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticPlanCubit extends Cubit<PlanState> implements PlanCubit {
  _StaticPlanCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The Request plan (#220) with one untimed step: the Plan tab shows.
const _planWithStep = BeaconPlan(
  beaconId: 'parent-1',
  editable: true,
  steps: [PlanStep(id: 'S1', index: 1, title: 'Bring boards')],
);

PlanState _planState(BeaconPlan? plan) => PlanState(
  beaconId: 'parent-1',
  viewerId: 'auth',
  plan: plan,
  status: const StateIsSuccess(),
);

class _StaticBeaconViewCubit extends Cubit<BeaconViewState>
    implements BeaconViewCubit {
  _StaticBeaconViewCubit(BeaconViewState state) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BeaconViewState _beaconState({
  bool isBeaconMine = true,
  int unanswered = 0,
  int needCoordination = 0,
}) {
  final now = DateTime.utc(2026, 1, 1);
  const profile = Profile(id: 'auth', displayName: 'Author');
  final helpOffers = <TimelineHelpOffer>[
    for (var i = 0; i < unanswered; i++)
      TimelineHelpOffer(
        user: Profile(id: 'helper-u-$i', displayName: 'Helper $i'),
        message: 'help',
        createdAt: now,
        updatedAt: now,
      ),
    for (var i = 0; i < needCoordination; i++)
      TimelineHelpOffer(
        user: Profile(id: 'coord-u-$i', displayName: 'Coord $i'),
        message: 'help',
        createdAt: now,
        updatedAt: now,
        coordinationResponse: CoordinationResponseType.needCoordination,
      ),
  ];
  return BeaconViewState(
    beacon: Beacon.empty.copyWith(
      id: 'parent-1',
      title: 'Parent',
      author: profile,
      createdAt: now,
      updatedAt: now,
    ),
    myProfile: isBeaconMine
        ? profile
        : const Profile(id: 'viewer', displayName: 'Viewer'),
    helpOffers: helpOffers,
    roomParticipantsLoaded: true,
  );
}

ThreadsState _threadsState({int unread = 0}) => ThreadsState(
  threads: [
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      unreadCount: unread,
      messageCount: 1,
      lastMessageAt: DateTime.utc(2026),
      lastMessageAuthorId: 'auth',
    ),
  ],
  resolvedUnreadByThreadId: {RequestThread.generalId: unread},
  status: const StateIsSuccess(),
);

Widget _harness({
  required Widget child,
  required double width,
  BeaconViewState? beaconState,
  ThreadsState? threadsState,
  PlanState? planState,
}) {
  final wc = windowClassForWidth(width);
  final baseTheme = TenturaTheme.light();
  final tokens = (baseTheme.extension<TenturaTokens>() ?? TenturaTokens.light)
      .applyWindowClass(wc);
  return MaterialApp(
    theme: baseTheme.copyWith(
      extensions: [
        tokens,
        ...baseTheme.extensions.values.where((e) => e is! TenturaTokens),
      ],
    ),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<BeaconViewCubit>.value(
              value: _StaticBeaconViewCubit(
                beaconState ?? _beaconState(unanswered: 2, needCoordination: 3),
              ),
            ),
            BlocProvider<ThreadsCubit>.value(
              value: _StaticThreadsCubit(
                threadsState ?? _threadsState(unread: 5),
              ),
            ),
            BlocProvider<PlanCubit>.value(
              value: _StaticPlanCubit(planState ?? _planState(_planWithStep)),
            ),
          ],
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  // The labelled tests use 720 px: in the test font «Discussion» (#609)
  // no longer fits a 140 px slot, and the bar then shows icons only.
  testWidgets('People is labeled at index 3 when not split', (tester) async {
    await tester.pumpWidget(
      _harness(
        width: 720,
        child: BeaconSurfaceTabs(
          isSplit: false,
          selectedSurface: BeaconSurface.now,
          onSurfaceSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Discussion'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
  });

  testWidgets('People sits at index 1 when split', (tester) async {
    await tester.pumpWidget(
      _harness(
        width: 420,
        child: BeaconSurfaceTabs(
          isSplit: true,
          selectedSurface: BeaconSurface.now,
          onSurfaceSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Discussion'), findsNothing);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.byIcon(Icons.people_outline), findsOneWidget);
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
  });

  testWidgets('tapping a tab emits the right BeaconSurface', (tester) async {
    final selected = <BeaconSurface>[];
    await tester.pumpWidget(
      _harness(
        width: 720,
        child: BeaconSurfaceTabs(
          isSplit: false,
          selectedSurface: BeaconSurface.now,
          onSurfaceSelected: selected.add,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Discussion'));
    await tester.pump();
    expect(selected, [BeaconSurface.room]);

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pump();
    expect(selected, [BeaconSurface.room, BeaconSurface.people]);

    await tester.tap(find.text('Plan'));
    await tester.pump();
    expect(selected, [
      BeaconSurface.room,
      BeaconSurface.people,
      BeaconSurface.plan,
    ]);
  });

  testWidgets('at 360 px every tab still taps and nothing overflows '
      '(#542 review)', (tester) async {
    // 360 px is a common phone width; the longer "Overview" label must not
    // break the bar there. Taps go by key, not by label text.
    final selected = <BeaconSurface>[];
    await tester.pumpWidget(
      _harness(
        width: 360,
        child: BeaconSurfaceTabs(
          isSplit: false,
          selectedSurface: BeaconSurface.now,
          onSurfaceSelected: selected.add,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    for (final id in [
      TestIds.beaconTabPlan,
      TestIds.beaconTabRoom,
      TestIds.beaconTabPeople,
    ]) {
      await tester.tap(find.byKey(TestIds.key(id)));
      await tester.pump();
    }
    expect(selected, [
      BeaconSurface.plan,
      BeaconSurface.room,
      BeaconSurface.people,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected-but-hidden ROOM falls back to NOW index', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        width: 360,
        child: BeaconSurfaceTabs(
          isSplit: true,
          selectedSurface: BeaconSurface.room,
          onSurfaceSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    final tabs = tester.widget<TenturaUnderlineTabs>(
      find.byType(TenturaUnderlineTabs),
    );
    expect(tabs.selectedIndex, 0);
  });

  testWidgets('badges land on CHAT and People in non-split mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        width: 360,
        beaconState: _beaconState(unanswered: 2, needCoordination: 3),
        threadsState: _threadsState(unread: 5),
        child: BeaconSurfaceTabs(
          isSplit: false,
          selectedSurface: BeaconSurface.now,
          onSurfaceSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('5'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // A labeled People tab has room for the coordination count too.
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('badges land on People only in split mode', (tester) async {
    await tester.pumpWidget(
      _harness(
        width: 360,
        beaconState: _beaconState(unanswered: 2, needCoordination: 3),
        threadsState: _threadsState(unread: 5),
        child: BeaconSurfaceTabs(
          isSplit: true,
          selectedSurface: BeaconSurface.now,
          onSurfaceSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('5'), findsNothing);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('all four tabs share the width in non-split mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        width: 360,
        child: BeaconSurfaceTabs(
          isSplit: false,
          selectedSurface: BeaconSurface.now,
          onSurfaceSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    final widths = tester
        .renderObjectList<RenderBox>(
          find.descendant(
            of: find.byType(TenturaUnderlineTabs),
            matching: find.byType(InkWell),
          ),
        )
        .map((box) => box.size.width)
        .toList();
    expect(widths, hasLength(4));
    expect(widths[0], closeTo(widths[1], 0.01));
    expect(widths[1], closeTo(widths[2], 0.01));
    expect(widths[2], closeTo(widths[3], 0.01));
  });

  testWidgets('reselecting the active tab calls onSurfaceReselected', (
    tester,
  ) async {
    final reselected = <BeaconSurface>[];
    await tester.pumpWidget(
      _harness(
        width: 720,
        child: BeaconSurfaceTabs(
          isSplit: false,
          selectedSurface: BeaconSurface.room,
          onSurfaceSelected: (_) {},
          onSurfaceReselected: reselected.add,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Discussion'));
    await tester.pump();
    expect(reselected, [BeaconSurface.room]);
  });

  testWidgets('People tab uses stable test id and semantics', (tester) async {
    await tester.pumpWidget(
      _harness(
        width: 360,
        child: BeaconSurfaceTabs(
          isSplit: false,
          selectedSurface: BeaconSurface.people,
          onSurfaceSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(ValueKey<String>(TestIds.beaconTabPeople)),
      findsOneWidget,
    );
    // By the semantics id, not the icon: whether the 360 px row shows icons
    // or labels depends on the font the labels are measured with.
    final peopleSemantics = tester.getSemantics(
      find.bySemanticsIdentifier(TestIds.beaconTabPeople),
    );
    expect(peopleSemantics.label, contains('People'));
    expect(peopleSemantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(peopleSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);
  });

  group('#546: no Plan tab until the Request has a plan step', () {
    Future<void> pumpTabs(
      WidgetTester tester, {
      required PlanState planState,
      BeaconSurface selected = BeaconSurface.now,
      bool isSplit = false,
    }) async {
      await tester.pumpWidget(
        _harness(
          width: 720,
          planState: planState,
          child: BeaconSurfaceTabs(
            isSplit: isSplit,
            selectedSurface: selected,
            onSurfaceSelected: (_) {},
          ),
        ),
      );
      await tester.pump();
    }

    final planTab = find.byKey(TestIds.key(TestIds.beaconTabPlan));

    testWidgets('no plan: no Plan tab, three tabs left', (tester) async {
      await pumpTabs(tester, planState: _planState(null));

      expect(planTab, findsNothing);
      expect(find.text('Plan'), findsNothing);
      final tabs = tester.widget<TenturaUnderlineTabs>(
        find.byType(TenturaUnderlineTabs),
      );
      expect(tabs.tabs, hasLength(3));
      expect(find.byKey(TestIds.key(TestIds.beaconTabNow)), findsOneWidget);
      expect(find.byKey(TestIds.key(TestIds.beaconTabRoom)), findsOneWidget);
      expect(find.byKey(TestIds.key(TestIds.beaconTabPeople)), findsOneWidget);
    });

    testWidgets('a plan with no steps (all removed): no Plan tab', (
      tester,
    ) async {
      await pumpTabs(
        tester,
        planState: _planState(
          const BeaconPlan(beaconId: 'parent-1', editable: true),
        ),
      );

      expect(planTab, findsNothing);
    });

    testWidgets('split window without a plan: Now and People only', (
      tester,
    ) async {
      await pumpTabs(tester, planState: _planState(null), isSplit: true);

      final tabs = tester.widget<TenturaUnderlineTabs>(
        find.byType(TenturaUnderlineTabs),
      );
      expect(tabs.tabs, hasLength(2));
      expect(planTab, findsNothing);
    });

    testWidgets('a plan with a step: the Plan tab is back (guard)', (
      tester,
    ) async {
      await pumpTabs(tester, planState: _planState(_planWithStep));

      expect(planTab, findsOneWidget);
    });

    testWidgets('tapping People without a plan still emits People', (
      tester,
    ) async {
      final selected = <BeaconSurface>[];
      await tester.pumpWidget(
        _harness(
          width: 720,
          planState: _planState(null),
          child: BeaconSurfaceTabs(
            isSplit: false,
            selectedSurface: BeaconSurface.now,
            onSurfaceSelected: selected.add,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(TestIds.key(TestIds.beaconTabPeople)));
      await tester.pump();
      expect(selected, [BeaconSurface.people]);
    });
  });
}
