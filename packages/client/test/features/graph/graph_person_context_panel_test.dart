import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/graph_mode.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _StubGraphCubit extends Cubit<GraphState> implements GraphCubit {
  _StubGraphCubit({
    required GraphState initial,
    this.canPageMoreFor = const {},
  }) : super(initial);

  final Map<String, bool> canPageMoreFor;
  int expandCalls = 0;

  @override
  final bool genealogyMode = false;

  @override
  final String? forwardsGraphBeaconId = null;

  @override
  GraphMode get mode => GraphMode.trust;

  @override
  final graphController =
      GraphController<NodeDetails, EdgeDetails<NodeDetails>>();

  @override
  bool canPageMore(String id) => canPageMoreFor[id] ?? false;

  @override
  Future<void> expandNode(NodeDetails node) async {
    expandCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit([GraphPersonContextState? initial])
    : super(initial ?? const GraphPersonContextState());

  int trustCalls = 0;
  int dismissCalls = 0;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() => dismissCalls += 1;

  @override
  Future<void> trustSelected() async => trustCalls += 1;

  @override
  void clearSelection() {}
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required Profile profile,
  required GraphState graphState,
  required _StubGraphCubit graphCubit,
  _StubContextCubit? contextCubit,
  FakeUiEffectPort? effects,
  Size size = const Size(900, 600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final ctx = contextCubit ?? _StubContextCubit();
  final fx = effects ?? FakeUiEffectPort();
  addTearDown(ctx.close);
  addTearDown(graphCubit.close);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<GraphCubit>.value(value: graphCubit),
              BlocProvider<GraphPersonContextCubit>.value(value: ctx),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(fx)),
            ],
            child: Scaffold(
              body: GraphPersonContextPanel(
                profile: profile,
                focusedNode: UserNode(user: profile),
                graphState: graphState,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

bool _focusAncestorHasKey(WidgetTester tester, Key key) {
  final focusedContext = tester.binding.focusManager.primaryFocus?.context;
  if (focusedContext == null) {
    return false;
  }
  var found = false;
  focusedContext.visitAncestorElements((element) {
    if (element.widget.key == key) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Future<void> _tabToNextFocus(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
}

void main() {
  group('GraphPersonContextPanel', () {
    testWidgets(
      'mutual MR without outgoing trust: Send, profile, expand, Trust',
      (
        tester,
      ) async {
        const profile = Profile(
          id: 'U-peer',
          displayName: 'Peer',
          score: 1,
          rScore: 1,
        );
        final graphCubit = _StubGraphCubit(
          initial: const GraphState(
            me: Profile(id: 'U-me', displayName: 'Me'),
            focus: 'U-peer',
            hiddenNeighborCounts: {'U-peer': 3},
          ),
          canPageMoreFor: {'U-peer': true},
        );
        await _pumpPanel(
          tester,
          profile: profile,
          graphState: graphCubit.state,
          graphCubit: graphCubit,
        );

        final l10n = lookupL10n(const Locale('en'));
        expect(find.text(l10n.profileSendRequestTo), findsOneWidget);
        expect(find.text(l10n.profile), findsOneWidget);
        expect(find.text(l10n.graphShowMoreConnections(3)), findsOneWidget);
        expect(find.text(l10n.trustThisUser), findsOneWidget);
        expect(find.text(l10n.profileRequestOptions), findsNothing);
      },
    );

    testWidgets('viewer-only with outgoing trust: unavailable + options', (
      tester,
    ) async {
      const profile = Profile(
        id: 'U-peer',
        displayName: 'Peer',
        myVote: 1,
        score: 1,
      );
      final graphCubit = _StubGraphCubit(
        initial: const GraphState(
          me: Profile(id: 'U-me', displayName: 'Me'),
          focus: 'U-peer',
        ),
      );
      await _pumpPanel(
        tester,
        profile: profile,
        graphState: graphCubit.state,
        graphCubit: graphCubit,
      );

      final l10n = lookupL10n(const Locale('en'));
      expect(find.text(l10n.profileRequestUnavailable), findsOneWidget);
      expect(find.text(l10n.profileRequestOptions), findsOneWidget);
      expect(find.text(l10n.trustThisUser), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('subject-only: Trust primary + Request options', (
      tester,
    ) async {
      const profile = Profile(
        id: 'U-peer',
        displayName: 'Peer',
        rScore: 1,
      );
      final graphCubit = _StubGraphCubit(
        initial: const GraphState(
          me: Profile(id: 'U-me', displayName: 'Me'),
          focus: 'U-peer',
        ),
      );
      await _pumpPanel(
        tester,
        profile: profile,
        graphState: graphCubit.state,
        graphCubit: graphCubit,
      );

      final l10n = lookupL10n(const Locale('en'));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text(l10n.trustThisUser), findsOneWidget);
      expect(find.text(l10n.profileRequestOptions), findsOneWidget);
    });

    testWidgets('neither visibility: Trust primary + Request options', (
      tester,
    ) async {
      const profile = Profile(id: 'U-peer', displayName: 'Peer');
      final graphCubit = _StubGraphCubit(
        initial: const GraphState(
          me: Profile(id: 'U-me', displayName: 'Me'),
          focus: 'U-peer',
        ),
      );
      await _pumpPanel(
        tester,
        profile: profile,
        graphState: graphCubit.state,
        graphCubit: graphCubit,
      );

      final l10n = lookupL10n(const Locale('en'));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text(l10n.trustThisUser), findsOneWidget);
      expect(find.text(l10n.profileRequestOptions), findsOneWidget);
      expect(find.text(l10n.profile), findsOneWidget);
    });

    testWidgets('mutual with outgoing trust: Send without secondary Trust', (
      tester,
    ) async {
      const profile = Profile(
        id: 'U-peer',
        displayName: 'Peer',
        myVote: 1,
        score: 1,
        rScore: 1,
      );
      final graphCubit = _StubGraphCubit(
        initial: const GraphState(
          me: Profile(id: 'U-me', displayName: 'Me'),
          focus: 'U-peer',
        ),
      );
      await _pumpPanel(
        tester,
        profile: profile,
        graphState: graphCubit.state,
        graphCubit: graphCubit,
      );

      final l10n = lookupL10n(const Locale('en'));
      expect(find.text(l10n.profileSendRequestTo), findsOneWidget);
      expect(find.text(l10n.trustThisUser), findsNothing);
    });

    testWidgets('Send emits forward navigation', (tester) async {
      const profile = Profile(
        id: 'U-peer',
        displayName: 'Peer',
        score: 1,
        rScore: 1,
      );
      final effects = FakeUiEffectPort();
      final graphCubit = _StubGraphCubit(
        initial: const GraphState(
          me: Profile(id: 'U-me', displayName: 'Me'),
          focus: 'U-peer',
        ),
      );
      await _pumpPanel(
        tester,
        profile: profile,
        graphState: graphCubit.state,
        graphCubit: graphCubit,
        effects: effects,
      );

      await tester.tap(
        find.byKey(TestIds.key(TestIds.graphPersonContextSendRequest)),
      );
      await tester.pump();
      expect(
        effects.emitted.whereType<NavigatePush>().map((e) => e.path).toList(),
        ['$kPathForwardPerson/U-peer'],
      );
    });

    testWidgets('Request options emit forward navigation', (tester) async {
      const profile = Profile(id: 'U-peer', displayName: 'Peer');
      final effects = FakeUiEffectPort();
      final graphCubit = _StubGraphCubit(
        initial: const GraphState(
          me: Profile(id: 'U-me', displayName: 'Me'),
          focus: 'U-peer',
        ),
      );
      await _pumpPanel(
        tester,
        profile: profile,
        graphState: graphCubit.state,
        graphCubit: graphCubit,
        effects: effects,
      );

      await tester.tap(
        find.byKey(TestIds.key(TestIds.graphPersonContextRequestOptions)),
      );
      await tester.pump();
      expect(
        effects.emitted.whereType<NavigatePush>().map((e) => e.path).toList(),
        ['$kPathForwardPerson/U-peer'],
      );
    });

    testWidgets('View profile emits profile navigation', (tester) async {
      const profile = Profile(id: 'U-peer', displayName: 'Peer');
      final effects = FakeUiEffectPort();
      final graphCubit = _StubGraphCubit(
        initial: const GraphState(
          me: Profile(id: 'U-me', displayName: 'Me'),
          focus: 'U-peer',
        ),
      );
      await _pumpPanel(
        tester,
        profile: profile,
        graphState: graphCubit.state,
        graphCubit: graphCubit,
        effects: effects,
      );

      await tester.tap(
        find.byKey(TestIds.key(TestIds.graphPersonContextViewProfile)),
      );
      await tester.pump();
      expect(
        effects.emitted.whereType<NavigatePush>().map((e) => e.path).toList(),
        ['$kPathProfileView/U-peer'],
      );
    });

    testWidgets('Show more calls expandNode', (tester) async {
      const profile = Profile(id: 'U-peer', displayName: 'Peer');
      final graphCubit = _StubGraphCubit(
        initial: const GraphState(
          me: Profile(id: 'U-me', displayName: 'Me'),
          focus: 'U-peer',
          hiddenNeighborCounts: {'U-peer': 2},
        ),
        canPageMoreFor: {'U-peer': true},
      );
      await _pumpPanel(
        tester,
        profile: profile,
        graphState: graphCubit.state,
        graphCubit: graphCubit,
      );

      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextShowMore)),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(TestIds.key(TestIds.graphPersonContextShowMore)),
      );
      await tester.pump();
      expect(graphCubit.expandCalls, 1);
    });

    testWidgets('Show more hidden when canPageMore is false', (tester) async {
      const profile = Profile(id: 'U-peer', displayName: 'Peer');
      final graphCubit = _StubGraphCubit(
        initial: const GraphState(
          me: Profile(id: 'U-me', displayName: 'Me'),
          focus: 'U-peer',
          hiddenNeighborCounts: {'U-peer': 2},
        ),
        canPageMoreFor: const {},
      );
      await _pumpPanel(
        tester,
        profile: profile,
        graphState: graphCubit.state,
        graphCubit: graphCubit,
      );

      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextShowMore)),
        findsNothing,
      );
    });

    testWidgets('close calls dismiss on context cubit', (tester) async {
      const profile = Profile(id: 'U-peer', displayName: 'Peer');
      final graphCubit = _StubGraphCubit(
        initial: const GraphState(
          me: Profile(id: 'U-me', displayName: 'Me'),
          focus: 'U-peer',
        ),
      );
      final contextCubit = _StubContextCubit();
      await _pumpPanel(
        tester,
        profile: profile,
        graphState: graphCubit.state,
        graphCubit: graphCubit,
        contextCubit: contextCubit,
      );

      await tester.tap(
        find.byKey(TestIds.key(TestIds.graphPersonContextClose)),
      );
      await tester.pump();
      expect(contextCubit.dismissCalls, 1);
    });

    testWidgets(
      'tab order: primary, secondary trust, profile, show more, close',
      (
        tester,
      ) async {
        const profile = Profile(
          id: 'U-peer',
          displayName: 'Peer',
          score: 1,
          rScore: 1,
        );
        final graphCubit = _StubGraphCubit(
          initial: const GraphState(
            me: Profile(id: 'U-me', displayName: 'Me'),
            focus: 'U-peer',
            hiddenNeighborCounts: {'U-peer': 3},
          ),
          canPageMoreFor: {'U-peer': true},
        );
        await _pumpPanel(
          tester,
          profile: profile,
          graphState: graphCubit.state,
          graphCubit: graphCubit,
        );

        await _tabToNextFocus(tester);
        expect(
          _focusAncestorHasKey(
            tester,
            TestIds.key(TestIds.graphPersonContextSendRequest),
          ),
          isTrue,
        );

        await _tabToNextFocus(tester);
        expect(
          _focusAncestorHasKey(
            tester,
            TestIds.key(TestIds.graphPersonContextTrust),
          ),
          isTrue,
        );

        await _tabToNextFocus(tester);
        expect(
          _focusAncestorHasKey(
            tester,
            TestIds.key(TestIds.graphPersonContextViewProfile),
          ),
          isTrue,
        );

        await _tabToNextFocus(tester);
        expect(
          _focusAncestorHasKey(
            tester,
            TestIds.key(TestIds.graphPersonContextShowMore),
          ),
          isTrue,
        );

        await _tabToNextFocus(tester);
        expect(
          _focusAncestorHasKey(
            tester,
            TestIds.key(TestIds.graphPersonContextClose),
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'tab order: trust primary then request options before profile',
      (
        tester,
      ) async {
        const profile = Profile(
          id: 'U-peer',
          displayName: 'Peer',
          rScore: 1,
        );
        final graphCubit = _StubGraphCubit(
          initial: const GraphState(
            me: Profile(id: 'U-me', displayName: 'Me'),
            focus: 'U-peer',
          ),
        );
        await _pumpPanel(
          tester,
          profile: profile,
          graphState: graphCubit.state,
          graphCubit: graphCubit,
        );

        await _tabToNextFocus(tester);
        expect(
          _focusAncestorHasKey(
            tester,
            TestIds.key(TestIds.graphPersonContextTrust),
          ),
          isTrue,
        );

        await _tabToNextFocus(tester);
        expect(
          _focusAncestorHasKey(
            tester,
            TestIds.key(TestIds.graphPersonContextRequestOptions),
          ),
          isTrue,
        );

        await _tabToNextFocus(tester);
        expect(
          _focusAncestorHasKey(
            tester,
            TestIds.key(TestIds.graphPersonContextViewProfile),
          ),
          isTrue,
        );

        await _tabToNextFocus(tester);
        expect(
          _focusAncestorHasKey(
            tester,
            TestIds.key(TestIds.graphPersonContextClose),
          ),
          isTrue,
        );
      },
    );
  });
}
