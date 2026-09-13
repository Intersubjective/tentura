import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene_controller.dart';

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

GraphTopology<String, String> _topology({
  required List<String> nodeIds,
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
    edges: const [],
  );
}

final class _SyncThrowLayoutAlgorithm implements SceneLayoutAlgorithm {
  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) {
    throw StateError('synchronous layout failure');
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

void main() {
  _logMemory('scene_controller_layout_lifecycle before');

  final canvas = SceneSize(width: 500, height: 500);

  test('synchronous layout throw becomes GraphLayoutOutcomeFailed', () async {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a']));
    controller.requestLayout(
      _SyncThrowLayoutAlgorithm(),
      canvasSize: canvas,
    );
    expect(controller.layoutOutcome, isA<GraphLayoutOutcomeFailed>());
    expect(controller.snapshot.layout, isNull);
  });

  test('sync layout failure clears active ticket and preserves presentation',
      () async {
    final controller = GraphSceneController<String, String>();
    controller.applyTopology(_topology(nodeIds: ['a']));
    controller.beginPresentation('a', ScenePoint(x: 4, y: 5));
    controller.requestLayout(
      _SyncThrowLayoutAlgorithm(),
      canvasSize: canvas,
    );
    expect(controller.layoutOutcome, isA<GraphLayoutOutcomeFailed>());
    expect(
      controller.snapshot.presentation.overrides['a'],
      ScenePoint(x: 4, y: 5),
    );
  });

  test('malformed stream layout failure still preserves presentation override',
      () async {
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

  tearDownAll(() {
    _logMemory('scene_controller_layout_lifecycle after');
  });
}
