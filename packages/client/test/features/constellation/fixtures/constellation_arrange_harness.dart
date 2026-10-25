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
import 'package:tentura/features/constellation/ui/widget/constellation_camera_controls.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../../support/constellation_store_fixture.dart';
import '../../../support/fake_clock_port.dart';
import '../../../support/fake_wake_up_port.dart';
import '../../../support/test_forward_case.dart';
import '../../../support/test_realtime_sync.dart';
import '../../../ui/effect/fake_ui_effect_port.dart';

/// A Field whose server side (anchors, layout snapshots) is modelled by
/// [ArrangeAnchorRepository], for the Arrange menu, undoable reset and undo
/// shortcut tests.

ConstellationAnchorPosition arrangePosition(double x, double y) =>
    ConstellationAnchorPosition(
      xUnits: x,
      yUnits: y,
      coordinateSpaceVersion: 1,
    );

ConstellationAnchorRevision arrangeRevision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

final arrangePersonOne = ConstellationAnchorTarget.person('p1');
final arrangePersonTwo = ConstellationAnchorTarget.person('p2');
final arrangePersonThree = ConstellationAnchorTarget.person('p3');

/// The layout the user has arranged by hand when a test starts.
Map<ConstellationAnchorTarget, ConstellationAnchorPosition>
arrangeInitialAnchors() => {
  arrangePersonOne: arrangePosition(1, 2),
  arrangePersonTwo: arrangePosition(-3, 4),
  arrangePersonThree: arrangePosition(5, -6),
};

/// Server model: the viewer's anchors plus the layout snapshots a reset or a
/// restore writes before it changes them.
final class ArrangeAnchorRepository
    implements ConstellationAnchorRepositoryPort {
  ArrangeAnchorRepository(
    Map<ConstellationAnchorTarget, ConstellationAnchorPosition> initial,
  ) : anchors = {...initial};

  final Map<ConstellationAnchorTarget, ConstellationAnchorPosition> anchors;

  final applies = <List<ConstellationAnchorApplyOp>>[];
  final resets = <({String clientOpId, bool saveHistory})>[];
  final restores = <String>[];

  final _snapshots =
      <String, Map<ConstellationAnchorTarget, ConstellationAnchorPosition>>{};

  /// Thrown by the next [reset] calls while set.
  Object? resetError;

  var _revision = 10;
  var _snapshotSeq = 0;
  String? _latestSnapshotId;

  int get revision => _revision;

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    applies.add(List.of(ops));
    final before = _revision;
    final results = <ConstellationAnchorOpResult>[];
    for (final op in ops) {
      _revision++;
      if (op.kind == ConstellationAnchorOpKind.delete) {
        anchors.remove(op.target);
      } else {
        anchors[op.target] = op.position!;
      }
      results.add(
        ConstellationAnchorOpResult(
          clientOpId: op.clientOpId,
          status: ConstellationAnchorOpStatus.ok,
          resultingTargetRevision: arrangeRevision(_revision),
          target: op.target,
          anchor: op.kind == ConstellationAnchorOpKind.delete
              ? null
              : ConstellationAnchor(
                  target: op.target,
                  position: op.position!,
                  revision: arrangeRevision(_revision),
                  placedAt: DateTime.utc(2026, 10, 25),
                ),
        ),
      );
    }
    return ConstellationAnchorApplyResult(
      beforeRevision: arrangeRevision(before),
      afterRevision: arrangeRevision(_revision),
      results: results,
    );
  }

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) async {
    resets.add((clientOpId: clientOpId, saveHistory: saveHistory));
    final error = resetError;
    if (error != null) throw error;
    final before = _revision;
    if (saveHistory) {
      final snapshotId = 'LS-reset-${++_snapshotSeq}';
      _snapshots[snapshotId] = {...anchors};
      _latestSnapshotId = snapshotId;
    }
    final cleared = anchors.length;
    anchors.clear();
    _revision++;
    return ConstellationAnchorResetResult(
      beforeRevision: arrangeRevision(before),
      afterRevision: arrangeRevision(_revision),
      clearedCount: cleared,
    );
  }

  /// Puts a saved layout back in one step; the layout it replaces is saved
  /// first and its id returned, so the restore can itself be undone.
  ///
  /// How the client learns the id of the reset snapshot is left to the
  /// implementation (a field of the reset result or a snapshot listing): an
  /// id this fake does not know stands for the newest saved layout. Not an
  /// override today: the port gains this method with the unit under test.
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) async {
    restores.add(snapshotId);
    final source = _snapshots[snapshotId] ?? _snapshots[_latestSnapshotId]!;
    final written = 'LS-restore-${++_snapshotSeq}';
    _snapshots[written] = {...anchors};
    _latestSnapshotId = written;
    anchors
      ..clear()
      ..addAll(source);
    _revision++;
    return written;
  }
}

final class ArrangeFieldRepository implements ConstellationRepositoryPort {
  ArrangeFieldRepository(this._anchors);

  final ArrangeAnchorRepository _anchors;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    const peers = [
      ConstellationPerson(id: 'p1', displayName: 'Peer one'),
      ConstellationPerson(id: 'p2', displayName: 'Peer two'),
      ConstellationPerson(id: 'p3', displayName: 'Peer three'),
    ];
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 25),
      context: '',
      peers: peers,
      anchorProjection: ConstellationAnchorProjection(
        revision: arrangeRevision(_anchors.revision),
        anchors: [
          for (final entry in _anchors.anchors.entries)
            ConstellationAnchor(
              target: entry.key,
              position: entry.value,
              revision: arrangeRevision(_anchors.revision),
              placedAt: DateTime.utc(2026, 10, 25),
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

typedef ArrangeHarness = ({
  ConstellationCubit cubit,
  ConstellationPlacementCase placement,
  ArrangeAnchorRepository anchors,
});

Future<ArrangeHarness> arrangeHarness({
  Map<ConstellationAnchorTarget, ConstellationAnchorPosition>? initial,
}) async {
  final anchors = ArrangeAnchorRepository(initial ?? arrangeInitialAnchors());
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    ArrangeFieldRepository(anchors),
    accountId: 'ego',
    realtime: sync.case_,
  ).store;
  final placement = ConstellationPlacementCase(
    anchors,
    store,
    FakeClockPort(DateTime.utc(2026, 10, 25)),
    FakeWakeUpPort(),
    realtime: sync.case_,
    env: const Env.fromEnvironment(),
    logger: Logger('ConstellationArrangeHarness'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    anchorCase: ConstellationAnchorCase(
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationArrangeHarness'),
    ),
    placementCase: placement,
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
    forwardCase: buildTestForwardCase(_FakeForwardRepository()),
    loadOnCreate: false,
  );
  await cubit.load();
  addTearDown(() async {
    await cubit.close();
    await placement.dispose();
  });
  return (cubit: cubit, placement: placement, anchors: anchors);
}

Widget _shell(ConstellationCubit cubit, Widget child) => MaterialApp(
  locale: const Locale('en'),
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
      child: Scaffold(body: child),
    ),
  ),
);

/// The Field body, as the screen mounts it.
Future<void> pumpArrangeBody(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required bool arrangeV2Enabled,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _shell(
      cubit,
      ConstellationBody(
        legendExpanded: false,
        onToggleLegend: () {},
        arrangeV2Enabled: arrangeV2Enabled,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The floating camera column alone.
Future<void> pumpArrangeControls(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required bool arrangeV2Enabled,
  bool tagViewActive = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _shell(
      cubit,
      Align(
        alignment: Alignment.topRight,
        child: ConstellationCameraControls(
          cubit: cubit,
          viewportInsets: EdgeInsets.zero,
          arrangeV2Enabled: arrangeV2Enabled,
          tagViewActive: tagViewActive,
        ),
      ),
    ),
  );
  await tester.pump();
}
