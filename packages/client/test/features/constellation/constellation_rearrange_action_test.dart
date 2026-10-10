import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/test_realtime_sync.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_forward_case.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 9, 11, 12);

ConstellationField _field({
  BigInt? revision,
  List<ConstellationAnchor> anchors = const [],
  List<ConstellationPerson> peers = const [],
  List<ConstellationPerson>? pinnedPeers,
  List<ConstellationRequest> requests = const [],
  List<ConstellationRequest>? pinnedRequests,
  List<ConstellationTrustEdgeEntity> edges = const [],
  List<ConstellationPerson> supportPeers = const [],
  List<ConstellationTrustEdgeEntity> supportEdges = const [],
  List<String> serverFilteredBeaconIds = const [],
}) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: peers,
  requests: requests,
  edges: edges,
  anchorProjection: ConstellationAnchorProjection(
    revision: ConstellationAnchorRevision(revision ?? BigInt.one),
    anchors: anchors,
    pinnedPeers: pinnedPeers ?? peers,
    pinnedRequests: pinnedRequests ?? requests,
    supportPeers: supportPeers,
    supportEdges: supportEdges,
    serverFilteredBeaconIds: serverFilteredBeaconIds,
    serverFilteredBeaconCount: serverFilteredBeaconIds.length,
  ),
);

final class _HarnessFieldRepository implements ConstellationRepositoryPort {
  _HarnessFieldRepository(this.fields);

  final List<ConstellationField> fields;
  int fetchCount = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetchCount++;
    final index = (fetchCount - 1).clamp(0, fields.length - 1);
    return fields[index];
  }
}

final class _HarnessAnchorRepository
    implements ConstellationWriteFake {
  int applyCount = 0;
  int upsertCount = 0;
  int deleteCount = 0;
  ConstellationAnchorPosition? lastPosition;
  Completer<void>? upsertHold;
  Error? upsertError;

  final _confirmedAnchors = <ConstellationAnchorTarget, ConstellationAnchor>{};
  var _applyRevision = BigInt.zero;

  /// The anchor positions this repository currently holds as confirmed.
  Map<ConstellationAnchorTarget, ConstellationAnchorPosition>
  get confirmedPositions => {
    for (final entry in _confirmedAnchors.entries)
      entry.key: entry.value.position,
  };

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    applyCount++;
    final before = ConstellationAnchorRevision(_applyRevision);
    final results = <ConstellationAnchorOpResult>[];
    for (final op in ops) {
      final revision = op.kind == ConstellationAnchorOpKind.delete
          ? (await delete(target: op.target)).revision
          : (await upsert(target: op.target, position: op.position!)).revision;
      _applyRevision = _applyRevision > revision.value
          ? _applyRevision
          : revision.value;
      if (op.kind == ConstellationAnchorOpKind.delete) {
        _confirmedAnchors.remove(op.target);
      } else {
        _confirmedAnchors[op.target] = ConstellationAnchor(
          target: op.target,
          position: op.position!,
          revision: revision,
          placedAt: DateTime.utc(2026, 9, 11, 1),
        );
      }
      results.add(
        ConstellationAnchorOpResult(
          clientOpId: op.clientOpId,
          status: ConstellationAnchorOpStatus.ok,
          resultingTargetRevision: revision,
          target: op.target,
          anchor: op.kind == ConstellationAnchorOpKind.delete
              ? null
              : _confirmedAnchors[op.target],
        ),
      );
    }
    final after = ConstellationAnchorRevision(_applyRevision);
    return ConstellationAnchorApplyResult(
      beforeRevision: before,
      afterRevision: after,
      results: results,
    );
  }

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    upsertCount++;
    lastPosition = position;
    await upsertHold?.future;
    if (upsertError != null) {
      throw upsertError!;
    }
    return ConstellationAnchorUpsertResult(
      anchor: ConstellationAnchor(
        target: target,
        position: position,
        revision: ConstellationAnchorRevision(BigInt.two),
        placedAt: DateTime.utc(2026, 9, 11, 1),
      ),
      revision: ConstellationAnchorRevision(BigInt.two),
    );
  }

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) async {
    deleteCount++;
    return ConstellationAnchorDeleteResult(
      target: target,
      revision: ConstellationAnchorRevision(BigInt.from(3)),
    );
  }
}

final class _FakeForwardRepository implements ForwardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  _StubContextCubit() : super(const GraphPersonContextState());

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

Future<
  ({
    ConstellationCubit cubit,
    _HarnessFieldRepository fieldRepo,
    _HarnessAnchorRepository anchorRepo,
  })
>
_harness({
  List<ConstellationField>? fields,
}) async {
  final fieldRepo = _HarnessFieldRepository(
    fields ??
        [
          _field(
            peers: const [
              ConstellationPerson(id: 'p1', displayName: 'Peer one'),
              ConstellationPerson(id: 'p2', displayName: 'Peer two'),
              ConstellationPerson(id: 'p3', displayName: 'Peer three'),
            ],
            requests: const [
              ConstellationRequest(
                id: 'req-1',
                authorId: 'p1',
                title: 'Need tools',
                status: 0,
              ),
              ConstellationRequest(
                id: 'req-2',
                authorId: 'p2',
                title: 'Need a ladder',
                status: 0,
              ),
            ],
          ),
        ],
  );
  final anchorRepo = _HarnessAnchorRepository();
  final anchorCase = ConstellationAnchorCase(
    env: const Env.fromEnvironment(),
    logger: Logger('ConstellationRearrangeActionTest'),
  );
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    fieldRepo,
    accountId: 'ego',
    realtime: sync.case_,
  ).store;
  final cubit = ConstellationCubit(
    case_: store,
    anchorCase: anchorCase,
    placementCase: ConstellationPlacementCase(
      anchorRepo,
      store,
      FakeClockPort(),
      FakeWakeUpPort(),
      realtime: sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationRearrangeActionTest'),
    ),
    viewer: _ego,
    forwardCase: buildTestForwardCase(_FakeForwardRepository()),
    loadOnCreate: false,
  );
  await cubit.load();
  return (cubit: cubit, fieldRepo: fieldRepo, anchorRepo: anchorRepo);
}

Future<void> _pumpShell(
  WidgetTester tester,
  ConstellationCubit cubit, {
  Size surface = const Size(1200, 900),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(surface);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ConstellationCubit>.value(value: cubit),
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
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Scene position of every graph node, keyed by its graph id.
Map<String, Offset> _allNodePositions(ConstellationCubit cubit) => {
  for (final node in cubit.graphController.nodes)
    tenturaGraphNodeId(node): cubit.graphController.getPositionForId(
      tenturaGraphNodeId(node),
    ),
};

/// Anchor position the cubit currently shows for every anchored target.
Map<ConstellationAnchorTarget, ConstellationAnchorPosition> _shownAnchors(
  ConstellationCubit cubit,
) => {
  for (final anchor in cubit.state.composition!.anchorOverlay.anchors)
    anchor.target: anchor.position,
};

/// A field in which [placements] are already stored as anchors at load time.
ConstellationField _fieldWithPlacements(
  Map<ConstellationAnchorTarget, ConstellationAnchorPosition> placements,
) => _field(
  // Pinned entities default to the loaded ones, as in a session's own first
  // load: a settled placement merges into them rather than replacing them.
  peers: const [
    ConstellationPerson(id: 'p1', displayName: 'Peer one'),
    ConstellationPerson(id: 'p2', displayName: 'Peer two'),
    ConstellationPerson(id: 'p3', displayName: 'Peer three'),
  ],
  requests: const [
    ConstellationRequest(
      id: 'req-1',
      authorId: 'p1',
      title: 'Need tools',
      status: 0,
    ),
    ConstellationRequest(
      id: 'req-2',
      authorId: 'p2',
      title: 'Need a ladder',
      status: 0,
    ),
  ],
  anchors: [
    for (final entry in placements.entries)
      ConstellationAnchor(
        target: entry.key,
        position: entry.value,
        revision: ConstellationAnchorRevision(BigInt.one),
        placedAt: DateTime.utc(2026, 9, 11),
      ),
  ],
);

/// A field in which the user already has two nodes placed at load time.
ConstellationField _fieldWithStoredPlacements() => _fieldWithPlacements({
  ConstellationAnchorTarget.person('p1'): const ConstellationAnchorPosition(
    xUnits: 1,
    yUnits: 2,
    coordinateSpaceVersion: 1,
  ),
  ConstellationAnchorTarget.beacon('req-2'): const ConstellationAnchorPosition(
    xUnits: 3,
    yUnits: 4,
    coordinateSpaceVersion: 1,
  ),
});

/// Positions of every node in a fresh session that loads [placements] as
/// stored anchors and plans in full: the layout engine's plan for that input,
/// with no prior layout of this session to stay close to.
Future<Map<String, Offset>> _positionsOfFreshLoadWith(
  WidgetTester tester,
  Map<ConstellationAnchorTarget, ConstellationAnchorPosition> placements,
) async {
  // A fresh session: unmount whatever an earlier session left on screen, so
  // the body's per-session footprint sync runs again for this cubit.
  await tester.pumpWidget(const SizedBox());
  final harness = await _harness(fields: [_fieldWithPlacements(placements)]);
  try {
    await _pumpShell(tester, harness.cubit);
    // The body's footprint metrics reach the cubit after its first layout, so
    // the plan with them is the first full plan the session makes.
    harness.cubit.rearrangeFreeNodes();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    return _allNodePositions(harness.cubit);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await harness.cubit.close();
  }
}

/// A fresh session: the same two placements, one invocation of the action,
/// and the resulting position of every node.
Future<Map<String, Offset>> _positionsAfterFreshPlacementAndRearrange(
  WidgetTester tester,
) async {
  final harness = await _harness();
  try {
    await _pumpShell(tester, harness.cubit);
    await _placeTwoNodes(tester, harness.cubit);
    await tester.tap(_rearrangeButton());
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    return _allNodePositions(harness.cubit);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await harness.cubit.close();
  }
}

Finder _rearrangeButton() =>
    find.byKey(TestIds.key(TestIds.constellationRearrange));

/// The user drops a person and a request somewhere other than the automatic
/// spot and lets the placement settle.
Future<void> _placeTwoNodes(
  WidgetTester tester,
  ConstellationCubit cubit,
) async {
  await cubit.onNewNodeDrop(
    target: ConstellationAnchorTarget.person('p1'),
    sceneCentre: const Offset(2100, 2100),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await cubit.onNewNodeDrop(
    target: ConstellationAnchorTarget.beacon('req-2'),
    sceneCentre: const Offset(1800, 2300),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
}

void main() {
  group('Constellation re-arrange action', () {
    testWidgets('is hidden until the user has moved something', (
      tester,
    ) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpShell(tester, harness.cubit);

      expect(_rearrangeButton(), findsNothing);
      // The other camera actions are present, so absence is about this action.
      expect(
        find.byKey(TestIds.key(TestIds.constellationFitAll)),
        findsOneWidget,
      );
    });

    testWidgets('appears after the first user placement', (tester) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpShell(tester, harness.cubit);
      expect(_rearrangeButton(), findsNothing);

      await _placeTwoNodes(tester, harness.cubit);

      expect(_rearrangeButton(), findsOneWidget);
      // Visible and reachable by a pointer, not merely present in the tree.
      expect(_rearrangeButton().hitTestable(), findsOneWidget);
    });

    testWidgets('is shown for a field that already holds placements', (
      tester,
    ) async {
      final harness = await _harness(fields: [_fieldWithStoredPlacements()]);
      addTearDown(harness.cubit.close);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpShell(tester, harness.cubit);

      expect(_rearrangeButton(), findsOneWidget);
    });

    testWidgets('disappears once the user has removed every placement', (
      tester,
    ) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpShell(tester, harness.cubit);
      await _placeTwoNodes(tester, harness.cubit);
      expect(_rearrangeButton(), findsOneWidget);

      await harness.cubit.unpinAnchor(
        target: ConstellationAnchorTarget.person('p1'),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      // One placement is still left, so the action stays.
      expect(_rearrangeButton(), findsOneWidget);

      await harness.cubit.unpinAnchor(
        target: ConstellationAnchorTarget.beacon('req-2'),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      expect(_rearrangeButton(), findsNothing);
      expect(
        find.byKey(TestIds.key(TestIds.constellationFitAll)),
        findsOneWidget,
      );
    });

    testWidgets('keeps every anchored node where the user put it', (
      tester,
    ) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpShell(tester, harness.cubit);
      await _placeTwoNodes(tester, harness.cubit);

      const anchoredIds = [
        '${TenturaGraphNodeKind.fieldPerson}:p1',
        '${TenturaGraphNodeKind.fieldRequest}:req-2',
      ];
      final before = _allNodePositions(harness.cubit);
      for (final id in anchoredIds) {
        expect(before, contains(id));
      }
      final shownBefore = _shownAnchors(harness.cubit);
      final confirmedBefore = harness.anchorRepo.confirmedPositions;
      final lastPositionBefore = harness.anchorRepo.lastPosition;
      expect(confirmedBefore, hasLength(2));

      await tester.tap(_rearrangeButton());
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      final after = _allNodePositions(harness.cubit);
      for (final id in anchoredIds) {
        expect(after[id]!.dx, closeTo(before[id]!.dx, 0.01), reason: id);
        expect(after[id]!.dy, closeTo(before[id]!.dy, 0.01), reason: id);
      }
      expect(
        harness.cubit.isAnchored(ConstellationAnchorTarget.person('p1')),
        isTrue,
      );
      expect(
        harness.cubit.isAnchored(ConstellationAnchorTarget.beacon('req-2')),
        isTrue,
      );
      expect(_shownAnchors(harness.cubit), shownBefore);
      expect(harness.anchorRepo.confirmedPositions, confirmedBefore);
      expect(harness.anchorRepo.lastPosition, lastPositionBefore);
      expect(tester.takeException(), isNull);
    });

    testWidgets('makes no anchor write and no field fetch', (tester) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpShell(tester, harness.cubit);
      await _placeTwoNodes(tester, harness.cubit);
      final applies = harness.anchorRepo.applyCount;
      final upserts = harness.anchorRepo.upsertCount;
      final deletes = harness.anchorRepo.deleteCount;
      final fetches = harness.fieldRepo.fetchCount;
      expect(upserts, greaterThan(0));
      expect(applies, greaterThan(0));

      await tester.tap(_rearrangeButton());
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      expect(harness.anchorRepo.applyCount, applies);
      expect(harness.anchorRepo.upsertCount, upserts);
      expect(harness.anchorRepo.deleteCount, deletes);
      expect(harness.fieldRepo.fetchCount, fetches);
    });

    testWidgets(
      'gives identical positions for the same input in two fresh sessions',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final first = await _positionsAfterFreshPlacementAndRearrange(tester);
        final second = await _positionsAfterFreshPlacementAndRearrange(tester);

        expect(first, isNotEmpty);
        expect(second.keys.toSet(), first.keys.toSet());
        for (final entry in first.entries) {
          expect(
            second[entry.key]!.dx,
            closeTo(entry.value.dx, 0.01),
            reason: entry.key,
          );
          expect(
            second[entry.key]!.dy,
            closeTo(entry.value.dy, 0.01),
            reason: entry.key,
          );
        }
      },
    );

    testWidgets(
      'lays the free nodes out as a fresh plan of the same placements',
      (
        tester,
      ) async {
        final harness = await _harness();
        addTearDown(harness.cubit.close);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pumpShell(tester, harness.cubit);
        await _placeTwoNodes(tester, harness.cubit);
        final placements = harness.anchorRepo.confirmedPositions;
        expect(placements, hasLength(2));
        await tester.tap(_rearrangeButton());
        await tester.pump();
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
        final after = _allNodePositions(harness.cubit);

        // The plan the layout engine produces for these placements with nothing
        // to stay close to: what a session that loads them already stored shows.
        final plan = await _positionsOfFreshLoadWith(tester, placements);

        const freeIds = [
          '${TenturaGraphNodeKind.fieldPerson}:p2',
          '${TenturaGraphNodeKind.fieldRequest}:req-1',
        ];
        for (final id in freeIds) {
          expect(plan, contains(id));
          expect(after[id]!.dx, closeTo(plan[id]!.dx, 0.5), reason: id);
          expect(after[id]!.dy, closeTo(plan[id]!.dy, 0.5), reason: id);
        }
        // A settled placement keeps the session's pins (ARCH 5.3), so the
        // session already laid these nodes out as the plan; the action must
        // leave them there rather than move them.
      },
    );

    testWidgets('invoking it again leaves the arranged positions as they are', (
      tester,
    ) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpShell(tester, harness.cubit);
      await _placeTwoNodes(tester, harness.cubit);

      await tester.tap(_rearrangeButton());
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      final first = _allNodePositions(harness.cubit);

      await tester.tap(_rearrangeButton());
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      final second = _allNodePositions(harness.cubit);

      expect(second.keys.toSet(), first.keys.toSet());
      for (final entry in first.entries) {
        expect(
          second[entry.key]!.dx,
          closeTo(entry.value.dx, 0.01),
          reason: entry.key,
        );
        expect(
          second[entry.key]!.dy,
          closeTo(entry.value.dy, 0.01),
          reason: entry.key,
        );
      }
    });

    testWidgets('is labelled with localized copy', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = await _harness(fields: [_fieldWithStoredPlacements()]);
      addTearDown(harness.cubit.close);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpShell(tester, harness.cubit);

      final label = L10n.of(
        tester.element(find.byType(ConstellationBody)),
      )!.constellationRearrange;

      expect(label.trim(), isNotEmpty);
      expect(tester.getSemantics(_rearrangeButton()).label, contains(label));
      // Disposed here: the framework checks for open handles before teardowns.
      semantics.dispose();
    });

    test('has a translation distinct from the English copy', () {
      final en = L10nEn().constellationRearrange;
      final ru = L10nRu().constellationRearrange;

      expect(en.trim(), isNotEmpty);
      expect(ru.trim(), isNotEmpty);
      expect(ru, isNot(en));
    });
  });
}
