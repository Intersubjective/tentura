// Issue #501: the forwards graph opened from a Post (Post info → "How the
// post reached people", or a deep link to /forwards-graph/:id) must speak of
// the post, not of a request. The screen reads the beacon itself (the same
// fetch that already supplies the subtitle), so a deep link works too.
// The same holds for the rest of the screen chrome: the focused-node
// "Open …" action in the top bar and the forwards legend.

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/screen/forwards_graph_screen.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_content.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

const _me = Profile(id: 'Ume', displayName: 'Me');

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

class _EmptyGraphSource extends GraphSourceRepository {
  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) async => const {};
}

class _BeaconRepositoryFake implements BeaconRepository {
  _BeaconRepositoryFake(this.beacon, {this.pending});

  final Beacon beacon;

  /// When set, the beacon read never answers while the test looks (a slow
  /// network): the screen has only the route to go by.
  final Completer<Beacon>? pending;

  @override
  Future<Beacon> fetchBeaconById(String id) async =>
      pending == null ? beacon : pending!.future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _ProfileRepositoryFake implements ProfileRepositoryPort {
  @override
  Future<Profile> fetchById(String id) async =>
      Profile(id: id, displayName: id);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

/// A stack with nothing to pop: the leading control falls back to a plain
/// back button (as after a web refresh on a deep link).
class _NoPopRouter extends Mock implements StackRouter {
  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

Beacon _beacon({required BeaconKind kind, required String id}) => Beacon(
  id: id,
  title: 'Weekend picnic',
  author: _me,
  kind: kind,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Future<GraphCubit> _pumpScreen(
  WidgetTester tester, {
  required Beacon beacon,
  Locale locale = const Locale('en'),
  String? routeKind,
  Completer<Beacon>? pendingBeacon,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = GraphCubit(
    me: _me,
    focus: _me.id,
    graphSourceRepository: _EmptyGraphSource(),
    forwardsGraphBeaconId: beacon.id,
    edgeColors: _edgeColors,
    beaconRepository: _BeaconRepositoryFake(beacon, pending: pendingBeacon),
    profileRepository: _ProfileRepositoryFake(),
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: StackRouterScope(
        controller: _NoPopRouter(),
        stateHash: 0,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<GraphCubit>.value(value: cubit),
            BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
            BlocProvider<ProfileCubit>.value(value: _FakeProfileCubit()),
          ],
          child: ForwardsGraphScreen(focus: beacon.id, kind: routeKind),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  return cubit;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// Puts the beacon itself on the canvas and focuses it, so the top bar
/// offers its "Open …" action (same setup as the forwards-mode case in
/// graph_body_navigation_controls_test).
Future<void> _focusBeaconNode(
  WidgetTester tester,
  GraphCubit cubit,
  Beacon beacon,
) async {
  final node = BeaconNode(beacon: beacon);
  cubit.graphController.reconcileTopology({node}, const {});
  await tester.pump();
  cubit.selectNode(node);
  await _settle(tester);
}

/// Tooltip of the top-bar action that opens the focused node.
String _openDetailsTooltip(WidgetTester tester) {
  final button = find.byKey(TestIds.key(TestIds.graphOpenDetails));
  expect(button, findsOneWidget);
  return tester.widget<IconButton>(button).tooltip ?? '';
}

Future<void> _openLegend(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.legend_toggle));
  await _settle(tester);
  expect(find.byType(GraphLegendContent), findsOneWidget);
}

/// Text in the expanded legend whose words satisfy [test].
Finder _legendText(bool Function(String text) test) => find.descendant(
  of: find.byType(GraphLegendContent),
  matching: find.byWidgetPredicate(
    (w) => w is Text && test(w.data ?? w.textSpan?.toPlainText() ?? ''),
  ),
);

/// Text in the screen top bar whose words satisfy [test].
Finder _topBarText(bool Function(String text) test) => find.descendant(
  of: find.byType(TenturaTopBar),
  matching: find.byWidgetPredicate(
    (w) => w is Text && test(w.data ?? w.textSpan?.toPlainText() ?? ''),
  ),
);

final _postWord = RegExp(r'\bposts?\b', caseSensitive: false);
final _requestWord = RegExp(r'\brequests?\b', caseSensitive: false);

void main() {
  group('forwards graph of a Post (#501)', () {
    testWidgets('the title speaks of the post, not of a request', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        beacon: _beacon(kind: BeaconKind.post, id: 'Bpost1'),
      );
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.forwardsGraphView), findsNothing);
      expect(_topBarText(_requestWord.hasMatch), findsNothing);
      expect(_topBarText(_postWord.hasMatch), findsOneWidget);
      // The beacon title subtitle stays.
      expect(_topBarText((t) => t == 'Weekend picnic'), findsOneWidget);
    });

    testWidgets('Russian: the title says «пост», not «запрос»', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        beacon: _beacon(kind: BeaconKind.post, id: 'Bpost1'),
        locale: const Locale('ru'),
      );
      final l10n = lookupL10n(const Locale('ru'));

      expect(find.text(l10n.forwardsGraphView), findsNothing);
      expect(
        _topBarText((t) => t.toLowerCase().contains('запрос')),
        findsNothing,
      );
      expect(
        _topBarText((t) => t.toLowerCase().contains('пост')),
        findsOneWidget,
      );
    });

    testWidgets('the focused post node offers to open the post, not a '
        'request', (tester) async {
      final beacon = _beacon(kind: BeaconKind.post, id: 'Bpost1');
      final cubit = await _pumpScreen(tester, beacon: beacon);
      await _focusBeaconNode(tester, cubit, beacon);
      final l10n = lookupL10n(const Locale('en'));

      final tooltip = _openDetailsTooltip(tester);
      expect(tooltip, isNot(l10n.openBeacon));
      expect(tooltip, isNot(matches(_requestWord)));
      expect(tooltip, matches(_postWord));
    });

    testWidgets('Russian: the focused post node says «пост», not «запрос»', (
      tester,
    ) async {
      final beacon = _beacon(kind: BeaconKind.post, id: 'Bpost1');
      final cubit = await _pumpScreen(
        tester,
        beacon: beacon,
        locale: const Locale('ru'),
      );
      await _focusBeaconNode(tester, cubit, beacon);
      final l10n = lookupL10n(const Locale('ru'));

      final tooltip = _openDetailsTooltip(tester).toLowerCase();
      expect(tooltip, isNot(l10n.openBeacon.toLowerCase()));
      expect(tooltip, isNot(contains('запрос')));
      expect(tooltip, contains('пост'));
    });

    testWidgets('the legend does not say people can forward requests', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        beacon: _beacon(kind: BeaconKind.post, id: 'Bpost1'),
      );
      await _openLegend(tester);

      expect(_legendText(_requestWord.hasMatch), findsNothing);
      // The eye explanation itself is still there.
      expect(
        _legendText((t) => t.toLowerCase().contains('forward')),
        findsWidgets,
      );
    });

    testWidgets('Russian: the legend does not mention «запрос»', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        beacon: _beacon(kind: BeaconKind.post, id: 'Bpost1'),
        locale: const Locale('ru'),
      );
      await _openLegend(tester);

      expect(
        _legendText((t) => t.toLowerCase().contains('запрос')),
        findsNothing,
      );
      expect(
        _legendText((t) => t.toLowerCase().contains('пересыл')),
        findsWidgets,
      );
    });
  });

  group('forwards graph opened from a Post, before the post loads (#501)', () {
    testWidgets('the title names the post while the beacon is still loading', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        beacon: _beacon(kind: BeaconKind.post, id: 'Bpost1'),
        routeKind: BeaconKind.post.name,
        pendingBeacon: Completer<Beacon>(),
      );
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.forwardsGraphViewPost), findsOneWidget);
      expect(_topBarText(_requestWord.hasMatch), findsNothing);
    });

    testWidgets('Russian: «пост» while the beacon is still loading', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        beacon: _beacon(kind: BeaconKind.post, id: 'Bpost1'),
        locale: const Locale('ru'),
        routeKind: BeaconKind.post.name,
        pendingBeacon: Completer<Beacon>(),
      );

      expect(
        _topBarText((t) => t.toLowerCase().contains('запрос')),
        findsNothing,
      );
      expect(
        _topBarText((t) => t.toLowerCase().contains('пост')),
        findsOneWidget,
      );
    });

    testWidgets('the title does not flip once the post has loaded', (
      tester,
    ) async {
      final pending = Completer<Beacon>();
      final beacon = _beacon(kind: BeaconKind.post, id: 'Bpost1');
      await _pumpScreen(
        tester,
        beacon: beacon,
        routeKind: BeaconKind.post.name,
        pendingBeacon: pending,
      );
      final l10n = lookupL10n(const Locale('en'));
      expect(find.text(l10n.forwardsGraphViewPost), findsOneWidget);

      pending.complete(beacon);
      await _settle(tester);

      expect(find.text(l10n.forwardsGraphViewPost), findsOneWidget);
      expect(find.text(l10n.forwardsGraphView), findsNothing);
    });

    testWidgets('without a kind on the route the loading title keeps the '
        'request wording (guard)', (tester) async {
      await _pumpScreen(
        tester,
        beacon: _beacon(kind: BeaconKind.request, id: 'Breq1'),
        pendingBeacon: Completer<Beacon>(),
      );
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.forwardsGraphView), findsOneWidget);
    });

    testWidgets('the loaded beacon wins over a stale route kind', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        beacon: _beacon(kind: BeaconKind.request, id: 'Breq1'),
        routeKind: BeaconKind.post.name,
      );
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.forwardsGraphView), findsOneWidget);
      expect(_topBarText(_postWord.hasMatch), findsNothing);
    });
  });

  group('forwards graph of a Request keeps its copy (#501 guard)', () {
    testWidgets('the title still says how this request spread', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        beacon: _beacon(kind: BeaconKind.request, id: 'Breq1'),
      );
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.forwardsGraphView), findsOneWidget);
      expect(_topBarText(_postWord.hasMatch), findsNothing);
    });

    testWidgets('the focused request node still offers to open the request', (
      tester,
    ) async {
      final beacon = _beacon(kind: BeaconKind.request, id: 'Breq1');
      final cubit = await _pumpScreen(tester, beacon: beacon);
      await _focusBeaconNode(tester, cubit, beacon);
      final l10n = lookupL10n(const Locale('en'));

      expect(_openDetailsTooltip(tester), l10n.openBeacon);
    });
  });
}
