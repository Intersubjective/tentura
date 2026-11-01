import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_scaffold.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

// #914: keyboard focus ring must track zoomed graph nodes (InteractiveViewer).

const _me = Profile(id: 'Ume', displayName: 'Me');

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

class _FakeGraphSource extends GraphSourceRepository {
  _FakeGraphSource({this.edges = const {}});

  final Set<EdgeDirected> edges;

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) async => focus == null ? edges : const {};
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  Future<Profile> fetchById(String id) async =>
      Profile(id: id, displayName: id);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeBeaconRepository implements BeaconRepository {
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

EdgeDirected _e(String src, String dst) => (
  src: src,
  dst: dst,
  weight: 1.0,
  node: UserNode(
    user: Profile(id: dst, displayName: dst),
  ),
  branch: null,
  srcTotalNeighborCount: null,
  dstTotalNeighborCount: null,
);

Future<void> _settleGraph(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Rect _ringOuterRect(Rect controlOnScreen) => controlOnScreen.inflate(
  TenturaFocusRing.gap + TenturaSpacing.focusRing,
);

Future<GraphCubit> _pumpTrustGraphWithFocusRing(
  WidgetTester tester, {
  required Size surfaceSize,
  required Locale locale,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = GraphCubit(
    me: _me,
    graphSourceRepository: _FakeGraphSource(
      edges: {_e('Ume', 'Ub')},
    ),
    edgeColors: _edgeColors,
    beaconRepository: _FakeBeaconRepository(),
    profileRepository: _FakeProfileRepository(),
    effects: FakeUiEffectPort(),
  );
  cubit.emit(cubit.state.copyWith(isAnimated: false));
  addTearDown(cubit.close);

  final previousHighlight = FocusManager.instance.highlightStrategy;
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => FocusManager.instance.highlightStrategy = previousHighlight,
  );

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => TenturaFocusRing(child: child!),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<GraphCubit>.value(value: cubit),
          BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          BlocProvider<ProfileCubit>.value(value: _FakeProfileCubit()),
        ],
        child: GraphScaffold(
          title: Text(locale.languageCode == 'ru' ? 'Граф' : 'Graph'),
        ),
      ),
    ),
  );

  await tester.pump();
  await _settleGraph(tester);
  return cubit;
}

Future<void> _focusGraphNode(WidgetTester tester, String userId) async {
  final nodeFinder = find.byKey(TestIds.key(TestIds.graphNode(userId)));
  expect(nodeFinder, findsOneWidget);
  final focusTarget = find.descendant(
    of: nodeFinder,
    matching: find.byType(GestureDetector),
  );
  Focus.of(tester.element(focusTarget.first)).requestFocus();
  await tester.pump();
  await tester.pump();
  // Keyboard reveal (#458) may pan the camera on the next frame.
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Rect _nodeMarkerGlobalRect(WidgetTester tester, String userId) {
  final finder = find.byKey(TestIds.key(TestIds.graphNode(userId)));
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

void main() {
  group('Graph focus ring under zoom (#914)', () {
    for (final (label, locale, surface) in [
      ('375×667 RU', const Locale('ru'), kPhoneSurface),
      ('desktop EN', const Locale('en'), const Size(900, 600)),
    ]) {
      for (final zoom in const [0.5, 1.0, 2.5]) {
        testWidgets(
          'keyboard ring surrounds focused node at zoom $zoom ($label)',
          (tester) async {
            final cubit = await _pumpTrustGraphWithFocusRing(
              tester,
              surfaceSize: surface,
              locale: locale,
            );
            final controller = cubit.graphController;
            controller.zoomBy(zoom / controller.cameraScale);
            await tester.pump();

            await _focusGraphNode(tester, 'Ub');

            final ring = find.byKey(TenturaFocusRing.ringKey);
            expect(ring, findsOneWidget);
            expect(
              tester.getRect(ring),
              rectMoreOrLessEquals(
                _ringOuterRect(_nodeMarkerGlobalRect(tester, 'Ub')),
              ),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
