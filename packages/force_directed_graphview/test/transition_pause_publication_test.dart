import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/fixed_scene_layout.dart';
import 'support/int_graph_controller.dart';

typedef _Controller = GraphController<Node<int>, Edge<Node<int>, void>>;

const _duration = Duration(milliseconds: 400);

Future<_Controller> _mountGraph(
  WidgetTester tester, {
  Map<GraphNodeId, ScenePoint>? positions,
}) async {
  final controller = testIntGraphController();
  final initial = positions ?? {'1': ScenePoint(x: 100, y: 100)};
  controller.reconcileTopology(
    {for (final id in initial.keys) Node<int>(data: int.parse(id), size: 20)},
    {},
    layoutOnTopologyChange: false,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: GraphView<Node<int>, Edge<Node<int>, void>>(
        controller: controller,
        canvasSize: const GraphCanvasSize.fixed(Size(500, 500)),
        layoutAlgorithm: FixedSceneLayoutAlgorithm(initial),
        layoutTransitionDuration: _duration,
        layoutTransitionCurve: Curves.linear,
        nodeBuilder: (context, node) => const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(controller.scene.layoutOutcome, isA<GraphLayoutOutcomeSucceeded>());
  for (final entry in initial.entries) {
    expect(
      controller.getPositionForId(entry.key),
      Offset(entry.value.x, entry.value.y),
    );
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  return controller;
}

// Dynamic dispatch keeps the tests runnable before these public APIs exist.
// There is deliberately no fallback to the destructive interaction stop.
void _pause(_Controller controller) =>
    // ignore: avoid_dynamic_calls
    (controller as dynamic).pauseTransitions();

void _resume(_Controller controller) =>
    // ignore: avoid_dynamic_calls
    (controller as dynamic).resumeTransitions();

void _animateTo(
  _Controller controller,
  Map<GraphNodeId, ScenePoint> targets, {
  Set<GraphNodeId> skip = const {},
}) =>
    // ignore: avoid_dynamic_calls
    (controller as dynamic).animateTo(targets, skip: skip);

// Own the microtask queue so layout acceptance can be separated from the
// controller's queued publication without sleeps or private hooks.
final class _QueuedMicrotasks {
  _QueuedMicrotasks() {
    _zone = Zone.current.fork(
      specification: ZoneSpecification(
        scheduleMicrotask: (self, parent, zone, callback) {
          _pending.add(() => zone.runGuarded(callback));
        },
      ),
    );
  }

  final _pending = Queue<VoidCallback>();
  late final Zone _zone;

  void run(VoidCallback callback) => _zone.run(callback);

  void acceptLayout(_Controller controller, SceneLayoutAlgorithm algorithm) {
    GraphLayoutTicket? ticket;
    run(() => ticket = controller.requestSceneLayout(algorithm: algorithm));
    expect(ticket, isNotNull);
    for (var i = 0; i < 100; i++) {
      final outcome = controller.scene.layoutOutcome;
      if (outcome is GraphLayoutOutcomeSucceeded && outcome.ticket == ticket) {
        expect(
          _pending,
          isNotEmpty,
          reason: 'Publication must still be queued',
        );
        return;
      }
      expect(_pending, isNotEmpty, reason: 'Layout must reach acceptance');
      _pending.removeFirst()();
    }
    fail('Layout did not reach acceptance within 100 microtasks');
  }

  void flush() {
    for (var i = 0; i < 200 && _pending.isNotEmpty; i++) {
      _pending.removeFirst()();
    }
    expect(_pending, isEmpty, reason: 'Publication must not loop indefinitely');
  }

  void completeLayout(_Controller controller, VoidCallback complete) {
    run(complete);
    for (var count = 0; count < 100; count++) {
      if (controller.scene.layoutOutcome is GraphLayoutOutcomeSucceeded) return;
      if (_pending.isEmpty) break;
      _pending.removeFirst()();
    }
    fail('Delayed layout did not reach acceptance');
  }
}

final class _PendingLayout implements SceneLayoutAlgorithm {
  final frames = StreamController<GraphLayoutFrame>();
  late GraphLayoutRequest _request;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) {
    _request = request;
    return frames.stream;
  }

  void complete({Map<GraphNodeId, ScenePoint>? positions}) {
    frames.add(
      GraphLayoutFrame(
        ticket: _request.ticket,
        sequence: 0,
        positions: {
          for (final id in _request.nodeIds)
            id: positions?[id] ?? ScenePoint(x: 100, y: 100),
        },
        isTerminal: true,
      ),
    );
    unawaited(frames.close());
  }
}

void main() {
  group('Non-destructive transition pause', () {
    testWidgets('resume retains destinations without an elapsed-time jump',
        (tester) async {
      final controller = await _mountGraph(
        tester,
        positions: {
          '1': ScenePoint(x: 100, y: 100),
          '2': ScenePoint(x: 150, y: 150),
        },
      );
      controller.requestSceneLayout(
        algorithm: FixedSceneLayoutAlgorithm({
          '1': ScenePoint(x: 300, y: 100),
          '2': ScenePoint(x: 150, y: 350),
        }),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final paused = controller.getPositionForId('1');
      final pausedSecond = controller.getPositionForId('2');
      expect(paused.dx, greaterThan(100));
      expect(paused.dx, lessThan(300));
      expect(pausedSecond.dy, greaterThan(150));
      expect(pausedSecond.dy, lessThan(350));

      _pause(controller);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.getPositionForId('1'), paused);
      expect(controller.getPositionForId('2'), pausedSecond);
      _resume(controller);
      expect(controller.getPositionForId('1'), paused);
      expect(controller.getPositionForId('2'), pausedSecond);
      await tester.pump();
      expect(controller.getPositionForId('1'), paused);
      expect(controller.getPositionForId('2'), pausedSecond);
      await tester.pump(const Duration(milliseconds: 50));
      final resumed = controller.getPositionForId('1');
      expect(resumed.dx, greaterThan(paused.dx));
      expect(resumed.dx, lessThan(300));
      expect(controller.getPositionForId('2').dy, greaterThan(pausedSecond.dy));
      expect(controller.getPositionForId('2').dy, lessThan(350));
      await tester.pumpAndSettle();
      expect(controller.getPositionForId('1'), const Offset(300, 100));
      expect(controller.getPositionForId('2'), const Offset(150, 350));
      expect(controller.isLayoutTransitioning, isFalse);
    });
  });

  group('Queued layout publication guards', () {
    testWidgets('a presentation drag publishes while transitions are paused',
        (tester) async {
      final controller = await _mountGraph(tester);
      final token = controller.beginNodePresentationDragForId(
        '1',
        const Offset(100, 100),
      );
      _pause(controller);
      await tester.pump();
      var publications = 0;
      controller.addListener(() => publications++);

      controller.updateNodePresentationDrag(token, const Offset(180, 140));
      await tester.pump();

      expect(publications, greaterThan(0));
      expect(controller.getPositionForId('1'), const Offset(180, 140));
      _resume(controller);
    });

    testWidgets('deferred frame notification is safe after disposal',
        (tester) async {
      var publications = 0;
      final controller = testIntGraphController()
        ..addListener(() => publications++);
      var queued = false;
      tester.binding.addPersistentFrameCallback((_) {
        if (queued) return;
        queued = true;
        controller
          ..notifyListeners()
          ..dispose();
      });
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(queued, isTrue);
      expect(publications, 0);
      expect(tester.takeException(), isNull);
    });

    for (final supersedeTicket in [false, true]) {
      testWidgets(
        supersedeTicket
            ? 'deferred frame notification rejects a superseded layout ticket'
            : 'deferred frame notification rejects a stale generation',
        (tester) async {
          final controller = await _mountGraph(tester);
          final queue = _QueuedMicrotasks();
          final pending = supersedeTicket ? _PendingLayout() : null;
          var publications = 0;
          void countPublication() => publications++;
          controller.addListener(countPublication);
          addTearDown(() => controller.removeListener(countPublication));

          var queued = false;
          tester.binding.addPersistentFrameCallback((_) {
            if (queued) return;
            queued = true;
            controller.notifyListeners();
            queue.run(() {
              if (pending != null) {
                controller.requestSceneLayout(algorithm: pending);
              } else {
                controller.scene.setPaintOrder(['1']);
              }
            });
          });
          tester.binding.scheduleFrame();
          await tester.pump();
          expect(queued, isTrue);
          expect(publications, 0);

          if (pending != null) queue.run(pending.complete);
          queue.flush();
          await tester.pumpAndSettle();
          expect(publications, greaterThan(0));
        },
      );
    }

    testWidgets('a newer frame notification still publishes once',
        (tester) async {
      final controller = await _mountGraph(tester);
      final queue = _QueuedMicrotasks();
      var publications = 0;
      void countPublication() => publications++;
      controller.addListener(countPublication);
      addTearDown(() => controller.removeListener(countPublication));

      var queued = false;
      tester.binding.addPersistentFrameCallback((_) {
        if (queued) return;
        queued = true;
        controller.notifyListeners();
        queue.run(() => controller.setNodePaintOrder(['1']));
        controller.notifyListeners();
      });
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(queued, isTrue);
      expect(publications, 1);
      queue.flush();
    });

    testWidgets(
      'pause suppresses frame notification and resumes retained destinations',
      (tester) async {
        final controller = await _mountGraph(tester);
        _animateTo(controller, {'1': ScenePoint(x: 300, y: 100)});
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final displayed = controller.getPositionForId('1');
        expect(displayed.dx, greaterThan(100));
        expect(displayed.dx, lessThan(300));

        var publications = 0;
        void countPublication() => publications++;
        controller.addListener(countPublication);
        addTearDown(() => controller.removeListener(countPublication));

        var queued = false;
        late int frozenPublications;
        tester.binding.addPersistentFrameCallback((_) {
          if (queued) return;
          queued = true;
          final beforeQueue = publications;
          controller.notifyListeners();
          expect(publications, beforeQueue);
          _pause(controller);
          frozenPublications = publications;
        });
        tester.binding.scheduleFrame();
        await tester.pump();
        expect(queued, isTrue);
        expect(publications - frozenPublications, 0);
        expect(controller.getPositionForId('1'), displayed);
        await tester.pump(const Duration(seconds: 2));
        expect(publications - frozenPublications, 0);
        expect(controller.getPositionForId('1'), displayed);

        _resume(controller);
        expect(controller.getPositionForId('1'), displayed);
        await tester.pump();
        expect(controller.getPositionForId('1'), displayed);
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.getPositionForId('1').dx, greaterThan(displayed.dx));
        expect(controller.getPositionForId('1').dx, lessThan(300));
        await tester.pumpAndSettle();
        expect(controller.getPositionForId('1'), const Offset(300, 100));
        expect(controller.isLayoutTransitioning, isFalse);
      },
    );

    testWidgets(
      'delayed acceptance freezes progressed geometry and resumes destinations',
      (tester) async {
        final controller = await _mountGraph(
          tester,
          positions: {
            '1': ScenePoint(x: 100, y: 100),
            '2': ScenePoint(x: 150, y: 100),
          },
        );
        _animateTo(controller, {
          '1': ScenePoint(x: 300, y: 100),
          '2': ScenePoint(x: 350, y: 100),
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final requestedPosition = controller.getPositionForId('1');
        final queue = _QueuedMicrotasks();
        final pending = _PendingLayout();
        queue
          ..run(() => controller.requestSceneLayout(algorithm: pending))
          ..flush();
        await tester.pump(const Duration(milliseconds: 100));
        final beforeAcceptance = controller.getPositionForId('1');
        final secondBeforeAcceptance = controller.getPositionForId('2');
        expect(beforeAcceptance.dx, greaterThan(requestedPosition.dx));
        expect(beforeAcceptance.dx, lessThan(300));

        final targets = {
          '1': ScenePoint(x: 400, y: 100),
          '2': ScenePoint(
            x: secondBeforeAcceptance.dx + 2,
            y: secondBeforeAcceptance.dy,
          ),
        };
        queue.completeLayout(
          controller,
          () => pending.complete(positions: targets),
        );
        expect(controller.scene.snapshot.layout!.positions, targets);
        final layoutRequests = controller.relayoutInvocationCount;
        _pause(controller);
        expect(controller.getPositionForId('1'), beforeAcceptance);
        expect(controller.getPositionForId('2'), secondBeforeAcceptance);
        final frozenTransition = controller.renderSnapshot.transition;
        final frozenCamera = controller.cameraRevision.value;
        var publications = 0;
        void countPublication() => publications++;
        controller.addListener(countPublication);
        addTearDown(() => controller.removeListener(countPublication));

        queue.flush();
        await tester.pump(const Duration(seconds: 2));
        expect(publications, 0);
        expect(controller.getPositionForId('1'), beforeAcceptance);
        expect(controller.getPositionForId('2'), secondBeforeAcceptance);
        expect(controller.renderSnapshot.transition, frozenTransition);
        expect(controller.cameraRevision.value, frozenCamera);
        expect(controller.scene.snapshot.layout!.positions, targets);

        queue
          ..run(() => _resume(controller))
          ..flush();
        expect(controller.getPositionForId('1'), beforeAcceptance);
        expect(controller.renderSnapshot.transition!.positions.keys, ['1']);
        expect(
          controller.getPositionForId('2'),
          Offset(targets['2']!.x, targets['2']!.y),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          controller.getPositionForId('1').dx,
          greaterThan(beforeAcceptance.dx),
        );
        expect(controller.getPositionForId('1').dx, lessThan(400));
        expect(publications, greaterThan(0));
        await tester.pumpAndSettle();
        expect(controller.getPositionForId('1'), const Offset(400, 100));
        expect(controller.isLayoutTransitioning, isFalse);
        expect(controller.relayoutInvocationCount, layoutRequests);
      },
    );

    testWidgets(
        'freeze after acceptance suppresses publication '
        'and resume reaches its destination', (tester) async {
      final controller = await _mountGraph(tester);
      final queue = _QueuedMicrotasks();
      var publications = 0;
      void countPublication() => publications++;
      controller.addListener(countPublication);
      addTearDown(() => controller.removeListener(countPublication));

      // Positive control: acceptance is real, and flushing this queue without
      // pausing publishes an animated transition toward the accepted target.
      final initialTicket = controller.scene.snapshot.layout!.ticket;
      queue.acceptLayout(
        controller,
        FixedSceneLayoutAlgorithm({'1': ScenePoint(x: 200, y: 100)}),
      );
      final controlLayout = controller.scene.snapshot.layout!;
      expect(controlLayout.ticket, isNot(initialTicket));
      expect(controlLayout.positions['1'], ScenePoint(x: 200, y: 100));
      expect(controller.isLayoutTransitioning, isFalse);
      publications = 0;
      queue.flush();
      expect(publications, greaterThan(0));
      expect(controller.isLayoutTransitioning, isTrue);
      expect(controller.getPositionForId('1'), const Offset(100, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.getPositionForId('1').dx, greaterThan(100));
      expect(controller.getPositionForId('1').dx, lessThan(200));
      await tester.pumpAndSettle();
      expect(controller.getPositionForId('1'), const Offset(200, 100));

      final beforeAcceptance = controller.getPositionForId('1');
      queue.acceptLayout(
        controller,
        FixedSceneLayoutAlgorithm({'1': ScenePoint(x: 300, y: 100)}),
      );
      final acceptedLayout = controller.scene.snapshot.layout!;
      expect(acceptedLayout.ticket, isNot(controlLayout.ticket));
      expect(acceptedLayout.positions['1'], ScenePoint(x: 300, y: 100));
      expect(controller.isLayoutTransitioning, isFalse);
      final layoutRequests = controller.relayoutInvocationCount;
      _pause(controller);
      final frozenPosition = controller.getPositionForId('1');
      expect(frozenPosition, beforeAcceptance);
      expect(frozenPosition, isNot(const Offset(300, 100)));
      final frozenTransition = controller.renderSnapshot.transition;
      final frozenCamera = controller.cameraRevision.value;
      publications = 0;
      queue.flush();
      await tester.pump(const Duration(seconds: 2));
      expect(publications, 0);
      expect(controller.getPositionForId('1'), frozenPosition);
      expect(controller.renderSnapshot.transition, frozenTransition);
      expect(controller.cameraRevision.value, frozenCamera);

      // The accepted callback has already been drained while frozen. Resume
      // must retain its destination rather than depending on a fresh layout.
      queue
        ..run(() => _resume(controller))
        ..flush();
      expect(controller.getPositionForId('1'), frozenPosition);
      await tester.pump();
      expect(controller.getPositionForId('1'), frozenPosition);
      await tester.pump(const Duration(milliseconds: 50));
      final resumed = controller.getPositionForId('1');
      expect(resumed.dx, greaterThan(frozenPosition.dx));
      expect(resumed.dx, lessThan(300));
      expect(resumed.dy, 100);
      expect(publications, greaterThan(0));
      await tester.pumpAndSettle();
      expect(controller.getPositionForId('1'), const Offset(300, 100));
      expect(controller.isLayoutTransitioning, isFalse);
      expect(controller.relayoutInvocationCount, layoutRequests);
    });

    testWidgets(
        'a newer pending ticket prevents an accepted tween from starting',
        (tester) async {
      final controller = await _mountGraph(tester);
      final queue = _QueuedMicrotasks()
        ..acceptLayout(
          controller,
          FixedSceneLayoutAlgorithm({'1': ScenePoint(x: 300, y: 100)}),
        );
      final pending = _PendingLayout();
      queue.run(() => controller.requestSceneLayout(algorithm: pending));
      final running = controller.scene.layoutOutcome;
      expect(running, isA<GraphLayoutOutcomeRunning>());
      queue.flush();

      try {
        expect(controller.scene.layoutOutcome, same(running));
        expect(controller.renderSnapshot.transition, isNull);
        expect(controller.isLayoutTransitioning, isFalse);
      } finally {
        // Finish the fixture with a valid terminal frame after the assertions.
        queue
          ..run(pending.complete)
          ..flush();
      }
    });

    testWidgets(
        'topology replacement prevents publication from its old generation',
        (tester) async {
      final controller = await _mountGraph(tester);
      final queue = _QueuedMicrotasks()
        ..acceptLayout(
          controller,
          FixedSceneLayoutAlgorithm({'1': ScenePoint(x: 300, y: 100)}),
        )
        ..run(() {
          controller.reconcileTopology(
            {const Node<int>(data: 2, size: 20)},
            {},
            layoutOnTopologyChange: false,
          );
        });
      final replacementPosition = controller.getPositionForId('2');
      queue.flush();

      expect(controller.renderSnapshot.topology.nodesById.keys, ['2']);
      expect(controller.renderSnapshot.transition, isNull);
      expect(controller.isLayoutTransitioning, isFalse);
      expect(controller.getPositionForId('2'), replacementPosition);
    });

    for (final replaceTopology in [false, true]) {
      testWidgets(
          replaceTopology
              ? 'freeze suppresses queued publication from a replaced topology '
                  'and resume does not replay it'
              : 'freeze suppresses queued publication from a superseded ticket '
                  'and resume does not replay it', (tester) async {
        final controller = await _mountGraph(tester);
        final queue = _QueuedMicrotasks()
          ..acceptLayout(
            controller,
            FixedSceneLayoutAlgorithm({'1': ScenePoint(x: 300, y: 100)}),
          );
        final pending = replaceTopology ? null : _PendingLayout();
        if (pending != null) {
          queue.run(() => controller.requestSceneLayout(algorithm: pending));
          expect(
            controller.scene.layoutOutcome,
            isA<GraphLayoutOutcomeRunning>(),
          );
        } else {
          queue.run(() {
            controller.reconcileTopology(
              {const Node<int>(data: 2, size: 20)},
              {},
              layoutOnTopologyChange: false,
            );
          });
        }
        final expectedOutcome = controller.scene.layoutOutcome;
        final remainingId = replaceTopology ? '2' : '1';
        try {
          _pause(controller);
          final frozenPosition = controller.getPositionForId(remainingId);
          final frozenTransition = controller.renderSnapshot.transition;
          final frozenCamera = controller.cameraRevision.value;
          var publications = 0;
          void countPublication() => publications++;
          controller.addListener(countPublication);
          addTearDown(() => controller.removeListener(countPublication));

          queue.flush();
          await tester.pump(const Duration(seconds: 2));
          expect(publications, 0);
          expect(controller.getPositionForId(remainingId), frozenPosition);
          expect(controller.renderSnapshot.transition, frozenTransition);
          expect(controller.cameraRevision.value, frozenCamera);

          queue
            ..run(() => _resume(controller))
            ..flush();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(controller.getPositionForId(remainingId), frozenPosition);
          expect(controller.isLayoutTransitioning, isFalse);
          expect(controller.scene.layoutOutcome, same(expectedOutcome));
          expect(
            controller.renderSnapshot.topology.nodesById.keys,
            [remainingId],
          );
          if (replaceTopology) {
            expect(
              controller.renderSnapshot.transition?.positions
                      .containsKey('1') ??
                  false,
              isFalse,
            );
          }
        } finally {
          if (pending != null) {
            queue
              ..run(pending.complete)
              ..flush();
          }
        }
      });
    }
  });

  group('Thresholded node transitions', () {
    testWidgets('only distances greater than two pixels are tweened',
        (tester) async {
      final controller = await _mountGraph(
        tester,
        positions: {
          '1': ScenePoint(x: 100, y: 100),
          '2': ScenePoint(x: 150, y: 100),
          '3': ScenePoint(x: 200, y: 100),
          '4': ScenePoint(x: 250, y: 100),
        },
      );
      _animateTo(controller, {
        '1': ScenePoint(x: 101, y: 100),
        '2': ScenePoint(x: 152, y: 100),
        '3': ScenePoint(x: 202.01, y: 100),
        // Both axes are below two pixels; Euclidean distance exceeds two.
        '4': ScenePoint(x: 251.5, y: 101.5),
      });
      await tester.pump();

      final transitioning = controller.renderSnapshot.transition!.positions;
      expect(transitioning.keys, unorderedEquals(['3', '4']));
      expect(controller.getPositionForId('1'), const Offset(101, 100));
      expect(controller.getPositionForId('2'), const Offset(152, 100));
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.getPositionForId('3').dx, greaterThan(200));
      expect(controller.getPositionForId('3').dx, lessThan(202.01));
      await tester.pumpAndSettle();
      expect(controller.getPositionForId('3'), const Offset(202.01, 100));
      expect(controller.getPositionForId('4'), const Offset(251.5, 101.5));
    });

    testWidgets('skipped nodes keep their displayed position while others move',
        (tester) async {
      final controller = await _mountGraph(
        tester,
        positions: {
          '1': ScenePoint(x: 100, y: 100),
          '2': ScenePoint(x: 150, y: 100),
        },
      );
      _animateTo(
        controller,
        {
          '1': ScenePoint(x: 300, y: 100),
          '2': ScenePoint(x: 350, y: 100),
        },
        skip: {'1'},
      );
      await tester.pump();
      expect(controller.renderSnapshot.transition!.positions.keys, ['2']);
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.getPositionForId('1'), const Offset(100, 100));
      expect(controller.getPositionForId('2').dx, greaterThan(150));
      expect(controller.getPositionForId('2').dx, lessThan(350));
      await tester.pumpAndSettle();
      expect(controller.getPositionForId('1'), const Offset(100, 100));
      expect(controller.getPositionForId('2'), const Offset(350, 100));
    });

    testWidgets(
        'retargeting starts and measures distance from displayed positions',
        (tester) async {
      final controller = await _mountGraph(tester);
      _animateTo(controller, {'1': ScenePoint(x: 300, y: 100)});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final displayed = controller.getPositionForId('1');
      expect(displayed.dx, greaterThan(100));
      expect(displayed.dx, lessThan(300));

      _animateTo(controller, {'1': ScenePoint(x: 400, y: 100)});
      expect(controller.getPositionForId('1'), displayed);
      await tester.pump();
      expect(controller.getPositionForId('1'), displayed);
      await tester.pump(const Duration(milliseconds: 50));
      final current = controller.getPositionForId('1');
      expect(current.dx, greaterThan(displayed.dx));
      expect(current.dx, lessThan(400));

      final nearby = ScenePoint(x: current.dx + 2, y: current.dy);
      _animateTo(controller, {'1': nearby});
      expect(controller.getPositionForId('1'), Offset(nearby.x, nearby.y));
      expect(controller.isLayoutTransitioning, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.getPositionForId('1'), Offset(nearby.x, nearby.y));
    });
  });
}
