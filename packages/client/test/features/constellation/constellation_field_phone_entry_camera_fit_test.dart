// Entering the Field on a phone (iPhone SE, 375×667, RU) starts «fit all»:
// every node body inside the Field viewport (Bob's too), the field centred in
// the camera area, and the camera where the «Показать всё поле» control puts
// it — never the field's top-left corner, never zoomed in past fit-all, and
// no other camera shown on the way there.
//
// Every test enters the Field the way the app does: the real
// ConstellationScreen inside Home's tab router, chosen like the tab bar does.
// The field is Bob's, loaded through the real repository mapping and laid out
// by the real layout: Bob, seven direct contacts and four of their contacts.
// Each test checks that this layout is wider or taller than the phone at full
// scale, so a camera zoomed in to a cap, or left at the origin, cannot pass.
//
// Covered paths: first entry with the field loaded; first entry through the
// Field's loading shell (the field arrives after the screen is up); the
// viewport size known only after the first frames; the user's own pan/zoom
// kept for the rest of the visit, also through server refreshes that carry a
// new load time (one or several, with or without new people; an untouched
// camera still re-frames for new people); a return to the Field tab starting
// fitted again; and a visit that starts in text view fitting on its first
// switch to map, then keeping the user's camera across later text/map
// switches and refreshes that arrive while text is showing.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/app/router/root_router.gr.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_field_test_harness.dart';

const _viewer = Profile(id: 'bob', displayName: 'Боб');

const _directContacts = {
  'anna': 'Анна',
  'boris': 'Борис',
  'dima': 'Дима',
  'kira': 'Кира',
  'lena': 'Лена',
  'misha': 'Миша',
  'olga': 'Ольга',
};

/// Contacts of Bob's contacts: id → (whose contact, display name).
const _secondRing = {
  'pavel': ('anna', 'Павел'),
  'rita': ('boris', 'Рита'),
  'sasha': ('dima', 'Саша'),
  'tanya': ('kira', 'Таня'),
};

/// Graph ids of every person on Bob's Field, Bob first.
final _everyNode = [
  'fp:${_viewer.id}',
  for (final id in _directContacts.keys) 'fp:$id',
  for (final id in _secondRing.keys) 'fp:$id',
];

/// How far (logical px, each axis) the fitted field's centre may sit from the
/// camera area's centre, and the entry camera from the fit-all camera.
const _centreTolerance = 8.0;

/// How far the entry camera scale may differ from the fit-all scale.
const _scaleTolerance = 0.01;

Map<String, dynamic> _peer(String id, String displayName) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'contactOnly': false,
  'displayName': displayName,
  'handle': null,
  'image': null,
  'isNew': false,
  'pinState': null,
  'presence': 'visible',
  'temporaryBeaconId': null,
  'bondContexts': <dynamic>[],
  'visible': true,
};

Map<String, dynamic> _edge(String src, String dst) => {
  '__typename': 'v2_ConstellationEdge',
  'src': src,
  'dst': dst,
  'tier': 1,
};

/// The `loadedAt` of the first response a visit gets.
const _firstLoadedAt = '2026-11-08T12:00:00.000Z';

/// The `loadedAt` the store stamps on the [n]-th later fetch: every full fetch
/// carries a new one, so a refresh is never the same instant as the load.
String _laterLoadedAt(int n) =>
    DateTime.utc(2026, 11, 8, 12, n).toIso8601String();

/// Bob's Field as the server sends it; [extraContact] adds one more direct
/// contact (a later refresh), [loadedAt] stamps the fetch.
Map<String, dynamic> _fieldResponse({
  String? extraContact,
  String loadedAt = _firstLoadedAt,
}) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': loadedAt,
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': [
      ..._directContacts.keys,
      ?extraContact,
    ],
    'peers': [
      _peer(_viewer.id, _viewer.displayName),
      for (final MapEntry(:key, :value) in _directContacts.entries)
        _peer(key, value),
      for (final MapEntry(:key, :value) in _secondRing.entries)
        _peer(key, value.$2),
      if (extraContact != null) _peer(extraContact, 'Новый коллега'),
    ],
    'edges': [
      for (final id in _directContacts.keys) _edge(_viewer.id, id),
      for (final MapEntry(:key, :value) in _secondRing.entries)
        _edge(value.$1, key),
      if (extraContact != null) _edge(_viewer.id, extraContact),
    ],
    'requests': <dynamic>[],
    'posts': <dynamic>[],
    'memberWebs': <dynamic>[],
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': '0',
      'anchors': <dynamic>[],
      'pinnedPeers': <dynamic>[],
      'pinnedRequests': <dynamic>[],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <dynamic>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

/// Maps [response] through the real repository.
Future<ConstellationField> _mapFromWire(Map<String, dynamic> response) async {
  late final ConstellationField field;
  await withRemoteWire(
    {'ConstellationFieldFetch': response},
    [],
    (remote) async {
      field = await ConstellationRepository(remote).fetch();
    },
  );
  return field;
}

final class _GatedFieldRepository implements ConstellationRepositoryPort {
  _GatedFieldRepository(this.field, {bool open = false}) {
    if (open) {
      release();
    }
  }

  ConstellationField field;
  final _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    await _gate.future;
    return field;
  }
}

/// A Field cubit on a real store over [repository], loading as the screen's
/// route wrapper makes it load.
({ConstellationCubit cubit, ConstellationStoreFixture store}) _fieldCubit(
  _GatedFieldRepository repository,
) {
  final store = ConstellationStoreFixture(repository, accountId: _viewer.id);
  final cubit = store.createCubit(viewer: _viewer);
  unawaited(cubit.load());
  return (cubit: cubit, store: store);
}

// --- Home with the Field tab ------------------------------------------------

final class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

/// Home with its tabs; only the Constellation tab holds the real screen.
class _TestHomeShell extends StatelessWidget {
  const _TestHomeShell();

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: [for (final spec in HomeTabSpec.all) spec.rootRoute()],
    duration: Duration.zero,
    transitionBuilder: (_, child, _) => child,
    builder: (_, child) => child,
  );
}

/// The real Field screen without its DI route wrapper; its cubits are
/// provided above the app.
class _FieldTabHost extends StatelessWidget {
  const _FieldTabHost();

  @override
  Widget build(BuildContext context) => const ConstellationScreen();
}

RootStackRouter _homeRouter() => RootStackRouter.build(
  routes: [
    AutoRoute(
      page: PageInfo(HomeRoute.name, builder: (_) => const _TestHomeShell()),
      path: '/home',
      initial: true,
      children: [
        for (final spec in HomeTabSpec.all)
          AutoRoute(
            page: PageInfo(
              spec.rootRoute().routeName,
              builder: (_) => spec.tab == HomeTab.constellation
                  ? const _FieldTabHost()
                  : Text('${spec.tab.name}-root'),
            ),
            path: spec.path.split('/').last,
            initial: spec.tab == HomeTab.work,
          ),
      ],
    ),
  ],
);

TabsRouter _tabs(RootStackRouter router) =>
    router.innerRouterOf<TabsRouter>(HomeRoute.name)!;

/// Mounts Home (on the My Work tab) on a [surface]-sized phone, RU.
Future<RootStackRouter> _mountHome(
  WidgetTester tester,
  ConstellationCubit cubit, {
  Size surface = kPhoneSurface,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final selection = constellationSelectionForFieldBodyTests();
  final reselect = HomeTabReselectCubit();
  final router = _homeRouter();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    router.dispose();
    await selection.close();
    await reselect.close();
    if (!cubit.isClosed) await cubit.close();
  });
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ConstellationCubit>.value(value: cubit),
        BlocProvider<ConstellationSelectionCubit>.value(value: selection),
        BlocProvider<HomeTabReselectCubit>.value(value: reselect),
        BlocProvider<GraphPersonContextCubit>(
          create: (_) => _StubContextCubit(),
        ),
        BlocProvider<ScreenCubit>(
          create: (_) => ScreenCubit(FakeUiEffectPort()),
        ),
      ],
      child: MaterialApp.router(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router.config(),
        builder: (_, child) => TenturaResponsiveScope(child: child!),
      ),
    ),
  );
  await _pumpFrames(tester, 10);
  expect(router.current.name, HomeRoute.name);
  expect(find.byType(ConstellationScreen), findsNothing);
  return router;
}

/// Chooses [tab] the way the Home tab bar does.
void _chooseTab(RootStackRouter router, HomeTab tab) =>
    _tabs(router).setActiveIndex(HomeTabSpec.forTab(tab).index);

/// The Field keeps animating chrome, so frames are pumped, not settled.
Future<void> _pumpFrames(
  WidgetTester tester,
  int count, {
  _CameraFilm? film,
}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    film?.record(tester);
  }
}

// --- What the user sees -----------------------------------------------------

Finder get _fieldViewport => find.byType(InteractiveViewer);

Matrix4 _camera(WidgetTester tester) => tester
    .widget<InteractiveViewer>(_fieldViewport)
    .transformationController!
    .value
    .clone();

/// The Field viewport in its own coordinates (where node bodies are drawn).
Rect _viewportRect(WidgetTester tester) =>
    Offset.zero & tester.getSize(_fieldViewport);

/// The area the camera frames into: the Field viewport minus the Field's own
/// map chrome (the camera-control column on the right, the strip under the
/// top bar) that the Field reports for its camera. «Fit all» centres the field
/// here, not in the raw viewport, so the controls never cover a node; this
/// is the reading of «field centred» the fit-all scale criterion implies.
Rect _cameraArea(WidgetTester tester, ConstellationCubit cubit) =>
    cubit.fieldCameraViewportSnapshotForTest.deflateRect(
      _viewportRect(tester),
    );

/// Where scene point [scene] is drawn in the viewport through [camera].
Offset _onScreen(Matrix4 camera, Offset scene) =>
    MatrixUtils.transformPoint(camera, scene);

/// Scene position of every person on the field (null while not laid out).
Map<String, Offset> _scenePositions(ConstellationCubit cubit) => {
  for (final id in _everyNode)
    id: ?cubit.graphController.getPositionOrNullForId(id),
};

/// The node bodies of the frame drawn for the current camera.
Map<String, Rect> _drawnBodies(
  WidgetTester tester,
  ConstellationCubit cubit,
) {
  final frame = tester
      .widget<ConstellationViewportOverlay>(
        find.byType(ConstellationViewportOverlay),
      )
      .frameHolder
      .frame;
  expect(frame, isNotNull, reason: 'the Field has drawn a frame');
  expect(
    frame!.cameraRevision,
    cubit.graphController.cameraRevision.value,
    reason: 'the drawn frame belongs to the current camera, not an older one',
  );
  return frame.bodies;
}

bool _inside(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.bottom <= outer.bottom + 0.5;

/// The test field is a real test of fitting: at full scale (scene pixels are
/// screen pixels) its people span more than the phone viewport.
void _expectFieldLargerThanPhoneAtFullScale(
  WidgetTester tester,
  ConstellationCubit cubit,
) {
  final positions = _scenePositions(cubit);
  expect(positions.keys, unorderedEquals(_everyNode), reason: 'laid out');
  final xs = positions.values.map((p) => p.dx);
  final ys = positions.values.map((p) => p.dy);
  final spanX =
      xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
  final spanY =
      ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
  final viewport = _viewportRect(tester);
  expect(
    spanX > viewport.width || spanY > viewport.height,
    isTrue,
    reason:
        'field span ${spanX.round()}×${spanY.round()} px at scale 1 exceeds '
        'the viewport ${viewport.size}',
  );
}

/// Every person's body, Bob's included, is drawn fully inside the Field
/// viewport; the field is centred in the camera area; the field origin (its
/// top-left corner) is nowhere near the viewport.
void _expectWholeFieldInView(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String when,
}) {
  final viewport = _viewportRect(tester);
  final bodies = _drawnBodies(tester, cubit);
  final scale = cubit.graphController.cameraScale;
  for (final id in _everyNode) {
    final body = bodies[id];
    expect(
      body,
      isNotNull,
      reason: '$when: $id is drawn in the viewport (scale $scale)',
    );
    expect(
      _inside(viewport, body!),
      isTrue,
      reason:
          '$when: $id body $body lies inside the Field viewport $viewport '
          '(scale $scale)',
    );
  }

  final field = _everyNode
      .map((id) => bodies[id]!)
      .reduce((a, b) => a.expandToInclude(b));
  final area = _cameraArea(tester, cubit);
  expect(
    (field.center.dx - area.center.dx).abs(),
    lessThanOrEqualTo(_centreTolerance),
    reason:
        '$when: field centre ${field.center} is horizontally centred in the '
        'camera area $area',
  );
  expect(
    (field.center.dy - area.center.dy).abs(),
    lessThanOrEqualTo(_centreTolerance),
    reason:
        '$when: field centre ${field.center} is vertically centred in the '
        'camera area $area',
  );

  final origin = _onScreen(_camera(tester), Offset.zero);
  expect(
    (origin - viewport.topLeft).distance,
    greaterThanOrEqualTo(viewport.shortestSide),
    reason:
        '$when: the camera is not at the field top-left corner (field '
        'origin drawn at $origin)',
  );
}

/// The camera is the largest that shows every body, measured from what is
/// drawn rather than from the fit-all routine: every body fits the camera area
/// now, and zooming in by a third about the field centre pushes at least one
/// body out of it, so the camera is not zoomed out past fit-all either.
///
/// Why 4/3: fit-all frames the nodes' footprints padded by
/// GraphController.fitToRect's default 48 scene px. Measured on this field at
/// 375×667 with today's fit-all (scale 0.485): the node centres span 241 px
/// of the 307 px-wide camera area and bodies are 20 px across, so a body
/// leaves the area at about 1.19×. 4/3 leaves room above that margin, while a
/// camera at three quarters of fit-all or less still fits after the zoom.
void _expectLargestFit(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String when,
}) {
  const zoomIn = 4 / 3;
  final area = _cameraArea(tester, cubit);
  final bodies = [
    for (final id in _everyNode) _drawnBodies(tester, cubit)[id]!,
  ];
  final centre = bodies.reduce((a, b) => a.expandToInclude(b)).center;
  for (final body in bodies) {
    expect(
      _inside(area, body),
      isTrue,
      reason: '$when: body $body fits the camera area $area',
    );
  }
  final overflowsWhenCloser = bodies.any((body) {
    final zoomed = Rect.fromCenter(
      center: centre + (body.center - centre) * zoomIn,
      width: body.width,
      height: body.height,
    );
    return !_inside(area, zoomed);
  });
  expect(
    overflowsWhenCloser,
    isTrue,
    reason:
        '$when: at ${zoomIn.toStringAsFixed(2)}× the current scale '
        '${cubit.graphController.cameraScale} some body leaves the camera '
        'area, so the field is not zoomed out past fit-all',
  );
}

/// The current camera is the one «Показать всё поле» produces for this field:
/// same scale (so never zoomed in past fit-all) and same framing. Taps the
/// control, so call it last in a visit.
Future<void> _expectCameraIsFitAll(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String when,
}) async {
  final control = find.byKey(TestIds.key(TestIds.constellationFitAll));
  expect(
    control.hitTestable(),
    findsOneWidget,
    reason: 'the fit-all control is on screen and tappable at 375×667',
  );
  final scale = cubit.graphController.cameraScale;
  final translation = _camera(tester).getTranslation();

  await tester.tap(control);
  await _pumpFrames(tester, 30);

  final fitAllScale = cubit.graphController.cameraScale;
  final fitAllTranslation = _camera(tester).getTranslation();
  expect(
    scale,
    closeTo(fitAllScale, _scaleTolerance),
    reason: '$when: camera scale equals the fit-all scale $fitAllScale',
  );
  expect(
    (translation.x - fitAllTranslation.x).abs(),
    lessThanOrEqualTo(_centreTolerance),
    reason: '$when: camera x matches fit-all',
  );
  expect(
    (translation.y - fitAllTranslation.y).abs(),
    lessThanOrEqualTo(_centreTolerance),
    reason: '$when: camera y matches fit-all',
  );
}

/// Every check of a fitted visit, then the fit-all comparison (which taps).
Future<void> _expectEntersFitted(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String when,
}) async {
  expect(tester.takeException(), isNull, reason: '$when: no Flutter errors');
  _expectFieldLargerThanPhoneAtFullScale(tester, cubit);
  _expectWholeFieldInView(tester, cubit, when: when);
  _expectLargestFit(tester, cubit, when: when);
  await _expectCameraIsFitAll(tester, cubit, when: when);
  expect(tester.takeException(), isNull, reason: '$when: no Flutter errors');
}

/// Every camera the Field showed while entering. A frame «shows» a camera
/// when at least one person's centre is inside the viewport; frames that show
/// nobody yet (map not framed, viewport unknown) are allowed.
final class _CameraFilm {
  _CameraFilm(this.cubit);

  final ConstellationCubit cubit;
  final shown = <Matrix4>[];

  void record(WidgetTester tester) {
    if (_fieldViewport.evaluate().isEmpty) {
      return;
    }
    final viewport = _viewportRect(tester);
    if (viewport.isEmpty) {
      return;
    }
    final camera = _camera(tester);
    final positions = _scenePositions(cubit).values;
    if (positions.any((p) => viewport.contains(_onScreen(camera, p)))) {
      shown.add(camera);
    }
  }

  /// No camera other than the final one was ever shown with people in view:
  /// a camera from a zero/unknown viewport or an unsettled layout never
  /// reached the screen, even for a frame.
  void expectOnlyFinalCameraShown(
    WidgetTester tester, {
    required String when,
  }) {
    final last = _camera(tester);
    expect(shown, isNotEmpty, reason: '$when: the field was shown');
    for (final (i, camera) in shown.indexed) {
      final scaleOff = (camera.getMaxScaleOnAxis() - last.getMaxScaleOnAxis())
          .abs();
      final moveOff = (camera.getTranslation() - last.getTranslation()).length;
      expect(
        scaleOff <= 1e-3 && moveOff <= 1,
        isTrue,
        reason:
            '$when: frame $i showed a camera (scale '
            '${camera.getMaxScaleOnAxis()}, translation '
            '${camera.getTranslation()}) other than the fitted one (scale '
            '${last.getMaxScaleOnAxis()})',
      );
    }
  }
}

/// The user drags the map and pinches it closer, as on a phone.
Future<void> _panAndPinch(WidgetTester tester) async {
  final centre = tester.getCenter(_fieldViewport);
  final drag = await tester.startGesture(centre);
  await drag.moveBy(const Offset(40, 0));
  await tester.pump();
  await drag.moveBy(const Offset(50, 60));
  await tester.pump();
  await drag.up();
  await tester.pump(const Duration(milliseconds: 50));

  final a = await tester.startGesture(centre - const Offset(30, 0));
  final b = await tester.startGesture(centre + const Offset(30, 0));
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await a.moveBy(const Offset(-15, 0));
    await b.moveBy(const Offset(15, 0));
    await tester.pump();
  }
  await a.up();
  await b.up();
  await _pumpFrames(tester, 20);
}

/// The server answers the next fetch with a Field stamped [loadedAt] (and
/// [extraContact] if given); the store catches up to it, as after a push.
Future<void> _refresh(
  _GatedFieldRepository repository,
  ({ConstellationCubit cubit, ConstellationStoreFixture store}) field, {
  required String loadedAt,
  String? extraContact,
}) async {
  repository.field = await _mapFromWire(
    _fieldResponse(extraContact: extraContact, loadedAt: loadedAt),
  );
  await field.store.store.requestRefresh(ConstellationRefreshReason.catchUp);
}

/// The user's camera now, to compare against after something else happens.
({double scale, Offset translation}) _cameraNow(
  WidgetTester tester,
  ConstellationCubit cubit,
) {
  final t = _camera(tester).getTranslation();
  return (
    scale: cubit.graphController.cameraScale,
    translation: Offset(t.x, t.y),
  );
}

void _expectCameraKept(
  WidgetTester tester,
  ConstellationCubit cubit,
  ({double scale, Offset translation}) kept, {
  required String when,
}) {
  expect(
    cubit.graphController.cameraScale,
    closeTo(kept.scale, 1e-6),
    reason: '$when: the user’s zoom is kept',
  );
  final t = _camera(tester).getTranslation();
  expect(
    (Offset(t.x, t.y) - kept.translation).distance,
    lessThan(0.5),
    reason: '$when: the user’s pan is kept, no snap back to fit-all',
  );
}

/// One body, [id], is drawn fully inside the Field viewport.
void _expectBodyInView(
  WidgetTester tester,
  ConstellationCubit cubit,
  String id, {
  required String when,
}) {
  final body = _drawnBodies(tester, cubit)[id];
  expect(body, isNotNull, reason: '$when: $id is drawn');
  expect(
    _inside(_viewportRect(tester), body!),
    isTrue,
    reason: '$when: $id body $body lies inside ${_viewportRect(tester)}',
  );
}

/// The user taps the «Map» segment of the app bar's view-mode switch
/// (found by its `TestIds.constellationAppBarViewModeMap` identifier).
Future<void> _tapMapSegment(WidgetTester tester) async {
  final semantics = tester.ensureSemantics();
  try {
    await tester.tap(
      find.bySemanticsIdentifier(TestIds.constellationAppBarViewModeMap),
    );
    await _pumpFrames(tester, 60);
  } finally {
    semantics.dispose();
  }
}

Future<_GatedFieldRepository> _repository({bool open = true}) async =>
    _GatedFieldRepository(
      await _mapFromWire(_fieldResponse()),
      open: open,
    );

void main() {
  group('Entering the Field on a phone (375×667, RU) starts fitted', () {
    testWidgets(
      'first entry from the tab bar shows every node inside the viewport, '
      'centred, at the largest scale that fits (the fit-all camera)',
      (tester) async {
        final field = _fieldCubit(await _repository());
        await field.cubit.stream.firstWhere(
          (s) => s.status is StateIsSuccess,
        );
        final router = await _mountHome(tester, field.cubit);
        final film = _CameraFilm(field.cubit);

        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 60, film: film);

        expect(find.byType(ConstellationScreen), findsOneWidget);
        _expectWholeFieldInView(tester, field.cubit, when: 'first entry');
        film.expectOnlyFinalCameraShown(tester, when: 'first entry');
        await _expectEntersFitted(tester, field.cubit, when: 'first entry');
      },
    );

    testWidgets(
      'first entry through the loading shell: when the field arrives after '
      'the screen is up, only the fitted camera is ever shown',
      (tester) async {
        final repository = await _repository(open: false);
        final field = _fieldCubit(repository);
        final router = await _mountHome(tester, field.cubit);
        final film = _CameraFilm(field.cubit);

        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 10, film: film);
        expect(field.cubit.state.field, isNull, reason: 'still loading');
        expect(_fieldViewport, findsNothing, reason: 'loading shell, no map');

        repository.release();
        await _pumpFrames(tester, 90, film: film);

        expect(field.cubit.state.field, isNotNull);
        _expectWholeFieldInView(tester, field.cubit, when: 'field arrived');
        film.expectOnlyFinalCameraShown(tester, when: 'field arrived');
        await _expectEntersFitted(tester, field.cubit, when: 'field arrived');
      },
    );

    testWidgets(
      'when the viewport size is known only after the first frames, no camera '
      'from the unknown viewport stays and the Field ends fitted',
      (tester) async {
        final field = _fieldCubit(await _repository());
        await field.cubit.stream.firstWhere(
          (s) => s.status is StateIsSuccess,
        );
        final router = await _mountHome(
          tester,
          field.cubit,
          surface: Size.zero,
        );

        // The Field tab opens before the phone reports its size. The film
        // runs from the first frame; frames with a zero viewport show nothing
        // and are deliberately not judged — what is judged is that no camera
        // computed then is still on screen once the real size arrives.
        final film = _CameraFilm(field.cubit);
        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 10, film: film);
        expect(
          film.shown,
          isEmpty,
          reason: 'nothing is visible while the viewport is zero',
        );

        await tester.binding.setSurfaceSize(kPhoneSurface);
        await _pumpFrames(tester, 60, film: film);

        _expectWholeFieldInView(tester, field.cubit, when: 'viewport known');
        film.expectOnlyFinalCameraShown(tester, when: 'viewport known');
        await _expectEntersFitted(
          tester,
          field.cubit,
          when: 'viewport known',
        );
      },
    );

    testWidgets(
      'the user’s pan and pinch stay for the rest of the visit through '
      'rebuilds and layout updates',
      (tester) async {
        final repository = await _repository();
        final field = _fieldCubit(repository);
        await field.cubit.stream.firstWhere(
          (s) => s.status is StateIsSuccess,
        );
        final router = await _mountHome(tester, field.cubit);
        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 60);
        _expectWholeFieldInView(tester, field.cubit, when: 'entry');
        final fitted = _camera(tester);

        await _panAndPinch(tester);
        final userScale = field.cubit.graphController.cameraScale;
        final userTranslation = _camera(tester).getTranslation();
        expect(
          _camera(tester).storage,
          isNot(fitted.storage),
          reason: 'the gestures moved the camera',
        );

        // Still on the Field: a rebuild, then a refresh that brings a new
        // contact and lays the field out again.
        tester.element(find.byType(ConstellationScreen)).markNeedsBuild();
        await _pumpFrames(tester, 10);
        await _refresh(
          repository,
          field,
          loadedAt: _laterLoadedAt(1),
          extraContact: 'nikita',
        );
        await _pumpFrames(tester, 90);

        expect(
          field.cubit.state.field!.peers.map((p) => p.id),
          contains('nikita'),
          reason: 'the refresh reached the Field',
        );
        expect(
          field.cubit.state.field!.loadedAt,
          DateTime.utc(2026, 11, 8, 12, 1),
          reason: 'the refresh carried its own load time, not the first one',
        );
        expect(tester.takeException(), isNull);
        expect(
          field.cubit.graphController.cameraScale,
          closeTo(userScale, 1e-6),
          reason: 'the user’s zoom is kept',
        );
        expect(
          (_camera(tester).getTranslation() - userTranslation).length,
          lessThan(0.5),
          reason: 'the user’s pan is kept, no snap back to fit-all',
        );
      },
    );

    testWidgets(
      'returning to the Field tab after another tab starts fitted again',
      (tester) async {
        final field = _fieldCubit(await _repository());
        await field.cubit.stream.firstWhere(
          (s) => s.status is StateIsSuccess,
        );
        final router = await _mountHome(tester, field.cubit);

        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 60);
        await _expectEntersFitted(
          tester,
          field.cubit,
          when: 'first entry from the tab bar',
        );
        final fitted = _camera(tester);

        await _panAndPinch(tester);
        expect(
          _camera(tester).storage,
          isNot(fitted.storage),
          reason: 'the user moved the camera during the visit',
        );

        _chooseTab(router, HomeTab.inbox);
        await _pumpFrames(tester, 20);
        expect(
          find.byType(ConstellationScreen, skipOffstage: false),
          findsOneWidget,
          reason: 'the Field tab stays mounted behind the other tab',
        );
        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 60);

        _expectWholeFieldInView(tester, field.cubit, when: 'tab return');
        await _expectEntersFitted(tester, field.cubit, when: 'tab return');
      },
    );
  });

  group('A server refresh within one Field visit keeps the user’s camera', () {
    Future<
      ({
        RootStackRouter router,
        _GatedFieldRepository repository,
        ({ConstellationCubit cubit, ConstellationStoreFixture store}) field,
      })
    >
    enterFitted(WidgetTester tester) async {
      final repository = await _repository();
      final field = _fieldCubit(repository);
      await field.cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
      final router = await _mountHome(tester, field.cubit);
      _chooseTab(router, HomeTab.constellation);
      await _pumpFrames(tester, 60);
      _expectWholeFieldInView(tester, field.cubit, when: 'entry');
      return (router: router, repository: repository, field: field);
    }

    testWidgets(
      'a refresh stamped with a new load time and the same people does not '
      'snap a moved camera back to fit-all',
      (tester) async {
        final visit = await enterFitted(tester);
        final cubit = visit.field.cubit;
        final fitted = _camera(tester);

        await _panAndPinch(tester);
        expect(_camera(tester).storage, isNot(fitted.storage));
        final user = _cameraNow(tester, cubit);
        expect(cubit.graphController.userCameraInputRevision.value, isPositive);

        await _refresh(
          visit.repository,
          visit.field,
          loadedAt: _laterLoadedAt(1),
        );
        await _pumpFrames(tester, 90);

        expect(
          cubit.state.field!.loadedAt,
          DateTime.utc(2026, 11, 8, 12, 1),
          reason: 'the refresh reached the Field with its own load time',
        );
        expect(tester.takeException(), isNull);
        _expectCameraKept(tester, cubit, user, when: 'one refresh');
      },
    );

    testWidgets(
      'two refreshes in a row, each with its own load time, keep the moved '
      'camera',
      (tester) async {
        final visit = await enterFitted(tester);
        final cubit = visit.field.cubit;

        await _panAndPinch(tester);
        final user = _cameraNow(tester, cubit);

        await _refresh(
          visit.repository,
          visit.field,
          loadedAt: _laterLoadedAt(1),
        );
        await _pumpFrames(tester, 60);
        await _refresh(
          visit.repository,
          visit.field,
          loadedAt: _laterLoadedAt(2),
        );
        await _pumpFrames(tester, 60);

        expect(
          cubit.state.field!.loadedAt,
          DateTime.utc(2026, 11, 8, 12, 2),
          reason: 'the second refresh reached the Field',
        );
        expect(tester.takeException(), isNull);
        _expectCameraKept(tester, cubit, user, when: 'two refreshes');
      },
    );

    testWidgets(
      'an untouched camera re-frames to fit-all when a refresh with a new '
      'load time brings a person',
      (tester) async {
        final visit = await enterFitted(tester);
        final cubit = visit.field.cubit;
        expect(cubit.graphController.userCameraInputRevision.value, 0);
        expect(
          cubit.fieldPeerCountAtLastProgrammaticFrameForTest,
          _everyNode.length - 1,
        );

        await _refresh(
          visit.repository,
          visit.field,
          loadedAt: _laterLoadedAt(1),
          extraContact: 'nikita',
        );
        await _pumpFrames(tester, 90);

        expect(
          cubit.fieldPeerCountAtLastProgrammaticFrameForTest,
          _everyNode.length,
          reason: 'the Field was framed again with the new person',
        );
        expect(tester.takeException(), isNull);
        _expectBodyInView(tester, cubit, 'fp:nikita', when: 'after refresh');
        await _expectCameraIsFitAll(tester, cubit, when: 'after refresh');
      },
    );

    testWidgets(
      'after a refresh with a new load time, leaving the tab and coming back '
      'starts a new visit at fit-all',
      (tester) async {
        final visit = await enterFitted(tester);
        final cubit = visit.field.cubit;

        await _panAndPinch(tester);
        await _refresh(
          visit.repository,
          visit.field,
          loadedAt: _laterLoadedAt(1),
        );
        await _pumpFrames(tester, 60);

        _chooseTab(visit.router, HomeTab.inbox);
        await _pumpFrames(tester, 20);
        _chooseTab(visit.router, HomeTab.constellation);
        await _pumpFrames(tester, 60);

        _expectWholeFieldInView(tester, cubit, when: 'tab return');
        await _expectEntersFitted(tester, cubit, when: 'tab return');
      },
    );
  });

  group('A Field visit that starts in text view fits on the first switch to '
      'map', () {
    /// Enters the Field with the text view already chosen on the cubit.
    Future<
      ({
        RootStackRouter router,
        _GatedFieldRepository repository,
        ({ConstellationCubit cubit, ConstellationStoreFixture store}) field,
      })
    >
    enterInTextView(WidgetTester tester) async {
      final repository = await _repository();
      final field = _fieldCubit(repository);
      await field.cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
      final router = await _mountHome(tester, field.cubit);
      field.cubit.setViewMode(ConstellationViewMode.text);
      _chooseTab(router, HomeTab.constellation);
      await _pumpFrames(tester, 60);
      expect(field.cubit.state.viewMode, ConstellationViewMode.text);
      return (router: router, repository: repository, field: field);
    }

    testWidgets(
      'switching to map the first time shows every node inside the viewport '
      'at the fit-all camera',
      (tester) async {
        final visit = await enterInTextView(tester);

        await _tapMapSegment(tester);

        expect(visit.field.cubit.state.viewMode, ConstellationViewMode.map);
        await _expectEntersFitted(
          tester,
          visit.field.cubit,
          when: 'first switch to map',
        );
      },
    );

    testWidgets(
      'a visit that began in text view after leaving and returning to the tab '
      'fits on the first switch to map',
      (tester) async {
        final repository = await _repository();
        final field = _fieldCubit(repository);
        await field.cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
        final router = await _mountHome(tester, field.cubit);
        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 60);
        await _panAndPinch(tester);

        field.cubit.setViewMode(ConstellationViewMode.text);
        await _pumpFrames(tester, 10);
        _chooseTab(router, HomeTab.inbox);
        await _pumpFrames(tester, 20);
        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 60);
        expect(field.cubit.state.viewMode, ConstellationViewMode.text);

        await _tapMapSegment(tester);

        await _expectEntersFitted(
          tester,
          field.cubit,
          when: 'first switch to map after a new visit',
        );
      },
    );

    testWidgets(
      'the first switch to map records a programmatic frame, and with the '
      'camera untouched a later refresh with a new person re-frames',
      (tester) async {
        final visit = await enterInTextView(tester);
        final cubit = visit.field.cubit;
        expect(cubit.fieldInitialFrameCompletedForTest, isFalse);

        await _tapMapSegment(tester);

        expect(cubit.fieldInitialFrameCompletedForTest, isTrue);
        expect(
          cubit.fieldPeerCountAtLastProgrammaticFrameForTest,
          _everyNode.length - 1,
          reason: 'framed with every non-viewer person',
        );
        expect(cubit.graphController.userCameraInputRevision.value, 0);

        await _refresh(
          visit.repository,
          visit.field,
          loadedAt: _laterLoadedAt(1),
          extraContact: 'nikita',
        );
        await _pumpFrames(tester, 90);

        expect(
          cubit.fieldPeerCountAtLastProgrammaticFrameForTest,
          _everyNode.length,
        );
        _expectBodyInView(tester, cubit, 'fp:nikita', when: 'after refresh');
        await _expectCameraIsFitAll(tester, cubit, when: 'after refresh');
      },
    );

    testWidgets(
      'a second visit that starts in text view records a programmatic frame '
      'on its first switch to map, and the framing state of the earlier visit '
      'is not reused',
      (tester) async {
        final repository = await _repository();
        final field = _fieldCubit(repository);
        await field.cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
        final router = await _mountHome(tester, field.cubit);
        final cubit = field.cubit;
        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 60);
        expect(cubit.fieldInitialFrameCompletedForTest, isTrue);
        await _panAndPinch(tester);

        cubit.setViewMode(ConstellationViewMode.text);
        await _pumpFrames(tester, 10);
        _chooseTab(router, HomeTab.inbox);
        await _pumpFrames(tester, 20);
        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 60);
        expect(cubit.state.viewMode, ConstellationViewMode.text);

        await _tapMapSegment(tester);

        expect(cubit.fieldInitialFrameCompletedForTest, isTrue);
        expect(
          cubit.fieldPeerCountAtLastProgrammaticFrameForTest,
          _everyNode.length - 1,
          reason: 'framed with every non-viewer person',
        );
        await _expectEntersFitted(tester, cubit, when: 'second visit, map');
      },
    );

    testWidgets(
      'a refresh with a new load time that arrives while text view is showing '
      'is part of the fit on the first switch to map',
      (tester) async {
        final visit = await enterInTextView(tester);
        final cubit = visit.field.cubit;

        await _refresh(
          visit.repository,
          visit.field,
          loadedAt: _laterLoadedAt(1),
          extraContact: 'nikita',
        );
        await _pumpFrames(tester, 30);
        expect(cubit.state.viewMode, ConstellationViewMode.text);
        expect(cubit.state.field!.peers.map((p) => p.id), contains('nikita'));

        await _tapMapSegment(tester);

        _expectBodyInView(tester, cubit, 'fp:nikita', when: 'first switch');
        await _expectCameraIsFitAll(tester, cubit, when: 'first switch');
      },
    );

    testWidgets(
      'only the first switch to map fits: after the user moves the camera, '
      'text and back to map keep it',
      (tester) async {
        final visit = await enterInTextView(tester);
        final cubit = visit.field.cubit;
        await _tapMapSegment(tester);
        _expectWholeFieldInView(tester, cubit, when: 'first switch');

        await _panAndPinch(tester);
        final user = _cameraNow(tester, cubit);

        cubit.setViewMode(ConstellationViewMode.text);
        await _pumpFrames(tester, 20);
        await _tapMapSegment(tester);

        expect(tester.takeException(), isNull);
        _expectCameraKept(tester, cubit, user, when: 'second switch to map');
      },
    );
  });

  group('A refresh that arrives while text view is showing keeps the camera '
      'the user set on the map', () {
    testWidgets(
      'moving the camera on the map, switching to text, a refresh with a new '
      'load time, then back to map keeps the user’s camera',
      (tester) async {
        final repository = await _repository();
        final field = _fieldCubit(repository);
        await field.cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
        final router = await _mountHome(tester, field.cubit);
        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 60);

        await _panAndPinch(tester);
        final user = _cameraNow(tester, field.cubit);

        field.cubit.setViewMode(ConstellationViewMode.text);
        await _pumpFrames(tester, 20);
        await _refresh(repository, field, loadedAt: _laterLoadedAt(1));
        await _pumpFrames(tester, 60);
        expect(
          field.cubit.state.field!.loadedAt,
          DateTime.utc(2026, 11, 8, 12, 1),
          reason: 'the refresh reached the Field while text view was showing',
        );
        await _tapMapSegment(tester);

        expect(tester.takeException(), isNull);
        _expectCameraKept(tester, field.cubit, user, when: 'back to map');
      },
    );
  });

  group('A visit that starts in map view keeps the user’s camera across the '
      'text view', () {
    testWidgets(
      'moving the camera, then text and back to map without leaving the tab, '
      'does not refit',
      (tester) async {
        final repository = await _repository();
        final field = _fieldCubit(repository);
        await field.cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
        final router = await _mountHome(tester, field.cubit);
        _chooseTab(router, HomeTab.constellation);
        await _pumpFrames(tester, 60);

        await _panAndPinch(tester);
        final user = _cameraNow(tester, field.cubit);

        field.cubit.setViewMode(ConstellationViewMode.text);
        await _pumpFrames(tester, 20);
        await _tapMapSegment(tester);

        expect(tester.takeException(), isNull);
        _expectCameraKept(tester, field.cubit, user, when: 'back to map');
      },
    );
  });
}
