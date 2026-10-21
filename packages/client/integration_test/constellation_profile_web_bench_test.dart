// Profile-web benchmark of the Constellation graph (issue #235 U40, I4).
//
// Run only through scripts/run_client_profile_web_bench_local.sh: it needs a
// browser and a `--profile` build, and it reports numbers rather than
// asserting budgets. The driver writes them to
// build/bench/constellation_profile_web.json.
//
// The field is the synthetic U01 field (N people and N Requests, 10% of each
// pinned) served by in-memory repositories, so the numbers measure the real
// Constellation widgets, scene controller, layout slicer and outbox in the
// browser, without network noise. Placement acks arrive after a fixed delay.
//
// Per N the pinned person is held, dragged and released twice, with a mouse
// and then with a touch: each cycle records grab → first moved frame, the
// drag frames, drop → ack → reflow and every main-thread task over 50 ms with
// its phase (grab / drag / drop / ack / reflow). Then the camera is panned.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' show FrameTiming, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show debugProfileLayoutsEnabled, debugProfilePaintsEnabled;
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart'
    show GraphLayoutOutcomeSucceeded;
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/service/clock_service.dart';
import 'package:tentura/data/service/wake_up_service.dart';
import 'package:tentura/domain/scheduling/adaptive_slice_controller.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_scene_controller.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/frame_slice_scheduler.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:web/web.dart' as web;

import '../test/features/constellation/fixtures/constellation_reference_fixture.dart';
import '../test/features/constellation/fixtures/synthetic_field.dart';
import '../test/support/constellation_store_fixture.dart';
import '../test/support/test_realtime_sync.dart';

const _sizes = [100, 300, 600];
const _surface = Size(1200, 800);
const _dragFrames = 60;
const _panFrames = 60;
const _ackDelay = Duration(milliseconds: 80);
const _reportKey = 'constellationProfileWebBench';

/// Diagnostic runs only: per-widget build, layout and paint Timeline events
/// during the drag and drop → reflow, to show where the time goes. They add overhead, so
/// such a run's numbers are not the benchmark's.
const _profileObjects = bool.fromEnvironment(
  'CONSTELLATION_BENCH_PROFILE_OBJECTS',
);

/// Timeline span names the client emits (lib/.../constellation_perf.dart);
/// dart2js maps each finished span to a `performance.measure` entry.
const _spanNames = [
  'constellation.drop→draggable',
  'drop→acked',
  'drop→reflowed',
  'layout.job',
  'compose',
  'scene.build',
];

@JS('eval')
external JSAny? _evaluate(JSString source);

String _evalString(String source) =>
    (_evaluate(source.toJS)! as JSString).toDart;

/// Collects browser long tasks (> 50 ms main-thread tasks, Long Tasks API)
/// and every `performance.measure` (dart2js maps finished Timeline spans,
/// the framework's frame phases and the client's spans, to measures) as they
/// are created, so the 10 000-entry clean-up of the Timeline shim cannot drop
/// them. [_window] aggregates both over a time window.
void _installObservers() {
  _evaluate(
    '''
(() => {
  if (window.__constellationBench) return;
  const state = window.__constellationBench = {
    longTasks: [], measures: [], longTaskSupported: false, error: null,
    window(t0, t1) {
      const measures = {};
      for (const m of this.measures) {
        if (m.start < t0 || m.start > t1) continue;
        const a = measures[m.name] ??= {count: 0, totalMs: 0, maxMs: 0};
        a.count++; a.totalMs += m.duration;
        if (m.duration > a.maxMs) a.maxMs = m.duration;
      }
      // A task overlapping the window counts: the drop runs inside the task
      // that dispatched the pointer-up, which began before it.
      const longTasks = this.longTasks
          .filter(t => t.start + t.duration >= t0 && t.start <= t1)
          .map(t => ({offsetMs: t.start - t0, durationMs: t.duration}));
      return {measures, longTasks};
    }
  };
  try {
    new PerformanceObserver(list => {
      for (const e of list.getEntries()) {
        state.longTasks.push({start: e.startTime, duration: e.duration});
      }
    }).observe({type: 'longtask', buffered: true});
    state.longTaskSupported = true;
  } catch (e) { state.error = String(e); }
  new PerformanceObserver(list => {
    for (const e of list.getEntries()) {
      state.measures.push({name: e.name, start: e.startTime, duration: e.duration});
    }
  }).observe({type: 'measure'});
})();
'''
        .toJS,
  );
}

/// Long tasks and measures between two `performance.now()` readings: the top
/// [top] measure names by total time, plus the client's own spans.
Map<String, Object?> _window(double t0, double t1, {int top = 20}) {
  final raw =
      (jsonDecode(
                _evalString(
                  'JSON.stringify(window.__constellationBench.window($t0, $t1))',
                ),
              )
              as Map)
          .cast<String, dynamic>();
  final measures = (raw['measures'] as Map).cast<String, dynamic>();
  final ranked = measures.entries.toList()
    ..sort(
      (a, b) => ((b.value as Map)['totalMs'] as num).compareTo(
        (a.value as Map)['totalMs'] as num,
      ),
    );
  final longTasks = (raw['longTasks'] as List).cast<Map<String, dynamic>>();
  final durations = [
    for (final t in longTasks) (t['durationMs'] as num).toDouble(),
  ];
  return {
    'longTasksOver50Ms': longTasks.length,
    'longestTaskMs': durations.isEmpty
        ? 0
        : durations.reduce((a, b) => a > b ? a : b),
    'longTasks': longTasks,
    'clientSpans': {
      for (final name in _spanNames)
        if (measures[name] != null) name: measures[name],
    },
    'topMeasuresByTotal': {
      for (final e in ranked.take(top)) e.key: e.value,
    },
  };
}

bool _longTaskSupported() =>
    _evalString(
      'String(window.__constellationBench.longTaskSupported)',
    ) ==
    'true';

Map<String, Object?> _browserEnvironment() =>
    (jsonDecode(
              _evalString('''
JSON.stringify((() => {
  const c = document.createElement('canvas');
  const gl = c.getContext('webgl2') || c.getContext('webgl');
  let renderer = 'none';
  if (gl) {
    const ext = gl.getExtension('WEBGL_debug_renderer_info');
    renderer = ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL)
                   : gl.getParameter(gl.RENDERER);
  }
  return {
    userAgent: navigator.userAgent,
    hardwareConcurrency: navigator.hardwareConcurrency,
    devicePixelRatio: window.devicePixelRatio,
    viewport: [window.innerWidth, window.innerHeight],
    webglRenderer: renderer,
    canvasKit: typeof window.flutterCanvasKit !== 'undefined',
  };
})())
'''),
            )
            as Map)
        .cast<String, Object?>();

void _setProfileObjects({required bool enabled}) {
  debugProfileBuildsEnabled = enabled;
  debugProfileLayoutsEnabled = enabled;
  debugProfilePaintsEnabled = enabled;
}

double _now() => web.window.performance.now();

/// Nearest-rank percentile of [values] in milliseconds.
double _percentile(List<double> values, double p) {
  if (values.isEmpty) return double.nan;
  final sorted = [...values]..sort();
  final rank = (p * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}

double _ms(Duration d) => d.inMicroseconds / 1000;

/// Build (framework, the UI-thread work), raster (CanvasKit, same JS thread
/// on web) and their vsync-to-raster-finish span, per frame.
Map<String, Object?> _summarise(List<FrameTiming> frames) {
  final build = [for (final f in frames) _ms(f.buildDuration)];
  final raster = [for (final f in frames) _ms(f.rasterDuration)];
  final total = [for (final f in frames) _ms(f.totalSpan)];
  Map<String, double> stats(List<double> v) => {
    'max': v.isEmpty ? double.nan : v.reduce((a, b) => a > b ? a : b),
    'p95': _percentile(v, 0.95),
    'p50': _percentile(v, 0.5),
  };
  return {
    'frames': frames.length,
    'buildMsPerFrame': build,
    'rasterMsPerFrame': raster,
    'buildMs': stats(build),
    'rasterMs': stats(raster),
    'totalSpanMs': stats(total),
  };
}

/// Records [FrameTiming]s whose engine frame numbers fall in a window.
///
/// Web batches timings and submits them only after a later frame, so
/// [flush] pumps idle frames until the last frame of the window arrived.
final class _FrameWindow {
  _FrameWindow(this._binding) {
    SchedulerBinding.instance.addTimingsCallback(_record);
  }

  final IntegrationTestWidgetsFlutterBinding _binding;
  final _frames = <FrameTiming>[];
  int _first = 0;
  int _last = 0;

  void _record(List<FrameTiming> timings) => _frames.addAll(timings);

  int get _frameNumber => _binding.platformDispatcher.frameData.frameNumber;

  void open() => _first = _frameNumber;

  void close() => _last = _frameNumber;

  Future<List<FrameTiming>> flush(WidgetTester tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!_frames.any((f) => f.frameNumber >= _last) &&
        DateTime.now().isBefore(deadline)) {
      _binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 100));
    }
    return [
      for (final f in _frames)
        if (f.frameNumber > _first && f.frameNumber <= _last) f,
    ];
  }

  void dispose() => SchedulerBinding.instance.removeTimingsCallback(_record);
}

/// Pumps frames until the graph has no layout job or transition for
/// [stableFrames] frames in a row; returns when that idle run began.
///
/// The layout slicer runs on scheduler tasks and wake-up timers, which do not
/// schedule frames, so `pumpAndSettle` alone can return mid-layout.
Future<double> _pumpUntilLayoutIdle(
  WidgetTester tester,
  ConstellationCubit cubit, {
  int stableFrames = 10,
}) async {
  final controller = cubit.graphController;
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  double? idleSince;
  var idleFrames = 0;
  while (idleFrames < stableFrames) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
        'layout did not settle: ${controller.scene.layoutOutcome}',
      );
    }
    final idle =
        !controller.isLayoutSettling &&
        controller.scene.layoutOutcome is GraphLayoutOutcomeSucceeded;
    if (idle) {
      idleSince ??= _now();
      idleFrames++;
    } else {
      idleSince = null;
      idleFrames = 0;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  return idleSince!;
}

final class _Field implements ConstellationRepositoryPort {
  _Field(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

/// Acknowledges every op after [_ackDelay], like a fast server.
final class _DelayedAckAnchors implements ConstellationAnchorRepositoryPort {
  final acks = <({double at, int ops})>[];
  var _revision = BigInt.one;

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    await Future<void>.delayed(_ackDelay);
    final before = ConstellationAnchorRevision(_revision);
    _revision += BigInt.one;
    final after = ConstellationAnchorRevision(_revision);
    acks.add((at: _now(), ops: ops.length));
    return ConstellationAnchorApplyResult(
      beforeRevision: before,
      afterRevision: after,
      results: [
        for (final op in ops)
          ConstellationAnchorOpResult(
            clientOpId: op.clientOpId,
            status: ConstellationAnchorOpStatus.ok,
            resultingTargetRevision: after,
            target: op.target,
            anchor: op.kind == ConstellationAnchorOpKind.delete
                ? null
                : ConstellationAnchor(
                    target: op.target,
                    position: op.position!,
                    revision: after,
                    placedAt: DateTime.now().toUtc(),
                  ),
          ),
      ],
    );
  }
}

/// The production wiring of ConstellationScreen, with in-memory repositories.
Future<({ConstellationCubit cubit, _DelayedAckAnchors anchors})> _mount(
  int size,
) async {
  final logger = Logger('ConstellationProfileWebBench');
  const env = Env.fromEnvironment();
  final sync = buildTestRealtimeSync();
  final anchors = _DelayedAckAnchors();
  final store = ConstellationStoreFixture(
    _Field(syntheticConstellationField(size: size)),
    accountId: kRefEgo.id,
    clock: ClockService(),
    wakeUp: WakeUpService(),
    realtime: sync.case_,
  ).store;
  final anchorCase = ConstellationAnchorCase(env: env, logger: logger);
  final placementCase = ConstellationPlacementCase(
    anchors,
    store,
    ClockService(),
    WakeUpService(),
    realtime: sync.case_,
    env: env,
    logger: logger,
  );
  final cubit = ConstellationCubit(
    case_: store,
    anchorCase: anchorCase,
    placementCase: placementCase,
    viewer: kRefEgo,
    loadOnCreate: false,
    scene: ConstellationSceneController(
      slicer: FrameSliceScheduler(
        clock: ClockService(),
        wakeUpPort: WakeUpService(),
        controller: AdaptiveSliceController(
          initialUnitCost: const Duration(microseconds: 100),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await cubit.close();
    await anchorCase.dispose();
    await placementCase.dispose();
    await sync.port.dispose();
  });
  await cubit.load();
  return (cubit: cubit, anchors: anchors);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object?>{};

  for (final size in _sizes) {
    testWidgets(
      'profile web: drag, pan and drop → ack → reflow at N = $size',
      (tester) async {
        try {
          await _bench(tester, binding, report, size);
        } catch (error, stack) {
          // Profile builds report failures without details; keep them here.
          ((report['errors'] ??= <String>[]) as List).add(
            'N = $size: $error\n$stack',
          );
          binding.reportData = {_reportKey: report};
          rethrow;
        }
      },
      // A web app builds no semantics tree until assistive technology asks
      // for one; testWidgets would otherwise add that pass to every frame.
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

Future<void> _bench(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Map<String, Object?> report,
  int size,
) async {
  expect(kIsWeb, isTrue, reason: 'This benchmark needs a browser');
  if (report['environment'] == null) {
    _installObservers();
    report['environment'] = {
      ..._browserEnvironment(),
      'buildMode': kProfileMode
          ? 'profile'
          : kReleaseMode
          ? 'release'
          : 'debug',
      'wasm': const bool.fromEnvironment('dart.tool.dart2wasm'),
      'surface': [_surface.width, _surface.height],
      'fixtureSeed': kSyntheticFieldDefaultSeed,
      'dragFrames': _dragFrames,
      'panFrames': _panFrames,
      'ackDelayMs': _ackDelay.inMilliseconds,
      'profileObjects': _profileObjects,
      'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    };
  }
  expect(kProfileMode, isTrue, reason: 'Run flutter drive --profile');
  final (:cubit, :anchors) = await _mount(size);
  await pumpConstellationBody(tester, cubit, size: _surface);
  await _pumpUntilLayoutIdle(tester, cubit);
  await tester.pumpAndSettle();
  final controller = cubit.graphController;
  final rendered = controller.renderSnapshot.topology.nodesById.length;

  // Pinned person p0 (the synthetic field pins the first 10%), centred.
  final target = ConstellationAnchorTarget.person('p0');
  final graphId = 'fp:${target.id}';
  cubit.panCameraTo(controller.getPositionForId(graphId));
  await tester.pumpAndSettle();
  await _pumpUntilLayoutIdle(tester, cubit);
  final node = find.byKey(
    TestIds.key(TestIds.graphNode(target.graphNodeId)),
  );
  expect(node, findsOneWidget);

  final frames = _FrameWindow(binding);
  addTearDown(frames.dispose);

  // --- Grab → drag → drop → ack → reflow, first with a mouse, then with a
  // touch on the same (still pinned) person.
  final mouse = await _dragCycle(
    tester,
    cubit,
    anchors,
    frames,
    target: target,
    kind: PointerDeviceKind.mouse,
  );
  final touch = await _dragCycle(
    tester,
    cubit,
    anchors,
    frames,
    target: target,
    kind: PointerDeviceKind.touch,
  );

  // --- Pan: one camera translation per frame, nothing held.
  final camera = tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!;
  final panAt = _now();
  frames.open();
  for (var i = 0; i < _panFrames; i++) {
    camera.value = camera.value.clone()
      ..setTranslationRaw(
        camera.value.storage[12] + 4,
        camera.value.storage[13] + 2,
        camera.value.storage[14],
      );
    await tester.pump(const Duration(milliseconds: 16));
  }
  frames.close();
  final panEnd = _now();
  final panTimings = await frames.flush(tester);
  // Observer callbacks are queued tasks; let them run.
  await tester.pump(const Duration(milliseconds: 200));

  report['n$size'] = {
    'size': size,
    'renderedNodeCount': rendered,
    'longTaskSupported': _longTaskSupported(),
    // The mouse cycle's drag and drop windows, as before.
    'drag': mouse.drag,
    'pan': {..._summarise(panTimings), ..._window(panAt, panEnd)},
    'dropAckReflow': mouse.dropAckReflow,
    'cycles': {'mouse': mouse.cycle, 'touch': touch.cycle},
  };
  report['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
  binding.reportData = {_reportKey: report};

  expect(panTimings, hasLength(greaterThanOrEqualTo(_panFrames)));
  await tester.pumpWidget(const SizedBox.shrink());
}

/// Phases of one held-node cycle, in order. A long task belongs to the phase
/// in which it started, except that a task spanning the pointer-up or the
/// ack belongs to the phase that event opens (the event ran inside it).
const _phases = ['grab', 'drag', 'drop', 'ack', 'reflow'];

/// Every main-thread task over 50 ms from pointer-down through the reflow
/// settling, each labelled with its phase; offsets are from pointer-down.
///
/// Boundaries (`performance.now()`): `firstMovedFrame` is read right after
/// the pumped frame that first drew the node off its start position,
/// `pointerUp` right before the release is dispatched, `ack` inside the
/// placement write's response, `ackApplied` after the first pumped frame in
/// which the cubit no longer holds a pending write, `reflowSettled` when the
/// layout went idle, `end` after the final `pumpAndSettle`.
Map<String, Object?> _phaseLongTasks(Map<String, double> at) {
  final down = at['pointerDown']!;
  final raw =
      (jsonDecode(
                _evalString(
                  'JSON.stringify(window.__constellationBench'
                  '.window($down, ${at['end']}))',
                ),
              )
              as Map)
          .cast<String, dynamic>();
  String phaseOf(double start, double end) {
    bool spans(String key) => start <= at[key]! && at[key]! <= end;
    if (spans('ack')) return 'ack';
    if (spans('pointerUp')) return 'drop';
    if (start < at['firstMovedFrame']!) return 'grab';
    if (start < at['pointerUp']!) return 'drag';
    if (start < at['ack']!) return 'drop';
    if (start <= at['ackApplied']!) return 'ack';
    return 'reflow';
  }

  final tasks = [
    for (final t in (raw['longTasks'] as List).cast<Map<String, dynamic>>())
      () {
        final offset = (t['offsetMs'] as num).toDouble();
        final duration = (t['durationMs'] as num).toDouble();
        return {
          'phase': phaseOf(down + offset, down + offset + duration),
          'offsetMs': offset,
          'durationMs': duration,
        };
      }(),
  ];
  return {
    'phaseBoundariesMs': {
      for (final e in at.entries) e.key: e.value - down,
    },
    'longTasks': tasks,
    'longTasksByPhase': {
      for (final phase in _phases)
        phase: () {
          final d = [
            for (final t in tasks)
              if (t['phase'] == phase) t['durationMs']! as double,
          ];
          return {
            'count': d.length,
            'maxMs': d.isEmpty ? 0 : d.reduce((a, b) => a > b ? a : b),
            'totalMs': d.fold<double>(0, (a, b) => a + b),
            'durationsMs': d,
          };
        }(),
    },
  };
}

/// Holds pinned [target] with a pointer of [kind], drags it for
/// [_dragFrames] frames and releases it, then waits for the ack and the
/// reflow to settle.
Future<
  ({
    Map<String, Object?> drag,
    Map<String, Object?> dropAckReflow,
    Map<String, Object?> cycle,
  })
>
_dragCycle(
  WidgetTester tester,
  ConstellationCubit cubit,
  _DelayedAckAnchors anchors,
  _FrameWindow frames, {
  required ConstellationAnchorTarget target,
  required PointerDeviceKind kind,
}) async {
  final controller = cubit.graphController;
  final graphId = 'fp:${target.id}';
  final node = find.byKey(
    TestIds.key(TestIds.graphNode(target.graphNodeId)),
  );
  expect(node, findsOneWidget);
  final at = <String, double>{};

  // --- Grab: pointer-down, one move past the slop, then frames until one
  // draws the node away from where it was held.
  final centre = tester.getCenter(node);
  final heldAt = controller.getPositionForId(graphId);
  // The finders above walk the whole element tree (> 50 ms at N = 300);
  // one idle frame keeps that harness task out of the grab.
  await tester.pump(const Duration(milliseconds: 16));
  at['pointerDown'] = _now();
  final gesture = await tester.startGesture(centre, kind: kind);
  // Past kTouchSlop (18) in scene space at any camera scale.
  await gesture.moveBy(const Offset(48, 0));
  final dispatchedAt = _now();
  var grabPumps = 0;
  final grabDeadline = DateTime.now().add(const Duration(seconds: 30));
  while (controller.getPositionForId(graphId) == heldAt) {
    if (DateTime.now().isAfter(grabDeadline)) {
      throw StateError('the held node never moved ($kind)');
    }
    await tester.pump(const Duration(milliseconds: 16));
    grabPumps++;
  }
  if (grabPumps == 0) {
    // Moved on dispatch: the next frame is the first that draws it.
    await tester.pump(const Duration(milliseconds: 16));
    grabPumps++;
  }
  at['firstMovedFrame'] = _now();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    cubit.state.placementPhase,
    ConstellationPlacementPhase.draggingExisting,
    reason: 'the pointer must hold the node before measuring ($kind)',
  );

  // --- Drag: one pointer move per frame.
  final dragStart = controller.getPositionForId(graphId);
  _setProfileObjects(enabled: _profileObjects);
  final dragAt = _now();
  frames.open();
  for (var i = 0; i < _dragFrames; i++) {
    await gesture.moveBy(const Offset(2, 1));
    await tester.pump(const Duration(milliseconds: 16));
  }
  frames.close();
  final dragEnd = _now();
  final dragTimings = await frames.flush(tester);
  final dragMoved = controller.getPositionForId(graphId) - dragStart;
  expect(
    dragMoved.distance,
    greaterThan(10),
    reason: 'the held node must follow the pointer ($kind)',
  );
  expect(dragTimings, hasLength(greaterThanOrEqualTo(_dragFrames)));

  // --- Drop → ack → reflow.
  final acksBefore = anchors.acks.length;
  frames.open();
  at['pointerUp'] = _now();
  await gesture.up();
  await tester.pump();
  final ackDeadline = DateTime.now().add(const Duration(seconds: 20));
  while ((anchors.acks.length == acksBefore ||
          cubit.state.hasPendingPlacementWrite) &&
      DateTime.now().isBefore(ackDeadline)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(anchors.acks.length, greaterThan(acksBefore));
  at['ack'] = anchors.acks[acksBefore].at;
  at['ackApplied'] = _now();
  at['reflowSettled'] = await _pumpUntilLayoutIdle(tester, cubit);
  await tester.pumpAndSettle();
  frames.close();
  at['end'] = _now();
  _setProfileObjects(enabled: false);
  final dropTimings = await frames.flush(tester);
  expect(cubit.isAnchored(target), isTrue);
  // Observer callbacks are queued tasks; let them run.
  await tester.pump(const Duration(milliseconds: 200));

  final dropAt = at['pointerUp']!;
  final drag = {
    ..._summarise(dragTimings),
    ..._window(dragAt, dragEnd, top: _profileObjects ? 150 : 16),
  };
  final dropAckReflow = {
    ..._summarise(dropTimings),
    ..._window(dropAt, at['reflowSettled']!, top: _profileObjects ? 150 : 24),
    'dropToAckMs': at['ack']! - dropAt,
    'dropToSettledMs': at['reflowSettled']! - dropAt,
  };
  final phases = _phaseLongTasks(at);
  final grabTasks = [
    for (final t in (phases['longTasks']! as List).cast<Map<String, Object>>())
      if (t['phase'] == 'grab') t,
  ];
  return (
    drag: drag,
    dropAckReflow: dropAckReflow,
    cycle: {
      'pointerKind': kind.name,
      'grab': {
        'grabToFirstMovedFrameMs': at['firstMovedFrame']! - at['pointerDown']!,
        'downAndMoveDispatchMs': dispatchedAt - at['pointerDown']!,
        'pumps': grabPumps,
        'longTasks': grabTasks,
      },
      ...phases,
      'drag': {
        for (final key in ['frames', 'buildMs', 'rasterMs', 'totalSpanMs'])
          key: drag[key],
      },
      'dropAckReflow': {
        for (final key in [
          'frames',
          'buildMs',
          'rasterMs',
          'totalSpanMs',
          'dropToAckMs',
          'dropToSettledMs',
        ])
          key: dropAckReflow[key],
      },
    },
  );
}
