// «Rearrange everyone» on the Field, with the viewer's own people tags loaded
// the way the app loads them: each tag gets one compact area, the areas of
// two tags do not overlap, and after «Done» leaves Arranging every tagged
// person is still drawn inside the Field viewport. Checked on desktop
// (1200×900) and on the narrow phone (375×667), the phone in Russian.
//
// Roster: tag A = Boris, Dima; tag B = Nova, Carol; a third own tag C =
// Boris only (so Boris carries two tags); Ulya and Uma carry no tag. No tag
// magnets.
@TestOn('vm')
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/constellation_pin_position.dart';
import 'package:tentura/features/constellation/domain/constellation_rearrange_all.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_scene_controller.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_rearrange_preview_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_row.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/rearrange_preview_scheduler.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_field_test_harness.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
const _desktop = Size(1200, 900);
const _spacing = 16.0;

const _people = {
  'boris': 'Boris',
  'dima': 'Dima',
  'nova': 'Nova',
  'carol': 'Carol',
  'ulya': 'Ulya',
  'uma': 'Uma',
};
const _tagged = ['boris', 'dima', 'nova', 'carol'];

const _tagA = PersonTag(id: 'T-a', name: 'A', glyph: 'A', color: 0, ord: 0);
const _tagB = PersonTag(id: 'T-b', name: 'B', glyph: 'B', color: 1, ord: 1);
const _tagC = PersonTag(
  id: 'T-c',
  name: 'Third tag',
  glyph: 'C',
  color: 2,
  ord: 2,
);
const _memberships = [
  PersonTagMembers(tagId: 'T-a', personIds: ['boris', 'dima']),
  PersonTagMembers(tagId: 'T-b', personIds: ['nova', 'carol']),
  PersonTagMembers(tagId: 'T-c', personIds: ['boris']),
];

String _nodeId(String personId) =>
    '${TenturaGraphNodeKind.fieldPerson}:$personId';

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

final _fieldWire = {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-09T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': [..._people.keys],
    'peers': [
      _peer(_ego.id, _ego.displayName),
      for (final MapEntry(:key, :value) in _people.entries) _peer(key, value),
    ],
    'edges': [
      for (final id in _people.keys)
        {
          '__typename': 'v2_ConstellationEdge',
          'src': _ego.id,
          'dst': id,
          'tier': 1,
        },
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

/// The QA roster as the server sends it, through the real repository mapping.
Future<ConstellationField> _fieldFromWire() async {
  late final ConstellationField field;
  await withRemoteWire(
    {'ConstellationFieldFetch': _fieldWire},
    [],
    (remote) async {
      field = await ConstellationRepository(remote).fetch();
    },
  );
  return field;
}

final class _FieldRepository implements ConstellationRepositoryPort {
  _FieldRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

/// Server side of the viewer's anchors: keeps every batch Apply writes.
final class _AnchorServer implements ConstellationWriteFake {
  final events = <String>[];
  final _anchors = <ConstellationAnchorTarget, ConstellationAnchorPosition>{};
  var _revision = BigInt.from(10);

  @override
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  }) async {
    events.add('save:$reason');
    return 'snap';
  }

  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) async => 'snap2';

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) => throw UnimplementedError('reset is not used by this test');

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    events.add('apply');
    final before = ConstellationAnchorRevision(_revision);
    final results = <ConstellationAnchorOpResult>[];
    for (final op in ops) {
      _revision += BigInt.one;
      final revision = ConstellationAnchorRevision(_revision);
      if (op.kind == ConstellationAnchorOpKind.delete) {
        _anchors.remove(op.target);
      } else {
        _anchors[op.target] = op.position!;
      }
      results.add(
        ConstellationAnchorOpResult(
          clientOpId: op.clientOpId,
          status: ConstellationAnchorOpStatus.ok,
          resultingTargetRevision: revision,
          target: op.target,
          anchor: op.kind == ConstellationAnchorOpKind.delete
              ? null
              : ConstellationAnchor(
                  target: op.target,
                  position: op.position!,
                  revision: revision,
                  placedAt: DateTime.utc(2026, 11, 9, 1),
                ),
        ),
      );
    }
    return ConstellationAnchorApplyResult(
      beforeRevision: before,
      afterRevision: ConstellationAnchorRevision(_revision),
      results: results,
    );
  }

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) => throw UnimplementedError('single writes are not used by this test');

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) => throw UnimplementedError('single writes are not used by this test');
}

final class _FakeForwardRepository implements ForwardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubContextCubit extends Cubit<GraphPersonContextState>
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

/// Runs the whole preview job at once, so Apply is ready on the next frame.
final class _ImmediateRearrangePreviewScheduler
    implements RearrangePreviewScheduler {
  @override
  void start({
    required bool Function(int units) step,
    required void Function() onComplete,
  }) {
    while (!step(1)) {}
    onComplete();
  }

  @override
  void cancel() {}

  @override
  void cancelJob(void Function() onComplete) {}

  @override
  void dispose() {}
}

typedef _Harness = ({
  ConstellationCubit cubit,
  ConstellationSelectionCubit selection,
  PeopleTagsCase tags,
});

/// The Field with the Arranging app bar above it, the viewer's own tags in
/// the people-tags store (registered in GetIt, as the app does).
Future<_Harness> _openField(
  WidgetTester tester, {
  required Size surface,
  Locale locale = const Locale('en'),
}) async {
  final rig = await PeopleTagsTestRig.create(
    FakePeopleTagsRepository(
      tagList: const [_tagA, _tagB, _tagC],
      memberList: _memberships,
    ),
  );
  GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  addTearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  final field = await _fieldFromWire();
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    _FieldRepository(field),
    accountId: _ego.id,
    realtime: sync.case_,
  ).store;
  final placement = ConstellationPlacementCase(
    _AnchorServer(),
    store,
    FakeClockPort(DateTime.utc(2026, 11, 9)),
    FakeWakeUpPort(),
    realtime: sync.case_,
    env: const Env.fromEnvironment(),
    logger: Logger('RearrangeEveryoneTagAreasFieldTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    anchorCase: ConstellationAnchorCase(
      env: const Env.fromEnvironment(),
      logger: Logger('RearrangeEveryoneTagAreasFieldTest'),
    ),
    placementCase: placement,
    viewer: _ego,
    forwardCase: buildTestForwardCase(_FakeForwardRepository()),
    ownTagIdsOf: rig.peopleTags.tagsOfPerson,
    peopleInTag: rig.peopleTags.peopleInTag,
    loadOnCreate: false,
    scene: ConstellationSceneController(
      rearrangePreviewScheduler: _ImmediateRearrangePreviewScheduler(),
    ),
  );
  await cubit.load();
  final selection = constellationSelectionForFieldBodyTests();
  final lens = ConstellationTagLensCubit(
    ownTagIdsOf: rig.peopleTags.tagsOfPerson,
  );

  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await lens.close();
    await selection.close();
    await cubit.close();
    await placement.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ConstellationCubit>.value(value: cubit),
            BlocProvider<ConstellationSelectionCubit>.value(value: selection),
            BlocProvider<ConstellationTagLensCubit>.value(value: lens),
            BlocProvider<GraphPersonContextCubit>(
              create: (_) => _StubContextCubit(),
            ),
            BlocProvider<ScreenCubit>(
              create: (_) => ScreenCubit(FakeUiEffectPort()),
            ),
          ],
          child: Builder(
            builder: (context) => Scaffold(
              appBar: TenturaTopBar.of(
                context,
                title: const SizedBox.shrink(),
                row: ConstellationAppBarRow(
                  legendExpanded: false,
                  onToggleLegend: () {},
                ),
              ),
              body: ConstellationBody(
                legendExpanded: false,
                onToggleLegend: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _pumpFrames(tester, 25);
  await stabilizeConstellationFieldChromeForTests(tester, cubit);
  for (final id in _people.keys) {
    expect(
      cubit.graphController.getPositionOrNullForId(_nodeId(id)),
      isNotNull,
      reason: '$id is on the Field before rearranging',
    );
  }
  return (cubit: cubit, selection: selection, tags: rig.peopleTags);
}

/// The Field keeps animating chrome, so frames are pumped, not settled.
Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The rearrangement «Rearrange everyone» previews for the Field as it
/// stands now, rebuilt from the same input the cubit builds (composition,
/// rendered node sizes, spacing 16, footprints, the viewer's own tags). Call
/// it while the preview is shown; [_rearrangeEveryoneAndApply] and
/// [_layoutToSceneShift] check it is the arrangement Apply really uses.
ConstellationRearrangement _rebuiltRearrangement(
  ConstellationCubit cubit,
  PeopleTagsCase tags,
) {
  final composition = cubit.state.composition!;
  final input = layoutInputFromComposition(
    viewerId: _ego.id,
    composition: composition,
    labelPlan: composition.labelPlan,
    nodeSizes: _nodeSizes(cubit),
    spacing: _spacing,
    footprints: cubit.layoutFootprints,
    rearrangeOwnTagPeopleByTagId: rearrangeOwnTagPeopleFromComposition(
      viewerId: _ego.id,
      composition: composition,
      ownTagIdsOf: tags.tagsOfPerson,
    ),
  );
  return computeConstellationRearrangeAll(input);
}

Map<String, ({double width, double height})> _nodeSizes(
  ConstellationCubit cubit,
) => {
  for (final MapEntry(:key, :value)
      in cubit.graphController.renderSnapshot.topology.nodesById.entries)
    tenturaLayoutDomainId(key): (
      width: value.size.width,
      height: value.size.height,
    ),
};

/// Tag-area radius: 2.5 × √members × (largest member node + spacing).
double _radius(ConstellationCubit cubit, List<String> members) {
  final sizes = _nodeSizes(cubit);
  var cell = 0.0;
  for (final id in members) {
    final size = sizes[id]!;
    cell = math.max(cell, math.max(size.width, size.height) + _spacing);
  }
  return 2.5 * math.sqrt(members.length) * cell;
}

/// Scene position of a person's node (the layout's own coordinate space).
Offset _scenePosition(ConstellationCubit cubit, String personId) =>
    cubit.graphController.getPositionForId(_nodeId(personId));

/// Opens «Rearrange everyone», rebuilds the previewed arrangement while the
/// preview is shown, taps Apply and returns that arrangement.
Future<ConstellationRearrangement> _rearrangeEveryoneAndApply(
  WidgetTester tester,
  _Harness h,
  String rearrangeLabel,
) async {
  await tapConstellationArrangeOverflowAction(tester, rearrangeLabel);
  final preview = h.cubit.state.rearrangePreview;
  expect(preview, isNotNull, reason: 'preview is shown');
  final rebuilt = _rebuiltRearrangement(h.cubit, h.tags);

  // The pins the Apply path is about to write are exactly the rebuilt
  // arrangement's positions, so the rebuilt tag centres are the ones Apply
  // uses, not a parallel derivation.
  expect(
    preview!.pinnedWrites.keys.toSet(),
    containsAll([
      for (final id in _tagged) ConstellationAnchorTarget.person(id),
    ]),
    reason: 'Apply pins every tagged person the tag stage seats',
  );
  for (final MapEntry(:key, :value) in preview.pinnedWrites.entries) {
    final point = rebuilt.layout.positions[key.id];
    expect(point, isNotNull, reason: '${key.id} is in the rebuilt layout');
    expect(
      value,
      constellationPointToV1Anchor(point!),
      reason: '${key.id}: Apply writes the rebuilt arrangement',
    );
  }

  final apply = find.byKey(const Key('constellation-rearrange-apply'));
  expect(apply, findsOneWidget, reason: 'the preview offers Apply');
  // The Field's top chrome is a capped strip that scrolls under the Arranging
  // toolbar; on a narrow phone the preview bar can sit below its fold, so
  // scroll Apply up to the strip's lower edge, as a user would, first.
  await Scrollable.ensureVisible(tester.element(apply), alignment: 1);
  await _pumpFrames(tester, 5);
  await tester.tap(apply);
  await _pumpFrames(tester, 40);
  expect(h.cubit.state.rearrangePreview, isNull, reason: 'Apply was taken');
  return rebuilt;
}

/// Maps the rebuilt arrangement (layout coordinates) into the Field's scene
/// coordinates, the frame `graphController` positions are in.
///
/// Apply's contract (computeConstellationRearrangeAll: "`layout` is exactly
/// what Apply produces") is that the Field shows every person where that
/// layout puts them. The scene may sit at its own offset from the layout, so
/// the mapping is the mean translation from layout to applied scene positions;
/// every person must then land within 1 px of their mapped place, else the
/// rebuilt tag centres would not describe the applied Field.
Offset _layoutToSceneShift(
  ConstellationCubit cubit,
  ConstellationRearrangement rebuilt,
) {
  var sum = Offset.zero;
  for (final id in _people.keys) {
    final laid = rebuilt.layout.positions[id]!;
    sum += _scenePosition(cubit, id) - Offset(laid.x, laid.y);
  }
  final shift = sum / _people.length.toDouble();
  for (final id in _people.keys) {
    final laid = rebuilt.layout.positions[id]!;
    final mapped = Offset(laid.x, laid.y) + shift;
    final shown = _scenePosition(cubit, id);
    expect(
      (shown - mapped).distance,
      lessThan(1),
      reason:
          '$id is shown at $shown, where the applied arrangement puts it '
          '($mapped in scene coordinates)',
    );
  }
  return shift;
}

/// On the Field's applied positions (scene coordinates throughout): tag B
/// (Nova, Carol) is one compact area and does not overlap tag A.
void _expectCompactSeparateAreas(
  ConstellationCubit cubit,
  ConstellationRearrangement rebuilt,
) {
  final shift = _layoutToSceneShift(cubit, rebuilt);
  final rA = _radius(cubit, const ['boris', 'dima']);
  final rB = _radius(cubit, const ['nova', 'carol']);
  final layoutA = rebuilt.tagCentres[_tagA.id];
  final layoutB = rebuilt.tagCentres[_tagB.id];
  expect(layoutA, isNotNull, reason: 'tag A gets an area');
  expect(layoutB, isNotNull, reason: 'tag B gets an area');
  final cA = Offset(layoutA!.x, layoutA.y) + shift;
  final cB = Offset(layoutB!.x, layoutB.y) + shift;

  final dima = _scenePosition(cubit, 'dima');
  final nova = _scenePosition(cubit, 'nova');
  final carol = _scenePosition(cubit, 'carol');
  expect(
    (nova - carol).distance,
    lessThan(rB),
    reason: 'Nova and Carol stand together in tag B’s area on the Field',
  );
  expect(
    (cA - cB).distance,
    greaterThan(rA + rB + _spacing),
    reason: 'tag A and tag B areas are apart, with a gap between them',
  );
  // The centres describe the applied Field: each tag's single-tag members
  // are shown inside their own area and outside the other one.
  for (final (id, at) in [('nova', nova), ('carol', carol)]) {
    expect(
      (at - cB).distance,
      lessThanOrEqualTo(rB + 1),
      reason: '$id is shown inside tag B’s area',
    );
    expect(
      (at - cA).distance,
      greaterThan(rA),
      reason: '$id is shown outside tag A’s area',
    );
  }
  expect(
    (dima - cA).distance,
    lessThanOrEqualTo(rA + 1),
    reason: 'Dima is shown inside tag A’s area',
  );
  expect(
    (dima - cB).distance,
    greaterThan(rB),
    reason: 'Dima is shown outside tag B’s area',
  );
}

/// Every tagged person's node centre is on screen inside the visible Field.
///
/// Frame of reference: the drawn frame's `bodies` are in the Field
/// viewport's local coordinates (scene → `sceneToViewportLocal`), and the
/// [ConstellationViewportOverlay] that holds them covers the Field viewport
/// ([InteractiveViewer]) exactly; both are checked. Each centre is mapped to
/// global coordinates through the overlay's render box and must lie
/// - inside the viewport less the map chrome the Field reports for its camera
///   (`fieldCameraViewportSnapshotForTest`), and
/// - below the app bar, and
/// - where a hit test reaches the Field, not the app bar or any top chrome
///   (tag row, toolbars, preview bar) drawn over it.
///
/// The person's node widget itself (Key `graph.node.<id>`, found by finder,
/// centre in global coordinates) must meet the same three conditions, so a
/// Field whose drawn frame is right but whose node widgets are off screen
/// fails too.
void _expectTaggedPeopleOnScreen(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String when,
}) {
  final viewerFinder = find.byType(InteractiveViewer);
  final overlayFinder = find.byType(ConstellationViewportOverlay);
  final viewerBox = tester.renderObject<RenderBox>(viewerFinder);
  final overlayBox = tester.renderObject<RenderBox>(overlayFinder);
  final viewerGlobal = viewerBox.localToGlobal(Offset.zero) & viewerBox.size;
  final overlayGlobal = overlayBox.localToGlobal(Offset.zero) & overlayBox.size;
  expect(
    overlayGlobal,
    viewerGlobal,
    reason: '$when: the drawn frame covers the Field viewport exactly',
  );

  final insets = cubit.fieldCameraViewportSnapshotForTest;
  final visibleField = insets.deflateRect(viewerGlobal);
  final appBarBottom = tester
      .getRect(find.byType(ConstellationAppBarRow))
      .bottom;

  final frame = tester
      .widget<ConstellationViewportOverlay>(overlayFinder)
      .frameHolder
      .frame;
  expect(frame, isNotNull, reason: '$when: the Field has drawn a frame');
  expect(
    frame!.cameraRevision,
    cubit.graphController.cameraRevision.value,
    reason: '$when: the drawn frame belongs to the current camera',
  );

  final coveringChrome = <RenderObject>[
    tester.renderObject(find.byType(ConstellationAppBarRow)),
    for (final finder in [
      find.byKey(const Key('constellation.arranging.toolbar')),
      find.byType(ConstellationRearrangePreviewBar),
      find.byType(ConstellationTagRow),
    ])
      for (final element in finder.evaluate()) element.renderObject!,
  ];

  void expectVisible(String where, Offset centre) {
    expect(
      visibleField.contains(centre),
      isTrue,
      reason: '$when: $where lies inside the visible Field $visibleField',
    );
    expect(
      centre.dy,
      greaterThan(appBarBottom),
      reason: '$when: $where is below the app bar (bottom $appBarBottom)',
    );
    final hit = tester.hitTestOnBinding(centre);
    final targets = [for (final entry in hit.path) entry.target];
    expect(
      targets.contains(viewerBox) || targets.contains(overlayBox),
      isTrue,
      reason: '$when: a tap on $where reaches the Field',
    );
    for (final chrome in coveringChrome) {
      expect(
        targets.contains(chrome),
        isFalse,
        reason: '$when: $where is not covered by ${chrome.runtimeType}',
      );
    }
  }

  for (final id in _tagged) {
    final scale = cubit.graphController.cameraScale;
    final body = frame.bodies[_nodeId(id)];
    expect(body, isNotNull, reason: '$when: $id is drawn on the Field');
    expectVisible(
      '$id drawn body centre (scale $scale)',
      overlayBox.localToGlobal(body!.center),
    );

    final widget = find.byKey(TestIds.key(TestIds.graphNode(id)));
    expect(widget, findsOneWidget, reason: '$when: $id node widget is built');
    expectVisible(
      '$id node widget centre (scale $scale)',
      tester.getCenter(widget),
    );
  }
}

void main() {
  group(
    'Rearrange everyone on the Field gives each tag its own compact area',
    () {
      testWidgets(
        'desktop: after Apply, tag B is compact and apart from tag A',
        (
          tester,
        ) async {
          final h = await _openField(tester, surface: _desktop);

          final rebuilt = await _rearrangeEveryoneAndApply(
            tester,
            h,
            L10nEn().constellationRearrangeEveryone,
          );

          _expectCompactSeparateAreas(h.cubit, rebuilt);
        },
      );

      testWidgets('phone: after Apply, tag B is compact and apart from tag A', (
        tester,
      ) async {
        final h = await _openField(tester, surface: kPhoneSurface);

        final rebuilt = await _rearrangeEveryoneAndApply(
          tester,
          h,
          L10nEn().constellationRearrangeEveryone,
        );

        _expectCompactSeparateAreas(h.cubit, rebuilt);
      });
    },
  );

  group('After Rearrange everyone, Done leaves Arranging with the people in '
      'view', () {
    testWidgets('desktop: Done closes Arranging and every tagged person is '
        'drawn inside the Field', (tester) async {
      final h = await _openField(tester, surface: _desktop);
      final en = L10nEn();

      await _rearrangeEveryoneAndApply(
        tester,
        h,
        en.constellationRearrangeEveryone,
      );
      expect(find.text(en.constellationArrangingTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('constellation.arranging.done')));
      await _pumpFrames(tester, 40);

      expect(h.selection.state.arranging, isFalse);
      expect(find.text(en.constellationArrangingTitle), findsNothing);
      _expectTaggedPeopleOnScreen(tester, h.cubit, when: 'after Done');
    });

    testWidgets('RU phone: «Готово» closes Arranging and every tagged person '
        'is drawn inside the Field', (tester) async {
      final h = await _openField(
        tester,
        surface: kPhoneSurface,
        locale: const Locale('ru'),
      );
      final ru = L10nRu();

      await _rearrangeEveryoneAndApply(
        tester,
        h,
        ru.constellationRearrangeEveryone,
      );
      expect(find.text(ru.constellationArrangingTitle), findsOneWidget);
      final done = find.byKey(const Key('constellation.arranging.done'));
      expect(
        find.descendant(of: done, matching: find.text('Готово')),
        findsOneWidget,
      );
      await tester.tap(done);
      await _pumpFrames(tester, 40);

      expect(h.selection.state.arranging, isFalse);
      expect(find.text(ru.constellationArrangingTitle), findsNothing);
      _expectTaggedPeopleOnScreen(tester, h.cubit, when: 'after «Готово»');
    });
  });
}
