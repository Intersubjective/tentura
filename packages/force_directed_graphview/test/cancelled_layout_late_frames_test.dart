import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart'
    show mintGraphLayoutTicket;
import 'package:force_directed_graphview/src/scene_controller.dart';

GraphTopology<String, String> _topology(List<String> nodeIds) =>
    GraphTopology.fromEntries(
      nodes: [
        for (final id in nodeIds)
          GraphSceneNode(
            id: id,
            payload: id,
            size: SceneSize(width: 40, height: 40),
          ),
      ],
      edges: const [],
    );

/// Layout algorithm whose stream the test drives by hand.
final class _ManualLayoutAlgorithm implements SceneLayoutAlgorithm {
  late final StreamController<GraphLayoutFrame> frames;
  late GraphLayoutRequest request;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) {
    this.request = request;
    frames = StreamController<GraphLayoutFrame>();
    return frames.stream;
  }
}

GraphLayoutFrame _frame(
  GraphLayoutRequest request, {
  required int sequence,
  required bool isTerminal,
  Set<GraphNodeId>? only,
  double x = 0,
}) =>
    GraphLayoutFrame(
      ticket: request.ticket,
      sequence: sequence,
      positions: {
        for (final id in only ?? request.nodeIds) id: ScenePoint(x: x, y: 0),
      },
      isTerminal: isTerminal,
    );

Future<void> _pump() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final canvas = SceneSize(width: 500, height: 500);

  group('frames arriving after a layout is cancelled', () {
    test(
      'frame ingress stream drops a protocol-violating frame once its '
      'subscriber has cancelled',
      () async {
        final owner = Object();
        final request = GraphLayoutRequest(
          ticket: mintGraphLayoutTicket(
            owner: owner,
            topologyRevision: 1,
            generation: 1,
          ),
          canvasSize: canvas,
          nodesById: {
            'a': GraphLayoutNode(
              id: 'a',
              size: SceneSize(width: 10, height: 10),
              simulationFixed: false,
            ),
            'b': GraphLayoutNode(
              id: 'b',
              size: SceneSize(width: 10, height: 10),
              simulationFixed: false,
            ),
          },
          edgesById: const {},
        );
        final source = StreamController<GraphLayoutFrame>();
        final uncaught = <Object>[];
        final received = <GraphLayoutFrame>[];
        final errors = <Object>[];

        await runZonedGuarded(() async {
          final sub = GraphLayoutFrameIngress.enforce(source.stream, request)
              .listen(received.add, onError: errors.add);
          source.add(_frame(request, sequence: 0, isTerminal: false));
          await _pump();
          unawaited(sub.cancel());
          // Partial positions: would violate the protocol if validated.
          source.add(
            _frame(request, sequence: 1, isTerminal: false, only: {'a'}),
          );
          await _pump();
        }, (error, _) => uncaught.add(error));

        expect(received, hasLength(1));
        expect(errors, isEmpty);
        expect(uncaught, isEmpty);
      },
    );

    test(
      'controller drops a malformed frame delivered after cancelActiveLayout '
      'without changing any scene state',
      () async {
        final controller = GraphSceneController<String, String>();
        controller.applyTopology(_topology(['a', 'b']));
        final algorithm = _ManualLayoutAlgorithm();
        final uncaught = <Object>[];
        var notifications = 0;

        await runZonedGuarded(() async {
          final ticket = controller.requestLayout(algorithm, canvasSize: canvas);
          algorithm.frames.add(
            _frame(algorithm.request, sequence: 0, isTerminal: false, x: 3),
          );
          await _pump();
          expect(controller.cancelActiveLayout(), isTrue);

          final before = controller.snapshot;
          final outcomeAtCancel = controller.layoutOutcome;
          expect(outcomeAtCancel, isA<GraphLayoutOutcomeCancelled>());
          controller.addListener(() => notifications++);

          // Missing positions: would violate the protocol if it were validated.
          algorithm.frames.add(
            _frame(
              algorithm.request,
              sequence: 1,
              isTerminal: false,
              only: {'a'},
            ),
          );
          await _pump();

          final after = controller.snapshot;
          expect(controller.layoutOutcome, same(outcomeAtCancel));
          expect(
            (controller.layoutOutcome as GraphLayoutOutcomeCancelled).ticket,
            ticket,
          );
          expect(after.sceneRevision, before.sceneRevision);
          expect(after.layout?.revision, before.layout?.revision);
          expect(after.layout?.positions, before.layout?.positions);
          expect(after.seedPositions, before.seedPositions);
          expect(notifications, 0);
        }, (error, _) => uncaught.add(error));

        expect(uncaught, isEmpty);
      },
    );

    test(
      'controller drops a well-formed terminal frame delivered after '
      'cancelActiveLayout without changing any scene state',
      () async {
        final controller = GraphSceneController<String, String>();
        controller.applyTopology(_topology(['a', 'b']));
        final algorithm = _ManualLayoutAlgorithm();
        final uncaught = <Object>[];
        var notifications = 0;

        await runZonedGuarded(() async {
          controller.requestLayout(algorithm, canvasSize: canvas);
          await _pump();
          controller.cancelActiveLayout();
          final before = controller.snapshot;
          final outcomeAtCancel = controller.layoutOutcome;
          controller.addListener(() => notifications++);

          algorithm.frames.add(
            _frame(algorithm.request, sequence: 0, isTerminal: true, x: 9),
          );
          await _pump();

          final after = controller.snapshot;
          expect(controller.layoutOutcome, same(outcomeAtCancel));
          expect(after.layout, isNull);
          expect(after.sceneRevision, before.sceneRevision);
          expect(notifications, 0);
        }, (error, _) => uncaught.add(error));

        expect(uncaught, isEmpty);
      },
    );

    test(
      'controller drops frames from a superseded layout and keeps the '
      'replacement layout active and unaffected',
      () async {
        final controller = GraphSceneController<String, String>();
        controller.applyTopology(_topology(['a', 'b']));
        final first = _ManualLayoutAlgorithm();
        final second = _ManualLayoutAlgorithm();
        final uncaught = <Object>[];
        var notifications = 0;

        await runZonedGuarded(() async {
          controller.requestLayout(first, canvasSize: canvas);
          first.frames.add(
            _frame(first.request, sequence: 0, isTerminal: false, x: 1),
          );
          await _pump();
          final secondTicket =
              controller.requestLayout(second, canvasSize: canvas);
          second.frames.add(
            _frame(second.request, sequence: 0, isTerminal: false, x: 2),
          );
          await _pump();

          final before = controller.snapshot;
          final outcomeBefore = controller.layoutOutcome;
          expect(
            (outcomeBefore as GraphLayoutOutcomeRunning).ticket,
            secondTicket,
          );
          controller.addListener(() => notifications++);

          // Late frames from the superseded layout: a repeated sequence
          // number and a partial position set.
          first.frames
            ..add(_frame(first.request, sequence: 0, isTerminal: false, x: 7))
            ..add(
              _frame(
                first.request,
                sequence: 5,
                isTerminal: false,
                only: {'a'},
              ),
            );
          await _pump();

          final after = controller.snapshot;
          expect(controller.layoutOutcome, same(outcomeBefore));
          expect(after.layout?.ticket, secondTicket);
          expect(after.layout?.revision, before.layout?.revision);
          expect(after.layout?.positions, before.layout?.positions);
          expect(after.sceneRevision, before.sceneRevision);
          expect(notifications, 0);

          // The replacement layout still accepts its own frames.
          second.frames.add(
            _frame(second.request, sequence: 1, isTerminal: true, x: 4),
          );
          await _pump();
          expect(controller.layoutOutcome, isA<GraphLayoutOutcomeSucceeded>());
          expect(controller.snapshot.layout?.positions['a'], ScenePoint(x: 4, y: 0));
        }, (error, _) => uncaught.add(error));

        expect(uncaught, isEmpty);
      },
    );
  });
}
