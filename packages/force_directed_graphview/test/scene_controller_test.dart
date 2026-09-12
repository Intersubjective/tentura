import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene_controller.dart';

GraphTopology<String, String> _topology({
  required List<String> nodeIds,
  List<(String edgeId, String src, String dst)> edges = const [],
}) {
  return GraphTopology.fromEntries(
    nodes: [
      for (final id in nodeIds)
        GraphSceneNode(
          id: id,
          payload: id,
          size: SceneSize(width: 40, height: 40),
        ),
    ],
    edges: [
      for (final (edgeId, src, dst) in edges)
        GraphSceneEdge(
          id: edgeId,
          sourceId: src,
          destinationId: dst,
          payload: edgeId,
        ),
    ],
  );
}

SceneLayoutAlgorithm _oneShotTerminal({
  required Map<GraphNodeId, ScenePoint> positions,
}) {
  return _OneShotLayoutAlgorithm(positions);
}

final class _OneShotLayoutAlgorithm implements SceneLayoutAlgorithm {
  _OneShotLayoutAlgorithm(this.positions);

  final Map<GraphNodeId, ScenePoint> positions;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: positions,
      isTerminal: true,
    );
  }
}

final class _SyncThenAsyncLayoutAlgorithm implements SceneLayoutAlgorithm {
  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds)
          id: ScenePoint(x: 1, y: 1),
      },
      isTerminal: false,
    );
    await Future<void>.delayed(Duration.zero);
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 1,
      positions: {
        for (final id in request.nodeIds)
          id: ScenePoint(x: 9, y: 9),
      },
      isTerminal: true,
    );
  }
}

final class _MalformedThenTerminalAlgorithm implements SceneLayoutAlgorithm {
  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds)
          if (id != request.nodeIds.first) id: ScenePoint(x: 0, y: 0),
      },
      isTerminal: false,
    );
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 1,
      positions: {
        for (final id in request.nodeIds)
          id: ScenePoint(x: 5, y: 5),
      },
      isTerminal: true,
    );
  }
}

final class _ForeignTicketLayoutAlgorithm implements SceneLayoutAlgorithm {
  _ForeignTicketLayoutAlgorithm(this.foreignTicket);

  final GraphLayoutTicket foreignTicket;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    yield GraphLayoutFrame(
      ticket: foreignTicket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds)
          id: ScenePoint(x: 1, y: 1),
      },
      isTerminal: true,
    );
  }
}

Future<void> _settleLayout(GraphSceneController<dynamic, dynamic> controller) async {
  for (var i = 0; i < 20; i++) {
    if (controller.layoutOutcome is GraphLayoutOutcomeSucceeded ||
        controller.layoutOutcome is GraphLayoutOutcomeFailed ||
        controller.layoutOutcome is GraphLayoutOutcomeCancelled) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  final canvas = SceneSize(width: 500, height: 500);

  test('empty topology has no resolved positions', () {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: []));
    expect(controller.resolvePosition('a'), isNull);
    expect(controller.snapshot.topology.isEmpty, isTrue);
  });

  test('payload-only replacement preserves layout position and ticket', () async {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a']));
    final ticket = controller.requestLayout(
      _oneShotTerminal(positions: {'a': ScenePoint(x: 10, y: 20)}),
      canvasSize: canvas,
    );
    await _settleLayout(controller);
    expect(controller.layoutOutcome, isA<GraphLayoutOutcomeSucceeded>());

    final beforeLayout = controller.snapshot.layout!;
    controller.applyTopology(
      GraphTopology.fromEntries(
        nodes: [
          GraphSceneNode(
            id: 'a',
            payload: 'a-refreshed',
            size: SceneSize(width: 40, height: 40),
          ),
        ],
        edges: const [],
      ),
    );

    expect(controller.snapshot.layout, beforeLayout);
    expect(controller.resolvePosition('a'), ScenePoint(x: 10, y: 20));
    expect(
      (controller.layoutOutcome as GraphLayoutOutcomeSucceeded).ticket,
      ticket,
    );
  });

  test('topology removal clears layout and presentation state', () {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a']));
    controller.requestLayout(
      _oneShotTerminal(positions: {'a': ScenePoint(x: 1, y: 2)}),
      canvasSize: canvas,
    );
    final token = controller.beginPresentation(
      'a',
      ScenePoint(x: 99, y: 99),
    );
    expect(token, isNotNull);

    controller.applyTopology(_topology(nodeIds: []));
    expect(controller.snapshot.layout, isNull);
    expect(controller.resolvePosition('a'), isNull);
    expect(controller.snapshot.presentation.overrides, isEmpty);
  });

  test('terminal layout clears matching held override in one notification', () async {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a']));
    final token = controller.beginPresentation(
      'a',
      ScenePoint(x: 50, y: 60),
    );

    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.requestLayout(
      _oneShotTerminal(positions: {'a': ScenePoint(x: 10, y: 20)}),
      canvasSize: canvas,
      releaseOnTerminal: {token},
    );
    await _settleLayout(controller);

    expect(notifications, greaterThanOrEqualTo(1));
    expect(controller.snapshot.presentation.overrides, isEmpty);
    expect(controller.snapshot.presentation.holds, isEmpty);
    expect(controller.resolvePosition('a'), ScenePoint(x: 10, y: 20));
  });

  test('layout failure preserves presentation override', () async {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a', 'b']));
    controller.beginPresentation('a', ScenePoint(x: 7, y: 8));

    controller.requestLayout(
      _MalformedThenTerminalAlgorithm(),
      canvasSize: canvas,
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.layoutOutcome, isA<GraphLayoutOutcomeFailed>());
    expect(controller.snapshot.presentation.overrides['a'], ScenePoint(x: 7, y: 8));
  });

  test('superseded layout preserves override until explicit cancel', () async {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a']));
    final token = controller.beginPresentation(
      'a',
      ScenePoint(x: 3, y: 4),
    );

    final slow = _SlowLayoutAlgorithm();
    final first = controller.requestLayout(slow, canvasSize: canvas);
    controller.requestLayout(
      _oneShotTerminal(positions: {'a': ScenePoint(x: 1, y: 1)}),
      canvasSize: canvas,
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.cancelLayout(first), isFalse);
    expect(controller.snapshot.presentation.overrides['a'], ScenePoint(x: 3, y: 4));
    expect(controller.cancelPresentation(token), isTrue);
    expect(controller.snapshot.presentation.overrides, isEmpty);
  });

  test('synchronous layout stream respects holds registered before subscribe',
      () async {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a']));
    final token = controller.beginPresentation(
      'a',
      ScenePoint(x: 40, y: 40),
    );

    controller.requestLayout(
      _oneShotTerminal(positions: {'a': ScenePoint(x: 0, y: 0)}),
      canvasSize: canvas,
      releaseOnTerminal: {token},
    );
    await _settleLayout(controller);

    expect(controller.snapshot.presentation.overrides, isEmpty);
    expect(controller.resolvePosition('a'), ScenePoint(x: 0, y: 0));
  });

  test('rejects stale foreign ticket frames', () async {
    final other = GraphSceneController<String, String>();
    other.applyTopology(_topology(nodeIds: ['a']));
    other.requestLayout(_SlowLayoutAlgorithm(), canvasSize: canvas);
    final foreignTicket =
        (other.layoutOutcome as GraphLayoutOutcomeRunning).ticket;

    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a']));
    controller.requestLayout(
      _ForeignTicketLayoutAlgorithm(foreignTicket),
      canvasSize: canvas,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.layoutOutcome, isA<GraphLayoutOutcomeFailed>());
    expect(controller.snapshot.layout, isNull);
  });

  test('two controllers isolate tickets and layout state', () async {
    final a = GraphSceneController<String, String>();
    final b = GraphSceneController<String, String>();
    a.applyTopology(_topology(nodeIds: ['a']));
    b.applyTopology(_topology(nodeIds: ['a']));

    a.requestLayout(
      _oneShotTerminal(positions: {'a': ScenePoint(x: 1, y: 1)}),
      canvasSize: canvas,
    );
    await _settleLayout(a);
    expect(a.resolvePosition('a'), ScenePoint(x: 1, y: 1));
    expect(b.resolvePosition('a'), isNull);
  });

  test('disposal ignores late layout callbacks', () async {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a']));
    controller.requestLayout(_SlowLayoutAlgorithm(), canvasSize: canvas);

    var notifiedAfterDispose = false;
    controller.addListener(() => notifiedAfterDispose = true);
    controller.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(notifiedAfterDispose, isFalse);
  });

  test('intermediate frames update layout before terminal', () async {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a', 'b']));
    controller.requestLayout(_SyncThenAsyncLayoutAlgorithm(), canvasSize: canvas);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.layoutOutcome, isA<GraphLayoutOutcomeSucceeded>());
    expect(controller.resolvePosition('a'), ScenePoint(x: 9, y: 9));
  });

  test('stale presentation token cannot update', () {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a']));
    final first = controller.beginPresentation(
      'a',
      ScenePoint(x: 1, y: 1),
    );
    final second = controller.beginPresentation(
      'a',
      ScenePoint(x: 2, y: 2),
    );
    expect(controller.updatePresentation(first, ScenePoint(x: 9, y: 9)), isFalse);
    expect(
      controller.updatePresentation(second, ScenePoint(x: 3, y: 3)),
      isTrue,
    );
    expect(controller.resolvePosition('a'), ScenePoint(x: 3, y: 3));
  });
}

final class _SlowLayoutAlgorithm implements SceneLayoutAlgorithm {
  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds)
          id: ScenePoint(x: 2, y: 2),
      },
      isTerminal: true,
    );
  }
}
