// A cold entry to the Field (a reload with the Field tab open, F5) frames
// every person on the Field without any fit-all press or camera input, in
// whichever order the viewport size and the Field's people arrive; and a
// live viewport resize with an untouched camera re-frames the Field.
//
// Every test mounts Home with the Field as the tab the app opens on (as a
// reload of /home/constellation does: the Field tab is active from the first
// frame, it is never chosen from another tab). The Field is Bob's, loaded
// through the real GraphQL mapping and repository into the real store,
// ConstellationCubit and ConstellationScreen/ConstellationBody, and laid out
// by the real layout: Bob, seven direct contacts and four of their contacts.
//
// Mount orders covered, at 375×667 RU and at 1280×800:
// - the viewport has its size first, the Field's people arrive later;
// - the Field's people arrive first, the viewport has no size at first and
//   gets it later;
// - the viewport grows in steps while the Field boots (a small first size,
//   then the real one).
// Then the live resize, 1280×800 → 375×667 and 375×667 → 1280×800.
//
// The initial-frame flag (`fieldInitialFrameCompletedForTest`) is checked
// around fit attempts that come too early — while the Field has no placed
// person, while the graph cannot lay out yet, or while the viewport has no
// size — and after the fit that frames the placed people.
//
// One extra scenario of «the people are laid out late»: the account's saved
// tag magnet is read after the Field is already on screen (the cubit reads
// magnets on every cold load), and seats the tagged people elsewhere. The
// people are laid out only then, so they must be framed only then.
@TestOn('vm')
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/app/router/root_router.gr.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_tag_magnet_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
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
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_field_test_harness.dart';

const _viewer = Profile(id: 'bob', displayName: 'Боб');

/// The desktop window QA reloads the Field in.
const _desktopSurface = Size(1280, 800);

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

/// Bob's Field as the server sends it.
Map<String, dynamic> _fieldResponse() => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-08T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': [..._directContacts.keys],
    'peers': [
      _peer(_viewer.id, _viewer.displayName),
      for (final MapEntry(:key, :value) in _directContacts.entries)
        _peer(key, value),
      for (final MapEntry(:key, :value) in _secondRing.entries)
        _peer(key, value.$2),
    ],
    'edges': [
      for (final id in _directContacts.keys) _edge(_viewer.id, id),
      for (final MapEntry(:key, :value) in _secondRing.entries)
        _edge(value.$1, key),
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

/// Bob's Field mapped through the real repository.
Future<ConstellationField> _mapFromWire() async {
  late final ConstellationField field;
  await withRemoteWire(
    {'ConstellationFieldFetch': _fieldResponse()},
    [],
    (remote) async {
      field = await ConstellationRepository(remote).fetch();
    },
  );
  return field;
}

/// Answers the Field fetch only once [release] is called: the people arrive
/// when the test says so.
final class _GatedFieldRepository implements ConstellationRepositoryPort {
  _GatedFieldRepository(this.field, {bool open = false}) {
    if (open) {
      release();
    }
  }

  final ConstellationField field;
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

Future<_GatedFieldRepository> _repository({required bool open}) async =>
    _GatedFieldRepository(await _mapFromWire(), open: open);

/// A Field cubit on a real store over [repository], loading as the screen's
/// route wrapper makes it load on a reload.
ConstellationCubit _fieldCubit(_GatedFieldRepository repository) {
  final store = ConstellationStoreFixture(repository, accountId: _viewer.id);
  final cubit = store.createCubit(viewer: _viewer);
  unawaited(cubit.load());
  return cubit;
}

// --- Tags whose saved magnet arrives after the Field -------------------------

/// Bob's tag «Работа» on three of his direct contacts.
const _workTag = 'work';
const _workPeople = {'anna', 'boris', 'dima'};

Set<String> _tagsOf(String personId) =>
    _workPeople.contains(personId) ? const {_workTag} : const {};

Set<String> _peopleIn(String tagId) =>
    tagId == _workTag ? _workPeople : const {};

/// The server's saved tag magnets, answered only once [release] is called:
/// the magnet read finishes after the Field is on screen.
final class _GatedMagnetRepository
    implements ConstellationTagMagnetRepositoryPort {
  _GatedMagnetRepository(this.saved);

  final List<ConstellationTagMagnet> saved;
  final _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<List<ConstellationTagMagnet>> list() async {
    await _gate.future;
    return saved;
  }

  @override
  Future<ConstellationTagMagnet> upsert({
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) => throw UnimplementedError('nobody moves a magnet in these tests');

  @override
  Future<void> remove({required String tagId, required String clientOpId}) =>
      throw UnimplementedError('nobody removes a magnet in these tests');
}

/// A Field cubit as the app builds it for an account with tags: the real
/// store over [repository] plus the tag magnet use case over [magnets].
ConstellationCubit _taggedFieldCubit(
  _GatedFieldRepository repository,
  _GatedMagnetRepository magnets,
) {
  final store = ConstellationStoreFixture(repository, accountId: _viewer.id);
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  final cubit = ConstellationCubit(
    case_: store.store,
    viewer: _viewer,
    tagMagnetCase: ConstellationTagMagnetCase(
      magnets,
      realtime.case_,
      env: const Env(),
      logger: Logger('field-cold-entry'),
    ),
    ownTagIdsOf: _tagsOf,
    peopleInTag: _peopleIn,
    loadOnCreate: false,
  );
  addTearDown(() async {
    if (!cubit.isClosed) await cubit.close();
  });
  unawaited(cubit.load());
  return cubit;
}

// --- Home reloaded on the Field tab -----------------------------------------

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

class _FieldTabHost extends StatelessWidget {
  const _FieldTabHost();

  @override
  Widget build(BuildContext context) => const ConstellationScreen();
}

/// Home whose initial tab is the Field, as after a reload of the Field URL.
RootStackRouter _homeOnFieldRouter() => RootStackRouter.build(
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
            initial: spec.tab == HomeTab.constellation,
          ),
      ],
    ),
  ],
);

/// Reloads the app on the Field tab with the window at [surface] (may be
/// [Size.zero]: the browser has not reported a size yet).
Future<void> _reloadOnField(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required Size surface,
  Locale locale = const Locale('ru'),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final selection = constellationSelectionForFieldBodyTests();
  final reselect = HomeTabReselectCubit();
  final router = _homeOnFieldRouter();
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
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router.config(),
        builder: (_, child) => TenturaResponsiveScope(child: child!),
      ),
    ),
  );
}

/// The Field keeps animating chrome, so frames are pumped, not settled.
Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// --- What the user sees -----------------------------------------------------

Finder get _fieldViewport => find.byType(InteractiveViewer);

Rect _viewportRect(WidgetTester tester) =>
    Offset.zero & tester.getSize(_fieldViewport);

/// The node bodies of the frame drawn for the current camera.
///
/// This is the measure the Field's existing camera-fit tests use
/// (constellation_field_phone_entry_camera_fit_test.dart): the viewport
/// overlay paints the node bodies from this frame, so it is where the user
/// sees each person, and its camera revision proves the frame was drawn for
/// the camera the Field holds now rather than an older one.
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

/// Every person on the Field, Bob included, is drawn fully inside the Field
/// viewport, with nobody having touched the camera or pressed fit-all.
void _expectEveryNodeInView(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String when,
}) {
  expect(tester.takeException(), isNull, reason: '$when: no Flutter errors');
  expect(cubit.state.field, isNotNull, reason: '$when: the Field has loaded');
  expect(
    cubit.graphController.userCameraInputRevision.value,
    0,
    reason: '$when: nobody moved the camera',
  );
  final viewport = _viewportRect(tester);
  expect(viewport.isEmpty, isFalse, reason: '$when: the viewport has a size');
  final bodies = _drawnBodies(tester, cubit);
  final scale = cubit.graphController.cameraScale;
  final missing = [
    for (final id in _everyNode)
      if (bodies[id] == null || !_inside(viewport, bodies[id]!))
        '$id ${bodies[id]}',
  ];
  expect(
    missing,
    isEmpty,
    reason:
        '$when: every node body lies inside the Field viewport $viewport '
        '(camera scale $scale); outside or not drawn: $missing',
  );
}

Matrix4 _camera(WidgetTester tester) => tester
    .widget<InteractiveViewer>(_fieldViewport)
    .transformationController!
    .value
    .clone();

/// The camera the window shows now is the one the Field's own fit-all
/// («Показать всё поле») gives for this window: automatic framing after a
/// resize goes through the same fit-all path, so the two are the same camera.
/// A camera kept from the previous window size is not. Presses the control,
/// so call it last.
Future<void> _expectCameraIsFitAllForThisWindow(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String when,
}) async {
  final control = find.byKey(TestIds.key(TestIds.constellationFitAll));
  expect(
    control.hitTestable(),
    findsOneWidget,
    reason: '$when: the fit-all control is on screen',
  );
  final scale = cubit.graphController.cameraScale;
  final translation = _camera(tester).getTranslation();

  await tester.tap(control);
  await _pumpFrames(tester, 30);

  final fitScale = cubit.graphController.cameraScale;
  final fitTranslation = _camera(tester).getTranslation();
  expect(
    scale,
    closeTo(fitScale, 0.01),
    reason: '$when: the camera scale $scale is the fit-all scale $fitScale',
  );
  expect(
    (translation - fitTranslation).length,
    lessThanOrEqualTo(8),
    reason:
        '$when: the camera position $translation is the fit-all position '
        '$fitTranslation',
  );
}

/// The two windows QA reloads the Field in.
const _surfaces = <String, Size>{
  '375×667 RU': kPhoneSurface,
  '1280×800': _desktopSurface,
};

void main() {
  group('A cold reload of the Field frames every node without fit-all', () {
    for (final MapEntry(key: name, value: surface) in _surfaces.entries) {
      testWidgets(
        '$name: the viewport has its size first and the people arrive later',
        (tester) async {
          final repository = await _repository(open: false);
          final cubit = _fieldCubit(repository);
          await _reloadOnField(tester, cubit, surface: surface);
          await _pumpFrames(tester, 20);
          expect(cubit.state.field, isNull, reason: 'the Field is loading');
          expect(
            cubit.fieldInitialFrameCompletedForTest,
            isFalse,
            reason: 'nothing framed while no person is placed',
          );
          // A fit-all attempt on the empty Field does not count as framing.
          cubit.fitWholeField(insets: EdgeInsets.zero);
          await _pumpFrames(tester, 10);
          expect(
            cubit.fieldInitialFrameCompletedForTest,
            isFalse,
            reason: 'a fit with no placed person does not frame the visit',
          );

          repository.release();
          await _pumpFrames(tester, 120);

          expect(cubit.graphController.canLayout, isTrue);
          expect(
            cubit.fieldInitialFrameCompletedForTest,
            isTrue,
            reason: 'framed once the people are placed',
          );
          _expectEveryNodeInView(tester, cubit, when: 'people arrived');
        },
      );

      testWidgets(
        '$name: the people arrive first and the viewport gets its size later',
        (tester) async {
          final cubit = _fieldCubit(await _repository(open: true));
          await cubit.stream.firstWhere((s) => s.field != null);
          await _reloadOnField(tester, cubit, surface: Size.zero);
          await _pumpFrames(tester, 20);
          expect(
            cubit.fieldInitialFrameCompletedForTest,
            isFalse,
            reason: 'nothing framed while the viewport has no size',
          );
          // A fit-all attempt into the zero-size viewport does not count.
          cubit.fitWholeField(insets: EdgeInsets.zero);
          await _pumpFrames(tester, 10);
          expect(
            cubit.fieldInitialFrameCompletedForTest,
            isFalse,
            reason: 'a fit into a zero-size viewport does not frame the visit',
          );

          await tester.binding.setSurfaceSize(surface);
          await _pumpFrames(tester, 120);

          expect(
            cubit.fieldInitialFrameCompletedForTest,
            isTrue,
            reason: 'framed once the viewport has its size',
          );
          _expectEveryNodeInView(tester, cubit, when: 'viewport sized');
        },
      );

      testWidgets(
        '$name: a fit attempted while the graph cannot lay out yet is not the '
        'initial frame; the Field is framed once it can',
        (tester) async {
          final cubit = _fieldCubit(await _repository(open: true));
          await cubit.stream.firstWhere((s) => s.field != null);
          // The Field's data is loaded but no map is mounted yet, so the
          // graph has nowhere to lay out.
          expect(
            cubit.graphController.canLayout,
            isFalse,
            reason: 'precondition: the graph cannot lay out before the map',
          );
          cubit.fitWholeField(insets: EdgeInsets.zero);
          expect(
            cubit.fieldInitialFrameCompletedForTest,
            isFalse,
            reason: 'a fit while the graph cannot lay out frames nothing',
          );

          await _reloadOnField(tester, cubit, surface: surface);
          await _pumpFrames(tester, 120);

          expect(cubit.graphController.canLayout, isTrue);
          expect(cubit.fieldInitialFrameCompletedForTest, isTrue);
          _expectEveryNodeInView(tester, cubit, when: 'graph laid out');
        },
      );

      testWidgets(
        '$name: the window grows to its real size after the people are '
        'placed in a smaller first viewport, and the Field is framed for the '
        'real size',
        (tester) async {
          final cubit = _fieldCubit(await _repository(open: true));
          await cubit.stream.firstWhere((s) => s.field != null);
          // The browser reports a small window first, then the real one.
          await _reloadOnField(tester, cubit, surface: const Size(320, 240));
          await _pumpFrames(tester, 30);
          expect(cubit.graphController.canLayout, isTrue);
          expect(
            cubit.fieldInitialFrameCompletedForTest,
            isTrue,
            reason:
                'the people are placed in a non-empty (small) viewport, so '
                'the first frame has run there',
          );
          _expectEveryNodeInView(tester, cubit, when: 'small first window');

          await tester.binding.setSurfaceSize(surface);
          await _pumpFrames(tester, 120);

          _expectEveryNodeInView(tester, cubit, when: 'real window size');
          await _expectCameraIsFitAllForThisWindow(
            tester,
            cubit,
            when: 'real window size',
          );
        },
      );
    }
  });

  group('Resizing the window with an untouched Field camera re-frames every '
      'node', () {
    for (final (from, to, fromName, toName) in [
      (_desktopSurface, kPhoneSurface, '1280×800', '375×667'),
      (kPhoneSurface, _desktopSurface, '375×667', '1280×800'),
    ]) {
      testWidgets('$fromName → $toName', (tester) async {
        final cubit = _fieldCubit(await _repository(open: true));
        await cubit.stream.firstWhere((s) => s.field != null);
        await _reloadOnField(tester, cubit, surface: from);
        await _pumpFrames(tester, 120);
        _expectEveryNodeInView(tester, cubit, when: 'before the resize');

        await tester.binding.setSurfaceSize(to);
        await _pumpFrames(tester, 120);

        _expectEveryNodeInView(tester, cubit, when: 'after the resize');
        await _expectCameraIsFitAllForThisWindow(
          tester,
          cubit,
          when: 'after the resize',
        );
      });
    }
  });

  group('A cold reload whose saved tag seating is read after the first layout '
      'frames every node once they are laid out', () {
    for (final MapEntry(key: name, value: surface) in _surfaces.entries) {
      testWidgets(
        '$name: a saved tag magnet read after the Field is on screen moves '
        'the tagged people, and the untouched camera frames them there',
        (tester) async {
          // Bob saved the «Работа» magnet far to the right and above him.
          final magnets = _GatedMagnetRepository(const [
            ConstellationTagMagnet(
              tagId: _workTag,
              xUnits: 14,
              yUnits: -10,
              revision: 1,
            ),
          ]);
          final cubit = _taggedFieldCubit(
            await _repository(open: true),
            magnets,
          );
          await cubit.stream.firstWhere((s) => s.field != null);
          await _reloadOnField(tester, cubit, surface: surface);
          await _pumpFrames(tester, 120);
          _expectEveryNodeInView(tester, cubit, when: 'before the magnet');
          final before = {
            for (final id in _workPeople)
              id: cubit.graphController.getPositionOrNullForId('fp:$id'),
          };

          magnets.release();
          await _pumpFrames(tester, 180);

          final moved = [
            for (final id in _workPeople)
              if ((cubit.graphController.getPositionOrNullForId('fp:$id')! -
                          before[id]!)
                      .distance >
                  1)
                id,
          ];
          expect(
            moved,
            isNotEmpty,
            reason: 'the magnet drew the tagged people to a new place',
          );
          _expectEveryNodeInView(tester, cubit, when: 'after the magnet');
        },
      );
    }
  });
}
