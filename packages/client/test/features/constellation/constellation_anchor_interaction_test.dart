import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_filter_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_status_marker.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 9, 11, 12);

double relativeLuminance(Color color) {
  double channel(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrastRatio(Color a, Color b) {
  final l1 = relativeLuminance(a);
  final l2 = relativeLuminance(b);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

ConstellationField _field({
  BigInt? revision,
  List<ConstellationAnchor> anchors = const [],
  List<ConstellationPerson> peers = const [],
  List<ConstellationRequest> requests = const [],
  List<String> serverFilteredBeaconIds = const [],
}) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: peers,
  requests: requests,
  anchorProjection: ConstellationAnchorProjection(
    revision: ConstellationAnchorRevision(revision ?? BigInt.one),
    anchors: anchors,
    pinnedPeers: peers,
    pinnedRequests: requests,
    supportPeers: const [],
    supportEdges: const [],
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
    implements ConstellationAnchorRepositoryPort {
  int upsertCount = 0;
  int deleteCount = 0;
  ConstellationAnchorPosition? lastPosition;
  Completer<void>? upsertHold;

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    upsertCount++;
    lastPosition = position;
    await upsertHold?.future;
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
              ConstellationPerson(id: 'p1', displayName: 'Peer'),
            ],
            requests: const [
              ConstellationRequest(
                id: 'req-1',
                authorId: 'p1',
                title: 'Need tools',
                status: 0,
              ),
            ],
          ),
        ],
  );
  final anchorRepo = _HarnessAnchorRepository();
  final sync = buildTestRealtimeSync();
  final anchorCase = ConstellationAnchorCase(
    fieldRepo,
    anchorRepo,
    sync.case_,
    env: const Env.fromEnvironment(),
    logger: Logger('ConstellationAnchorInteractionTest'),
  );
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      fieldRepo,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationAnchorInteractionTest'),
    ),
    anchorCase: anchorCase,
    viewer: _ego,
    forwardRepository: _FakeForwardRepository(),
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

Offset _requireNodeCentre(ConstellationCubit cubit, String id) {
  final node = cubit.graphController.nodes.firstWhere(
    (candidate) => candidate.id == id,
  );
  return cubit.graphController.getPosition(node);
}

void main() {
  group('Constellation anchor interaction', () {
    testWidgets('first pin uses Pin here confirmation', (tester) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      await _pumpShell(tester, harness.cubit);

      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragNew(target: target);
      await harness.cubit.onNewNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );
      await tester.pump();

      expect(
        harness.cubit.state.placementPhase,
        ConstellationPlacementPhase.provisionalNew,
      );
      expect(
        find.byKey(TestIds.key(TestIds.constellationPinHere)),
        findsOneWidget,
      );
      expect(harness.anchorRepo.upsertCount, 0);

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationPinHere)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(harness.anchorRepo.upsertCount, 1);
      expect(
        harness.cubit.state.placementPhase,
        ConstellationPlacementPhase.idle,
      );
    });

    testWidgets('Pin here keeps the node at the dragged scene position', (
      tester,
    ) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      await _pumpShell(tester, harness.cubit);

      final original = _requireNodeCentre(harness.cubit, 'p1');
      const drop = Offset(2800, 1600);
      expect((original - drop).distance, greaterThan(200));

      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragNew(target: target);
      await harness.cubit.onNewNodeDrop(target: target, sceneCentre: drop);
      await tester.pump();

      expect(_requireNodeCentre(harness.cubit, 'p1'), drop);

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationPinHere)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(harness.anchorRepo.upsertCount, 1);
      final expected = constellationPointToV1Anchor((x: drop.dx, y: drop.dy));
      expect(
        harness.anchorRepo.lastPosition!.xUnits,
        closeTo(expected.xUnits, 1e-9),
      );
      expect(
        harness.anchorRepo.lastPosition!.yUnits,
        closeTo(expected.yUnits, 1e-9),
      );
      expect(harness.cubit.isAnchored(target), isTrue);

      final pinned = _requireNodeCentre(harness.cubit, 'p1');
      expect(pinned.dx, closeTo(drop.dx, 1));
      expect(pinned.dy, closeTo(drop.dy, 1));
    });

    testWidgets('Pin here does not snap back while the write is in flight', (
      tester,
    ) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      await _pumpShell(tester, harness.cubit);

      final original = _requireNodeCentre(harness.cubit, 'p1');
      const drop = Offset(2800, 1600);
      expect((original - drop).distance, greaterThan(200));

      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragNew(target: target);
      await harness.cubit.onNewNodeDrop(target: target, sceneCentre: drop);
      await tester.pump();

      harness.anchorRepo.upsertHold = Completer<void>();
      await tester.tap(find.byKey(TestIds.key(TestIds.constellationPinHere)));
      await tester.pump();

      expect(harness.anchorRepo.upsertCount, 1);
      final whilePending = _requireNodeCentre(harness.cubit, 'p1');
      expect(whilePending.dx, closeTo(drop.dx, 1));
      expect(whilePending.dy, closeTo(drop.dy, 1));

      harness.anchorRepo.upsertHold!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final pinned = _requireNodeCentre(harness.cubit, 'p1');
      expect(pinned.dx, closeTo(drop.dx, 1));
      expect(pinned.dy, closeTo(drop.dy, 1));
    });

    testWidgets('unpinning a beacon does not place it on ego', (tester) async {
      final harness = await _harness(
        fields: [
          _field(
            peers: const [
              ConstellationPerson(id: 'p1', displayName: 'Peer'),
            ],
            requests: const [
              ConstellationRequest(
                id: 'req-1',
                authorId: 'p1',
                title: 'Need tools',
                status: 0,
              ),
            ],
            anchors: [
              ConstellationAnchor(
                target: ConstellationAnchorTarget.person('p1'),
                position: const ConstellationAnchorPosition(
                  xUnits: 4,
                  yUnits: 0,
                  coordinateSpaceVersion: 1,
                ),
                revision: ConstellationAnchorRevision(BigInt.one),
                placedAt: _loadedAt,
              ),
              ConstellationAnchor(
                target: ConstellationAnchorTarget.beacon('req-1'),
                position: const ConstellationAnchorPosition(
                  xUnits: -3,
                  yUnits: 5,
                  coordinateSpaceVersion: 1,
                ),
                revision: ConstellationAnchorRevision(BigInt.one),
                placedAt: _loadedAt,
              ),
            ],
          ),
        ],
      );
      addTearDown(harness.cubit.close);
      await _pumpShell(tester, harness.cubit);

      final ego = _requireNodeCentre(harness.cubit, 'ego');
      final pinned = _requireNodeCentre(harness.cubit, 'req-1');
      expect((pinned - ego).distance, greaterThan(200));
      expect(harness.cubit.isAnchored(ConstellationAnchorTarget.beacon('req-1')), isTrue);

      await harness.cubit.unpinAnchor(
        target: ConstellationAnchorTarget.beacon('req-1'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(harness.cubit.isAnchored(ConstellationAnchorTarget.beacon('req-1')), isFalse);
      final unpinned = _requireNodeCentre(harness.cubit, 'req-1');
      expect((unpinned - ego).distance, greaterThan(40));
    });

    testWidgets('pinning a person does not move the camera', (tester) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      await _pumpShell(tester, harness.cubit);

      final controller = harness.cubit.graphController;
      expect(controller.canLayout, isTrue);

      const panTarget = Offset(2800, 2200);
      controller.jumpToPosition(panTarget);
      await tester.pump();

      final screenBefore = controller.sceneToViewportLocal(panTarget);
      expect(screenBefore.dx, inInclusiveRange(0, 1200));
      expect(screenBefore.dy, inInclusiveRange(0, 900));

      await harness.cubit.pinFromText(
        target: ConstellationAnchorTarget.person('p1'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(harness.anchorRepo.upsertCount, 1);
      final screenAfter = controller.sceneToViewportLocal(panTarget);
      expect(screenAfter.dx, closeTo(screenBefore.dx, 1));
      expect(screenAfter.dy, closeTo(screenBefore.dy, 1));
    });

    testWidgets('cancel provisional pin writes nothing', (tester) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      await _pumpShell(tester, harness.cubit);

      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragNew(target: target);
      await harness.cubit.onNewNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(TestIds.key(TestIds.constellationCancelPlacement)),
      );
      await tester.pump();

      expect(harness.anchorRepo.upsertCount, 0);
      expect(
        harness.cubit.state.placementPhase,
        ConstellationPlacementPhase.idle,
      );
    });

    testWidgets('escape cancels provisional placement', (tester) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      await _pumpShell(tester, harness.cubit);

      final target = ConstellationAnchorTarget.person('p1');
      harness.cubit.beginDragNew(target: target);
      await harness.cubit.onNewNodeDrop(
        target: target,
        sceneCentre: const Offset(2100, 2100),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(harness.anchorRepo.upsertCount, 0);
      expect(
        harness.cubit.state.placementPhase,
        ConstellationPlacementPhase.idle,
      );
    });

    testWidgets('text-first pin submits one upsert', (tester) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      harness.cubit.setViewMode(ConstellationViewMode.text);
      await _pumpShell(tester, harness.cubit);

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationPinTarget)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(harness.anchorRepo.upsertCount, 1);
    });

    test('hidden pin count unions server and local filter ids', () async {
      final harness = await _harness(
        fields: [
          _field(
            peers: const [ConstellationPerson(id: 'p1')],
            requests: const [
              ConstellationRequest(
                id: 'req-closed',
                authorId: 'p1',
                title: 'Closed',
                status: 4,
              ),
              ConstellationRequest(
                id: 'req-open',
                authorId: 'p1',
                title: 'Open',
                status: 0,
                needs: ['knowledge'],
              ),
            ],
            anchors: [
              ConstellationAnchor(
                target: ConstellationAnchorTarget.beacon('req-closed'),
                position: const ConstellationAnchorPosition(
                  xUnits: 1,
                  yUnits: 1,
                  coordinateSpaceVersion: 1,
                ),
                revision: ConstellationAnchorRevision(BigInt.one),
                placedAt: _loadedAt,
              ),
              ConstellationAnchor(
                target: ConstellationAnchorTarget.beacon('req-open'),
                position: const ConstellationAnchorPosition(
                  xUnits: 2,
                  yUnits: 2,
                  coordinateSpaceVersion: 1,
                ),
                revision: ConstellationAnchorRevision(BigInt.one),
                placedAt: _loadedAt,
              ),
            ],
            serverFilteredBeaconIds: const ['req-closed'],
          ),
        ],
      );
      addTearDown(harness.cubit.close);

      harness.cubit.setFilterCapabilitySlugs({'logistics'});
      expect(harness.cubit.hiddenPinnedBeaconCount, 2);
    });

    testWidgets('clear filters resets membership defaults', (tester) async {
      final harness = await _harness();
      addTearDown(harness.cubit.close);
      await harness.cubit.setShowClosed(true);
      expect(harness.cubit.state.membershipFilters.showClosed, isTrue);

      await harness.cubit.clearFilters();
      expect(harness.cubit.state.membershipFilters.showClosed, isFalse);
      expect(harness.cubit.state.membershipFilters.participatedOnly, isFalse);
      expect(harness.cubit.canClearFilters, isFalse);
    });

    testWidgets('status presenter rejects unknown raw status', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Builder(
              builder: (context) {
                final l10n = L10n.of(context)!;
                final tt = context.tt;
                expect(
                  constellationRequestStatusPresentation(
                    rawStatus: 99,
                    l10n: l10n,
                    tt: tt,
                  ),
                  isNull,
                );
                expect(
                  constellationRequestStatusPresentation(
                    rawStatus: 4,
                    l10n: l10n,
                    tt: tt,
                  )?.label,
                  l10n.constellationRequestStatusClosed,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('five status cues and independent pin marker', (tester) async {
      final statuses = <int, IconData>{
        0: Icons.circle_outlined,
        7: Icons.person_add_alt_1_outlined,
        8: Icons.check,
        5: Icons.schedule,
        4: Icons.task_alt,
      };
      for (final entry in statuses.entries) {
        await tester.pumpWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: TenturaResponsiveScope(
              child: ConstellationRequestStatusMarker(
                rawStatus: entry.key,
                isPinned: true,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byIcon(entry.value), findsOneWidget);
        expect(find.byIcon(Icons.push_pin), findsOneWidget);
      }
    });

    testWidgets('semantics at text scale 1 and 2', (tester) async {
      for (final scale in [1.0, 2.0]) {
        final harness = await _harness();
        addTearDown(harness.cubit.close);
        harness.cubit.setViewMode(ConstellationViewMode.text);
        await _pumpShell(tester, harness.cubit, textScale: scale);
        final semantics = tester.getSemantics(
          find.byKey(const Key('constellation.text.request.req-1')),
        );
        expect(semantics.label, contains('Open'));
      }
    });

    testWidgets('compact and expanded layouts render filter bar', (
      tester,
    ) async {
      for (final size in [
        const Size(390, 844),
        const Size(1440, 900),
      ]) {
        final harness = await _harness();
        addTearDown(harness.cubit.close);
        await _pumpShell(tester, harness.cubit, surface: size);
        expect(find.byType(ConstellationFilterBar), findsNothing);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: TenturaResponsiveScope(
              child: BlocProvider<ConstellationCubit>.value(
                value: harness.cubit,
                child: const Scaffold(
                  body: SingleChildScrollView(
                    child: ConstellationFilterBar(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(TestIds.key(TestIds.constellationFilterShowClosed)),
          findsOneWidget,
        );
      }
    });

    testWidgets('status and pin markers meet contrast floors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Builder(
              builder: (context) {
                final l10n = L10n.of(context)!;
                final tt = context.tt;
                final scheme = Theme.of(context).colorScheme;
                final background = scheme.surface;
                for (final status in [7, 8, 5, 4]) {
                  final presentation = constellationRequestStatusPresentation(
                    rawStatus: status,
                    l10n: l10n,
                    tt: tt,
                  )!;
                  expect(
                    contrastRatio(presentation.color, background),
                    greaterThanOrEqualTo(3),
                  );
                }
                final open = constellationRequestStatusPresentation(
                  rawStatus: 0,
                  l10n: l10n,
                  tt: tt,
                )!;
                expect(open.color, tt.border);
                expect(
                  contrastRatio(tt.info, background),
                  greaterThanOrEqualTo(3),
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    });
  });
}
