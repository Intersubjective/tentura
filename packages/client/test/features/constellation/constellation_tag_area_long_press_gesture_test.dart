import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_hull_layer.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_field_test_harness.dart';

/// Issue #1021 §Gesture — tag-area long press from empty hull space (#7abw.12).

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

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

/// Minimal anchor server (same shape as constellation_group_drag_test).
final class _Server implements ConstellationAnchorRepositoryPort {
  _Server([
    Map<ConstellationAnchorTarget, (double, double)> seeded = const {},
  ]) {
    for (final MapEntry(key: target, value: (x, y)) in seeded.entries) {
      anchors[target] = ConstellationAnchor(
        target: target,
        position: ConstellationAnchorPosition(
          xUnits: x,
          yUnits: y,
          coordinateSpaceVersion: 1,
        ),
        revision: _revision(revision),
        placedAt: DateTime.utc(2026, 10, 22),
      );
    }
  }

  int revision = 7;
  final anchors = <ConstellationAnchorTarget, ConstellationAnchor>{};
  final applies = <List<ConstellationAnchorApplyOp>>[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    applies.add(List.of(ops));
    for (final op in ops) {
      if (op.kind != ConstellationAnchorOpKind.upsert) continue;
      expect(
        ConstellationAnchorPosition.validate(
          xUnits: op.position!.xUnits,
          yUnits: op.position!.yUnits,
          coordinateSpaceVersion: op.position!.coordinateSpaceVersion,
        ),
        isA<ConstellationAnchorPositionValid>(),
        reason: '${op.target} written out of range',
      );
    }
    final before = revision;
    final results = <ConstellationAnchorOpResult>[];
    for (final op in ops) {
      revision++;
      switch (op.kind) {
        case ConstellationAnchorOpKind.delete:
          anchors.remove(op.target);
          results.add(
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: _revision(revision),
              target: op.target,
            ),
          );
        case ConstellationAnchorOpKind.upsert:
          final anchor = ConstellationAnchor(
            target: op.target,
            position: op.position!,
            revision: _revision(revision),
            placedAt: DateTime.utc(2026, 10, 22),
          );
          anchors[op.target] = anchor;
          results.add(
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: _revision(revision),
              target: op.target,
              anchor: anchor,
            ),
          );
      }
    }
    return ConstellationAnchorApplyResult(
      beforeRevision: _revision(before),
      afterRevision: _revision(revision),
      results: results,
    );
  }

  @override
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  }) => throw UnimplementedError();

  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) => throw UnimplementedError();

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) => throw UnimplementedError();
}

final class _Fields implements ConstellationRepositoryPort {
  _Fields(this.server, this.people);

  final _Server server;
  final List<ConstellationPerson> people;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 22),
    context: '',
    peers: people,
    edges: [
      for (final person in people)
        ConstellationTrustEdgeEntity(src: 'ego', dst: person.id, tier: 1),
    ],
    // No Posts: beacon nodes sit near authors and would overlap tag hull
    // «empty» spots, so [NodeDragGesture] would not start canvas long press.
    posts: [],
    anchorProjection: ConstellationAnchorProjection(
      revision: _revision(server.revision),
      anchors: server.anchors.values.toList(),
      pinnedPeers: [
        for (final person in people)
          if (server.anchors.containsKey(
            ConstellationAnchorTarget.person(person.id),
          ))
            person,
      ],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

const _ego = Profile(id: 'ego', displayName: 'Ego');
const _surface = Size(375, 667);

const _tagWorkshop = PersonTag(
  id: 'T-workshop',
  name: 'Workshop',
  glyph: 'W',
  color: 1,
  ord: 1,
);
const _tagGarden = PersonTag(
  id: 'T-garden',
  name: 'Garden',
  glyph: 'G',
  color: 2,
  ord: 2,
);

final _ann = ConstellationAnchorTarget.person('a');
final _bob = ConstellationAnchorTarget.person('b');

const _threePeople = [
  ConstellationPerson(id: 'a', displayName: 'Ann'),
  ConstellationPerson(id: 'b', displayName: 'Bob'),
  ConstellationPerson(id: 'c', displayName: 'Cat'),
];

Set<String> _peopleInTag(String tagId, List<PersonTagMembers> members) {
  for (final m in members) {
    if (m.tagId == tagId) {
      return m.personIds.toSet();
    }
  }
  return {};
}

List<Offset> _memberCentres(
  ConstellationCubit cubit,
  String tagId,
  List<PersonTagMembers> memberList,
) {
  final controller = cubit.graphController;
  return [
    for (final id in _peopleInTag(tagId, memberList))
      controller.getPositionOrNullForId('fp:$id')!,
  ];
}

Path _hullPath(
  ConstellationCubit cubit,
  String tagId,
  List<PersonTagMembers> memberList,
) => buildConstellationTagHullPath(_memberCentres(cubit, tagId, memberList));

Offset? _emptyPointInHull(
  WidgetTester tester,
  ConstellationCubit cubit,
  String tagId,
  List<PersonTagMembers> memberList, {
  String? alsoInsideTagId,
}) {
  final path = _hullPath(cubit, tagId, memberList);
  final alsoPath = alsoInsideTagId == null
      ? null
      : _hullPath(cubit, alsoInsideTagId, memberList);
  final bounds = path.getBounds().inflate(4);
  for (var y = bounds.top; y <= bounds.bottom; y += 6) {
    for (var x = bounds.left; x <= bounds.right; x += 6) {
      final point = Offset(x, y);
      if (!path.contains(point)) {
        continue;
      }
      if (alsoPath != null && !alsoPath.contains(point)) {
        continue;
      }
      if (cubit.mapNodeAtSceneCentre(point) != null) {
        continue;
      }
      return point;
    }
  }
  return null;
}

/// Scene → global: `NodeDragGesture`'s pointer listener uses this basis for
/// `event.localPosition` (`kGraphViewNodeDragPointerLayerKey`).
Offset _sceneToGlobal(WidgetTester tester, ConstellationCubit cubit, Offset scene) {
  final listener = find.descendant(
    of: find.byType(GraphView<NodeDetails, EdgeDetails>),
    matching: find.byKey(kGraphViewNodeDragPointerLayerKey),
  );
  expect(listener, findsOneWidget);
  final box = tester.renderObject<RenderBox>(listener);
  return box.localToGlobal(scene);
}

/// Mirrors [ConstellationBody] hull hit geometry for debugging / assertions.
void _expectTagHullAtScene(
  ConstellationCubit cubit,
  ConstellationTagLensCubit lens,
  PeopleTagsCase store,
  Offset scene,
  String? expectedTagId,
) {
  final field = cubit.state.field;
  expect(field, isNotNull);
  final fieldIds = <String>{
    for (final p in field!.peers) p.id,
    for (final p in field.resolvedAnchorProjection.pinnedPeers) p.id,
  };
  final hullHit = ConstellationTagHullHitTester(
        hitsMapNode: (scenePoint) {
          final node = cubit.mapNodeAtSceneCentre(scenePoint);
          if (node is FieldPersonNode && node.person.id == cubit.viewerId) {
            return false;
          }
          return node != null;
        },
      )..update(
        controller: cubit.graphController,
        tags: [
          for (final tag in store.tags)
            if (store.peopleInTag(tag.id).any(fieldIds.contains)) tag,
        ],
        selectedTagIds: lens.state.selectedOwn,
        peopleOf: store.peopleInTag,
      );
  final resolvedTagId = hullHit.tagHullAt(scene);
  expect(resolvedTagId, expectedTagId);
}

typedef _Harness = ({
  _Server server,
  ConstellationCubit cubit,
  ConstellationPlacementCase placement,
  ConstellationSelectionCubit selection,
  ConstellationTagLensCubit lens,
  PeopleTagsTestRig tags,
  List<PersonTagMembers> memberList,
});

Future<_Harness> _mount(
  WidgetTester tester, {
  Map<ConstellationAnchorTarget, (double, double)> seeded = const {},
  List<PersonTagMembers>? memberList,
}) async {
  final members = memberList ??
      const [
        PersonTagMembers(tagId: 'T-workshop', personIds: ['a', 'b']),
        PersonTagMembers(tagId: 'T-garden', personIds: ['a', 'b', 'c']),
      ];
  final repo = FakePeopleTagsRepository(
    tagList: const [_tagWorkshop, _tagGarden],
    memberList: members,
  );
  final rig = await PeopleTagsTestRig.create(repo);
  GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  addTearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  final server = _Server(seeded);
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    _Fields(server, _threePeople),
    accountId: 'ego',
    realtime: sync.case_,
  ).store;
  final placement = ConstellationPlacementCase(
    server,
    store,
    FakeClockPort(),
    FakeWakeUpPort(),
    realtime: sync.case_,
    env: const Env.fromEnvironment(),
    logger: Logger('TagAreaLongPressTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    placementCase: placement,
    viewer: _ego,
    ownTagIdsOf: rig.peopleTags.tagsOfPerson,
  );
  final selection = constellationSelectionForFieldBodyTests();
  final lens = ConstellationTagLensCubit(ownTagIdsOf: rig.peopleTags.tagsOfPerson);
  addTearDown(() async {
    await lens.close();
    await selection.close();
    await cubit.close();
    await placement.dispose();
    await sync.port.dispose();
  });
  await tester.runAsync(
    () => cubit.stream.firstWhere((state) => state.status is StateIsSuccess),
  );
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: _surface),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider<ConstellationSelectionCubit>.value(
                value: selection,
              ),
              BlocProvider<ConstellationTagLensCubit>.value(value: lens),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _StubContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: Scaffold(
              body: ConstellationBody(
                legendExpanded: false,
                onToggleLegend: () {},
                peopleTagsCase: rig.peopleTags,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pump();
  // [ConstellationSelectionLayers] box select treats Shift as «draw a box».
  // Stale modifier state from other tests would leave an opaque hit target on
  // the whole map and block empty-map canvas long press (#1021).
  HardwareKeyboard.instance.clearState();
  // Hull hit order: selected own tags paint above unselected; workshop must
  // win over the larger garden hull on shared empty space.
  lens.toggleOwn(_tagWorkshop.id);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  // Default camera can leave seeded anchors off-screen on 375×667; fit the
  // Workshop hull so empty-hull probes and synthetic pointers hit the graph.
  final workshopHull = _hullPath(cubit, _tagWorkshop.id, members);
  cubit.graphController.fitToRect(workshopHull.getBounds().inflate(140));
  await tester.pumpAndSettle();
  return (
    server: server,
    cubit: cubit,
    placement: placement,
    selection: selection,
    lens: lens,
    tags: rig,
    memberList: members,
  );
}

Future<void> _flushWrites(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets(
    'touch: hold empty Workshop hull then move writes a+b; undo clears anchors',
    (tester) async {
      final h = await _mount(tester);
      final empty = _emptyPointInHull(tester, h.cubit, 'T-workshop', h.memberList);
      expect(empty, isNotNull);
      _expectTagHullAtScene(
        h.cubit,
        h.lens,
        h.tags.peopleTags,
        empty!,
        'T-workshop',
      );
      final global = _sceneToGlobal(tester, h.cubit, empty);
      final roundTrip = h.cubit.graphController.globalToScene(global);
      expect(
        roundTrip,
        isNotNull,
        reason: 'global must map into scene for NodeDragGesture',
      );
      expect((roundTrip! - empty).distance, lessThan(2.0));

      final gesture = await tester.startGesture(global);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 2));
      await tester.pump();
      expect(h.cubit.state.tagAreaDragTagId, 'T-workshop');
      await gesture.moveBy(const Offset(50, 40));
      await tester.pump();
      await gesture.up();
      await _flushWrites(tester);

      expect(h.server.applies, isNotEmpty);
      final targets = {for (final op in h.server.applies.last) op.target};
      expect(targets, contains(_ann));
      expect(targets, contains(_bob));

      await tester.runAsync(() async {
        expect(await h.cubit.undoArrangement(), isTrue);
      });
      await _flushWrites(tester);
      expect(h.server.anchors.containsKey(_ann), isFalse);
      expect(h.server.anchors.containsKey(_bob), isFalse);
    },
  );

  testWidgets(
    'mouse: same empty-hull hold+move writes a+b; undo clears anchors',
    (tester) async {
      final h = await _mount(tester);
      final empty = _emptyPointInHull(tester, h.cubit, 'T-workshop', h.memberList);
      expect(empty, isNotNull);
      final global = _sceneToGlobal(tester, h.cubit, empty!);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: global);
      await tester.pump();
      await gesture.down(global);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 2));
      await tester.pump();
      expect(h.cubit.state.tagAreaDragTagId, 'T-workshop');
      await gesture.moveBy(const Offset(50, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await _flushWrites(tester);

      expect(h.server.applies, isNotEmpty);
      final targets = {for (final op in h.server.applies.last) op.target};
      expect(targets, contains(_ann));
      expect(targets, contains(_bob));

      await tester.runAsync(() async {
        expect(await h.cubit.undoArrangement(), isTrue);
      });
      await _flushWrites(tester);
      expect(h.server.anchors.containsKey(_ann), isFalse);
      expect(h.server.anchors.containsKey(_bob), isFalse);
    },
  );

  testWidgets(
    'quick pan from same empty spot does not write placements',
    (tester) async {
      final h = await _mount(tester);
      final empty = _emptyPointInHull(tester, h.cubit, 'T-workshop', h.memberList);
      expect(empty, isNotNull);
      final global = _sceneToGlobal(tester, h.cubit, empty!);

      final gesture = await tester.startGesture(global);
      await gesture.moveBy(const Offset(80, 60));
      await tester.pump();
      await gesture.up();
      await tester.pump(kLongPressTimeout);
      await _flushWrites(tester);

      expect(h.server.applies, isEmpty);
    },
  );

  testWidgets(
    'mouse long press on person node lifts only that node',
    (tester) async {
      final h = await _mount(tester);
      enterConstellationArrangingForTests(h.selection);
      await tester.pump(const Duration(milliseconds: 200));

      final annScene = h.cubit.graphController.getPositionOrNullForId('fp:a');
      expect(annScene, isNotNull, reason: 'Ann must be laid out');
      final annCentre = _sceneToGlobal(tester, h.cubit, annScene!);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: annCentre);
      await tester.pump();
      await gesture.down(annCentre);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 2));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await _flushWrites(tester);

      expect(h.server.applies, hasLength(1));
      final targets = {for (final op in h.server.applies.single) op.target};
      expect(targets, {_ann});
    },
  );

  testWidgets(
    'overlapping hulls: selected own-tag wins for empty-space drag start',
    (tester) async {
      final h = await _mount(tester);

      final empty = _emptyPointInHull(
        tester,
        h.cubit,
        _tagWorkshop.id,
        h.memberList,
        alsoInsideTagId: _tagGarden.id,
      );
      expect(empty, isNotNull);
      final global = _sceneToGlobal(tester, h.cubit, empty!);

      final gesture = await tester.startGesture(global);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 2));
      expect(h.cubit.state.tagAreaDragTagId, _tagWorkshop.id);
      await gesture.up();
      await tester.pump();
      h.cubit.cancelPlacement();
      await tester.pump();
    },
  );

  testWidgets('outside Arranging: tag-area hold still runs', (tester) async {
    final h = await _mount(tester);
    applyConstellationTouchDragTestPolicy(h.selection, touchNodeDragLocked: true);

    final empty = _emptyPointInHull(tester, h.cubit, 'T-workshop', h.memberList);
    expect(empty, isNotNull);
    final global = _sceneToGlobal(tester, h.cubit, empty!);

    final gesture = await tester.startGesture(global);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 2));
    expect(h.cubit.state.tagAreaDragTagId, 'T-workshop');
    await gesture.up();
    await tester.pump();
    h.cubit.cancelPlacement();
  });

}
