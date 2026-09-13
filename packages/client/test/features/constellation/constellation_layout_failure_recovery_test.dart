import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
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

void _logMemory(String label) {
  try {
    final mem = File('/proc/meminfo').readAsLinesSync();
    String? avail;
    String? swapFree;
    for (final line in mem) {
      if (line.startsWith('MemAvailable:')) {
        avail = line.trim();
      } else if (line.startsWith('SwapFree:')) {
        swapFree = line.trim();
      }
    }
    // ignore: avoid_print
    print('MEM $label: ${avail ?? "?"} | ${swapFree ?? "?"}');
  } on Object {
    // ignore: avoid_print
    print('MEM $label: (unavailable)');
  }
}

final _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 9, 13, 12);

ConstellationField _field() => ConstellationField(
      loadedAt: _loadedAt,
      context: '',
      peers: const [
        ConstellationPerson(id: 'p1', displayName: 'Peer'),
      ],
      requests: const [],
      anchorProjection: ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision(BigInt.one),
        anchors: const [],
        pinnedPeers: const [
          ConstellationPerson(id: 'p1', displayName: 'Peer'),
        ],
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );

final class _HarnessFieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      _field();
}

final class _HarnessAnchorRepository implements ConstellationAnchorRepositoryPort {
  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async =>
      ConstellationAnchorUpsertResult(
        anchor: ConstellationAnchor(
          target: target,
          position: position,
          revision: ConstellationAnchorRevision(BigInt.two),
          placedAt: _loadedAt,
        ),
        revision: ConstellationAnchorRevision(BigInt.two),
      );

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) async =>
      ConstellationAnchorDeleteResult(
        target: target,
        revision: ConstellationAnchorRevision(BigInt.from(3)),
      );
}

final class _FakeForwardRepository implements ForwardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SyncThrowLayoutAlgorithm implements SceneLayoutAlgorithm {
  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) {
    throw StateError('sync layout failure');
  }
}

Future<void> _settleSceneLayoutSucceeded(
  WidgetTester tester,
  GraphSceneController<dynamic, dynamic> scene,
) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (scene.layoutOutcome is GraphLayoutOutcomeSucceeded) {
      return;
    }
  }
}

Future<void> _settleGraphLayoutFailureMessage(
  WidgetTester tester,
  ConstellationCubit cubit,
) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (cubit.state.graphLayoutFailureMessage != null) {
      return;
    }
  }
  expect(
    cubit.state.graphLayoutFailureMessage,
    isNotNull,
    reason: 'graph layout failure message was not surfaced',
  );
}

Future<void> _pumpFramesWithoutRelayout(
  WidgetTester tester,
  ConstellationCubit cubit,
  int frameCount, {
  required int relayoutCountBaseline,
}) async {
  for (var i = 0; i < frameCount; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      cubit.graphController.relayoutInvocationCount,
      relayoutCountBaseline,
    );
  }
}

Future<void> _pumpConstellationMap(
  WidgetTester tester,
  ConstellationCubit cubit,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
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
}

Future<ConstellationCubit> _loadedCubit(WidgetTester tester) async {
  final field = _field();
  final sync = buildTestRealtimeSync();
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _HarnessFieldRepository(),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationLayoutFailureRecoveryTest'),
    ),
    viewer: _ego,
    anchorCase: ConstellationAnchorCase(
      _HarnessFieldRepository(),
      _HarnessAnchorRepository(),
      sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationLayoutFailureRecoveryTest'),
    ),
    forwardRepository: _FakeForwardRepository(),
    loadOnCreate: false,
  );
  await cubit.load();
  await _pumpConstellationMap(tester, cubit);
  await _settleSceneLayoutSucceeded(tester, cubit.graphController.scene);
  expect(
    cubit.graphController.scene.layoutOutcome,
    isA<GraphLayoutOutcomeSucceeded>(),
    reason: 'initial constellation layout did not succeed',
  );
  return cubit;
}

void main() {
  _logMemory('constellation_layout_failure_recovery before');

  group('constellation layout failure recovery', () {
    testWidgets(
        'recovers once from confirmed projection after owned layout failure',
        (tester) async {
      final cubit = await _loadedCubit(tester);
      addTearDown(cubit.close);
      final requestsBefore = cubit.graphController.relayoutInvocationCount;

      cubit.requestConstellationLayoutForTest(
        algorithm: _SyncThrowLayoutAlgorithm(),
      );
      await _settleSceneLayoutSucceeded(tester, cubit.graphController.scene);

      expect(
        cubit.graphController.scene.layoutOutcome,
        isA<GraphLayoutOutcomeSucceeded>(),
        reason: 'recovery layout did not succeed',
      );
      expect(cubit.state.graphLayoutFailureMessage, isNull);
      expect(
        cubit.graphController.relayoutInvocationCount,
        greaterThanOrEqualTo(requestsBefore + 2),
      );
    });

    testWidgets(
        'second owned failure surfaces message without further relayout loop',
        (tester) async {
      final cubit = await _loadedCubit(tester);
      addTearDown(cubit.close);
      cubit.testSceneLayoutAlgorithmOverride = _SyncThrowLayoutAlgorithm();

      cubit.requestConstellationLayoutForTest(
        algorithm: _SyncThrowLayoutAlgorithm(),
      );
      await _settleGraphLayoutFailureMessage(tester, cubit);

      expect(
        cubit.state.graphLayoutFailureMessage,
        kConstellationGraphLayoutFailureMessage,
      );

      final countAfterFailure = cubit.graphController.relayoutInvocationCount;
      await _pumpFramesWithoutRelayout(
        tester,
        cubit,
        24,
        relayoutCountBaseline: countAfterFailure,
      );
    });

    testWidgets('retryGraphLayoutAfterFailure clears failure and relayouts',
        (tester) async {
      final cubit = await _loadedCubit(tester);
      addTearDown(cubit.close);
      cubit.testSceneLayoutAlgorithmOverride = _SyncThrowLayoutAlgorithm();

      cubit.requestConstellationLayoutForTest(
        algorithm: _SyncThrowLayoutAlgorithm(),
      );
      await _settleGraphLayoutFailureMessage(tester, cubit);
      expect(cubit.state.graphLayoutFailureMessage, isNotNull);

      cubit.testSceneLayoutAlgorithmOverride = null;
      cubit.retryGraphLayoutAfterFailure();
      await _settleSceneLayoutSucceeded(tester, cubit.graphController.scene);

      expect(
        cubit.graphController.scene.layoutOutcome,
        isA<GraphLayoutOutcomeSucceeded>(),
      );
      expect(cubit.state.graphLayoutFailureMessage, isNull);
    });
  });

  tearDownAll(() {
    _logMemory('constellation_layout_failure_recovery after');
  });
}
