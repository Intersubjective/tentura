import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
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
}) {
  final wc = windowClassForWidth(width);
  final baseTheme = TenturaTheme.light();
  final tokens =
      (baseTheme.extension<TenturaTokens>() ?? TenturaTokens.light)
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
              value: _StaticThreadsCubit(threadsState ?? _threadsState(unread: 5)),
            ),
          ],
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('People is icon-only at index 2 when not split', (tester) async {
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

    final tt = TenturaTokens.light.applyWindowClass(WindowClass.compact);
    expect(find.text('People'), findsNothing);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);

    final peopleIcon = find.byIcon(Icons.people_outline);
    final peopleInkWell = tester.renderObject<RenderBox>(
      find.ancestor(of: peopleIcon, matching: find.byType(InkWell)),
    );
    expect(peopleInkWell.size.width, tt.tabCompactWidth);
  });

  testWidgets('People is icon-only at index 1 when split', (tester) async {
    await tester.pumpWidget(
      _harness(
        width: 360,
        child: BeaconSurfaceTabs(
          isSplit: true,
          selectedSurface: BeaconSurface.now,
          onSurfaceSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Chat'), findsNothing);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('People'), findsNothing);
    expect(find.byIcon(Icons.people_outline), findsOneWidget);
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
  });

  testWidgets('tapping a tab emits the right BeaconSurface', (tester) async {
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

    await tester.tap(find.text('Chat'));
    await tester.pump();
    expect(selected, [BeaconSurface.room]);

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pump();
    expect(selected, [BeaconSurface.room, BeaconSurface.people]);
  });

  testWidgets('selected-but-hidden ROOM falls back to NOW index', (tester) async {
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

  testWidgets('badges land on CHAT and People in non-split mode', (tester) async {
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
    expect(find.text('3'), findsNothing);
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

  testWidgets('NOW and CHAT stay equal width in non-split mode', (tester) async {
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

    final tt = TenturaTokens.light.applyWindowClass(WindowClass.compact);
    final inkWells = tester.renderObjectList<RenderBox>(
      find.descendant(
        of: find.byType(TenturaUnderlineTabs),
        matching: find.byType(InkWell),
      ),
    );
    final flexWidths = inkWells
        .map((box) => box.size.width)
        .where((w) => w != tt.tabCompactWidth)
        .toList();
    expect(flexWidths.length, 2);
    expect(flexWidths[0], closeTo(flexWidths[1], 0.01));
  });

  testWidgets('reselecting the active tab calls onSurfaceReselected', (
    tester,
  ) async {
    final reselected = <BeaconSurface>[];
    await tester.pumpWidget(
      _harness(
        width: 360,
        child: BeaconSurfaceTabs(
          isSplit: false,
          selectedSurface: BeaconSurface.room,
          onSurfaceSelected: (_) {},
          onSurfaceReselected: reselected.add,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Chat'));
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
    final peopleSemantics = tester.getSemantics(
      find.byIcon(Icons.people_outline),
    );
    expect(peopleSemantics.label, contains('People'));
    expect(peopleSemantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(peopleSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);
  });
}
