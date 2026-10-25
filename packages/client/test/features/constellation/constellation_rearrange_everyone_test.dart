import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

/// «Rearrange everyone, including pinned»: a preview that writes nothing and
/// counts the people who would move, Cancel that leaves the Field as it was,
/// Apply as one history snapshot plus one anchor batch for every pinned
/// target, and one Undo that puts all of them back.

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 9, 11, 12);

final _p1 = ConstellationAnchorTarget.person('p1');
final _p2 = ConstellationAnchorTarget.person('p2');
final _p3 = ConstellationAnchorTarget.person('p3');
final _p4 = ConstellationAnchorTarget.person('p4');

const _pinnedAt = <String, ConstellationAnchorPosition>{
  'p1': ConstellationAnchorPosition(
    xUnits: 1,
    yUnits: 2,
    coordinateSpaceVersion: 1,
  ),
  'p2': ConstellationAnchorPosition(
    xUnits: 3,
    yUnits: 4,
    coordinateSpaceVersion: 1,
  ),
};

/// Two people are pinned (p1, p2); p3 and p4 are placed by the automatic
/// layout, so a full re-layout has pins to override and free nodes to re-lay.
ConstellationField _fieldWithPinnedAndFreePeople() {
  const peers = [
    ConstellationPerson(id: 'p1', displayName: 'Peer one'),
    ConstellationPerson(id: 'p2', displayName: 'Peer two'),
    ConstellationPerson(id: 'p3', displayName: 'Peer three'),
    ConstellationPerson(id: 'p4', displayName: 'Peer four'),
  ];
  return ConstellationField(
    loadedAt: _loadedAt,
    context: '',
    peers: peers,
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.one),
      anchors: [
        for (final entry in _pinnedAt.entries)
          ConstellationAnchor(
            target: ConstellationAnchorTarget.person(entry.key),
            position: entry.value,
            revision: ConstellationAnchorRevision(BigInt.one),
            placedAt: DateTime.utc(2026, 9, 11),
          ),
      ],
      pinnedPeers: peers,
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

final class _FieldRepository implements ConstellationRepositoryPort {
  _FieldRepository(this.field);

  final ConstellationField field;
  int fetchCount = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetchCount++;
    return field;
  }
}

/// A server that keeps its anchors and saved layouts, and logs every write.
final class _AnchorServer implements ConstellationWriteFake {
  _AnchorServer(Map<ConstellationAnchorTarget, ConstellationAnchorPosition> at)
    : _anchors = {...at};

  /// Writes in the order they reached the server: `save:<reason>`, `apply`,
  /// `restore`, `reset`.
  final events = <String>[];

  /// Every batch of an `apply`, in order.
  final batches = <List<ConstellationAnchorApplyOp>>[];

  final Map<ConstellationAnchorTarget, ConstellationAnchorPosition> _anchors;
  final _snapshots =
      <String, Map<ConstellationAnchorTarget, ConstellationAnchorPosition>>{};
  String? _latestSnapshotId;
  var _revision = BigInt.from(10);

  Map<ConstellationAnchorTarget, ConstellationAnchorPosition> get anchors => {
    ..._anchors,
  };

  List<String> get savedReasons => [
    for (final event in events)
      if (event.startsWith('save:')) event.substring('save:'.length),
  ];

  String _saveCurrent() {
    final id = 'LS${_snapshots.length + 1}';
    _snapshots[id] = {..._anchors};
    return _latestSnapshotId = id;
  }

  /// Saves the viewer's current layout as a history snapshot.
  @override
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  }) async {
    events.add('save:$reason');
    return _saveCurrent();
  }

  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) async {
    events.add('restore');
    final source =
        _snapshots[snapshotId == kLatestLayoutSnapshotId
            ? _latestSnapshotId
            : snapshotId]!;
    final replaced = _saveCurrent();
    _anchors
      ..clear()
      ..addAll(source);
    _revision += BigInt.one;
    return replaced;
  }

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) async {
    events.add('reset');
    throw UnimplementedError('reset is not used by this test');
  }

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    events.add('apply');
    batches.add(ops);
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
                  placedAt: DateTime.utc(2026, 9, 11, 1),
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

Future<
  ({
    ConstellationCubit cubit,
    _FieldRepository fieldRepo,
    _AnchorServer server,
  })
>
_harness() async {
  final fieldRepo = _FieldRepository(_fieldWithPinnedAndFreePeople());
  final server = _AnchorServer({
    for (final entry in _pinnedAt.entries)
      ConstellationAnchorTarget.person(entry.key): entry.value,
  });
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    fieldRepo,
    accountId: 'ego',
    realtime: sync.case_,
  ).store;
  final cubit = ConstellationCubit(
    case_: store,
    anchorCase: ConstellationAnchorCase(
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationRearrangeEveryoneTest'),
    ),
    placementCase: ConstellationPlacementCase(
      server,
      store,
      FakeClockPort(),
      FakeWakeUpPort(),
      realtime: sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationRearrangeEveryoneTest'),
    ),
    viewer: _ego,
    forwardCase: buildTestForwardCase(_FakeForwardRepository()),
    loadOnCreate: false,
  );
  await cubit.load();
  return (cubit: cubit, fieldRepo: fieldRepo, server: server);
}

Future<void> _pumpShell(
  WidgetTester tester,
  ConstellationCubit cubit, {
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
}

/// Scene position of every graph node, keyed by its graph id.
Map<String, Offset> _nodePositions(ConstellationCubit cubit) => {
  for (final node in cubit.graphController.nodes)
    tenturaGraphNodeId(node): cubit.graphController.getPositionForId(
      tenturaGraphNodeId(node),
    ),
};

bool _moved(
  Map<String, Offset> before,
  Map<String, Offset> after,
  String personId,
) {
  final id = '${TenturaGraphNodeKind.fieldPerson}:$personId';
  return (after[id]! - before[id]!).distance > 0.5;
}

/// Anchor position the cubit currently shows for every anchored target.
Map<ConstellationAnchorTarget, ConstellationAnchorPosition> _shownAnchors(
  ConstellationCubit cubit,
) => {
  for (final anchor in cubit.state.composition!.anchorOverlay.anchors)
    anchor.target: anchor.position,
};

const _previewCopySuffix = ' · your current layout is saved to history';

Finder _previewMessage(int count) =>
    find.text('$count people will move$_previewCopySuffix');

void main() {
  final pinnedTargets = {_p1, _p2};
  final freeTargets = {_p3, _p4};
  final originalAnchors = {
    for (final entry in _pinnedAt.entries)
      ConstellationAnchorTarget.person(entry.key): entry.value,
  };

  Future<
    ({
      ConstellationCubit cubit,
      _FieldRepository fieldRepo,
      _AnchorServer server,
    })
  >
  openField(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    final harness = await _harness();
    addTearDown(harness.cubit.close);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpShell(tester, harness.cubit, locale: locale);
    return harness;
  }

  group('Rearrange everyone including pinned', () {
    testWidgets('the preview counts exactly the people who then move', (
      tester,
    ) async {
      final h = await openField(tester);
      expect(h.cubit.state.rearrangePreview, isNull);
      final before = _nodePositions(h.cubit);

      h.cubit.previewRearrangeAll();
      await _settle(tester);
      final count = h.cubit.state.rearrangePreview!.movingCount;
      await h.cubit.applyRearrangePreview();
      await _settle(tester);

      final after = _nodePositions(h.cubit);
      final moved = {
        for (final target in [..._pinnedAt.keys, 'p3', 'p4'])
          if (_moved(before, after, target)) target,
      };
      // Both pinned people leave their pins.
      expect(moved, containsAll(['p1', 'p2']));
      expect(count, moved.length);
    });

    testWidgets(
      'the preview shows how many people will move with Apply and Cancel',
      (tester) async {
        final h = await openField(tester);
        expect(find.textContaining('people will move'), findsNothing);

        h.cubit.previewRearrangeAll();
        await _settle(tester);

        final count = h.cubit.state.rearrangePreview!.movingCount;
        expect(_previewMessage(count), findsOneWidget);
        expect(find.text('Apply'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      },
    );

    testWidgets('the preview message is shown in Russian too', (tester) async {
      final h = await openField(tester, locale: const Locale('ru'));

      h.cubit.previewRearrangeAll();
      await _settle(tester);

      final count = h.cubit.state.rearrangePreview!.movingCount;
      expect(
        find.text(
          'Сдвинется $count чел. · текущая расстановка сохранится в истории',
        ),
        findsOneWidget,
      );
    });

    testWidgets('previewing writes nothing and moves no node', (tester) async {
      final h = await openField(tester);
      final positionsBefore = _nodePositions(h.cubit);
      final shownBefore = _shownAnchors(h.cubit);
      final fetchesBefore = h.fieldRepo.fetchCount;

      h.cubit.previewRearrangeAll();
      await _settle(tester);

      expect(h.server.events, isEmpty);
      expect(h.server.anchors, originalAnchors);
      expect(_shownAnchors(h.cubit), shownBefore);
      expect(_nodePositions(h.cubit), positionsBefore);
      expect(h.fieldRepo.fetchCount, fetchesBefore);
      expect(h.cubit.canUndoArrangement, isFalse);
    });

    testWidgets('cancelling the preview leaves the Field as it was', (
      tester,
    ) async {
      final h = await openField(tester);
      final positionsBefore = _nodePositions(h.cubit);
      final shownBefore = _shownAnchors(h.cubit);

      h.cubit.previewRearrangeAll();
      await _settle(tester);
      h.cubit.cancelRearrangePreview();
      await _settle(tester);

      expect(h.cubit.state.rearrangePreview, isNull);
      expect(_nodePositions(h.cubit), positionsBefore);
      expect(_shownAnchors(h.cubit), shownBefore);
      expect(h.server.events, isEmpty);
      expect(h.server.anchors, originalAnchors);
      expect(h.cubit.canUndoArrangement, isFalse);
    });

    testWidgets('the Cancel button closes the preview without writing', (
      tester,
    ) async {
      final h = await openField(tester);
      final positionsBefore = _nodePositions(h.cubit);

      h.cubit.previewRearrangeAll();
      await _settle(tester);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      expect(h.cubit.state.rearrangePreview, isNull);
      expect(find.textContaining('people will move'), findsNothing);
      expect(_nodePositions(h.cubit), positionsBefore);
      expect(h.server.events, isEmpty);
    });

    testWidgets(
      'applying saves one history snapshot, then writes one batch that '
      'upserts only the pinned targets',
      (tester) async {
        final h = await openField(tester);

        h.cubit.previewRearrangeAll();
        await _settle(tester);
        final applied = await h.cubit.applyRearrangePreview();
        await _settle(tester);

        expect(applied, isTrue);
        expect(h.cubit.state.rearrangePreview, isNull);
        // The snapshot is taken before anything is written.
        expect(h.server.events, ['save:rebuild', 'apply']);
        expect(h.server.batches, hasLength(1));
        final batch = h.server.batches.single;
        expect(batch.map((op) => op.kind).toSet(), {
          ConstellationAnchorOpKind.upsert,
        });
        expect(batch.map((op) => op.target).toSet(), pinnedTargets);
        expect(batch, hasLength(pinnedTargets.length));
        // Pinned people move to a new place, they do not become automatic;
        // free people are re-laid out locally and never become pinned.
        expect(h.server.anchors.keys.toSet(), pinnedTargets);
        for (final target in pinnedTargets) {
          expect(
            h.server.anchors[target],
            isNot(originalAnchors[target]),
            reason: '${target.id} is written to its new position',
          );
          expect(h.cubit.isAnchored(target), isTrue);
        }
        for (final target in freeTargets) {
          expect(h.cubit.isAnchored(target), isFalse, reason: target.id);
        }
        expect(_shownAnchors(h.cubit), h.server.anchors);
      },
    );

    testWidgets('the Apply button applies the previewed arrangement', (
      tester,
    ) async {
      final h = await openField(tester);

      h.cubit.previewRearrangeAll();
      await _settle(tester);
      await tester.tap(find.text('Apply'));
      await _settle(tester);

      expect(h.cubit.state.rearrangePreview, isNull);
      expect(h.server.events, ['save:rebuild', 'apply']);
      expect(
        h.server.batches.single.map((op) => op.target).toSet(),
        pinnedTargets,
      );
    });

    testWidgets('applying records exactly one undoable step', (tester) async {
      final h = await openField(tester);
      expect(h.cubit.canUndoArrangement, isFalse);

      h.cubit.previewRearrangeAll();
      await _settle(tester);
      await h.cubit.applyRearrangePreview();
      await _settle(tester);

      expect(h.cubit.canUndoArrangement, isTrue);
      expect(await h.cubit.undoArrangement(), isTrue);
      await _settle(tester);
      expect(h.cubit.canUndoArrangement, isFalse);
      expect(h.cubit.canRedoArrangement, isTrue);
    });

    testWidgets(
      'one undo puts every node back, on the server and on screen',
      (tester) async {
        final h = await openField(tester);
        final positionsBefore = _nodePositions(h.cubit);
        final shownBefore = _shownAnchors(h.cubit);

        h.cubit.previewRearrangeAll();
        await _settle(tester);
        await h.cubit.applyRearrangePreview();
        await _settle(tester);
        expect(h.server.anchors, isNot(originalAnchors));
        expect(_shownAnchors(h.cubit), isNot(shownBefore));

        expect(await h.cubit.undoArrangement(), isTrue);
        await _settle(tester);

        expect(h.server.anchors, originalAnchors);
        expect(_shownAnchors(h.cubit), shownBefore);
        final positionsAfter = _nodePositions(h.cubit);
        expect(positionsAfter.keys.toSet(), positionsBefore.keys.toSet());
        for (final entry in positionsBefore.entries) {
          expect(
            positionsAfter[entry.key]!.dx,
            closeTo(entry.value.dx, 0.01),
            reason: entry.key,
          );
          expect(
            positionsAfter[entry.key]!.dy,
            closeTo(entry.value.dy, 0.01),
            reason: entry.key,
          );
        }
        for (final target in freeTargets) {
          expect(h.cubit.isAnchored(target), isFalse, reason: target.id);
        }
      },
    );
  });
}
