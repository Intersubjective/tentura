import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart'
    show mintGraphLayoutTicket;

GraphLayoutRequest _request({
  required Object owner,
  required Map<GraphNodeId, GraphLayoutNode> nodes,
  Map<GraphEdgeId, GraphLayoutEdge> edges = const {},
  SceneLayout? previous,
}) {
  final ticket = mintGraphLayoutTicket(
    owner: owner,
    topologyRevision: 1,
    generation: 1,
  );
  return GraphLayoutRequest(
    ticket: ticket,
    canvasSize: SceneSize(width: 500, height: 500),
    nodesById: nodes,
    edgesById: edges,
    previous: previous,
  );
}

GraphLayoutNode _layoutNode(String id, {bool fixed = false}) => GraphLayoutNode(
      id: id,
      size: SceneSize(width: 100, height: 100),
      simulationFixed: fixed,
    );

void main() {
  final owner = Object();

  group('GraphLayoutFrameIngress', () {
    late GraphLayoutRequest request;

    setUp(() {
      request = _request(
        owner: owner,
        nodes: {
          'a': _layoutNode('a'),
          'b': _layoutNode('b'),
        },
      );
    });

    test('rejects stale ticket', () {
      final ingress = GraphLayoutFrameIngress(request);
      final otherTicket = mintGraphLayoutTicket(
        owner: Object(),
        topologyRevision: 1,
        generation: 1,
      );
      final frame = GraphLayoutFrame(
        ticket: otherTicket,
        sequence: 0,
        positions: {
          'a': ScenePoint(x: 1, y: 2),
          'b': ScenePoint(x: 3, y: 4),
        },
        isTerminal: true,
      );
      expect(
        ingress.classify(frame),
        GraphLayoutFrameDisposition.staleTicket,
      );
    });

    test('rejects partial positions', () {
      final ingress = GraphLayoutFrameIngress(request);
      final frame = GraphLayoutFrame(
        ticket: request.ticket,
        sequence: 0,
        positions: {'a': ScenePoint(x: 1, y: 2)},
        isTerminal: false,
      );
      expect(
        ingress.classify(frame),
        GraphLayoutFrameDisposition.partialOrExtraPositions,
      );
    });

    test('rejects duplicate sequence', () {
      final ingress = GraphLayoutFrameIngress(request);
      final frame = GraphLayoutFrame(
        ticket: request.ticket,
        sequence: 0,
        positions: {
          'a': ScenePoint(x: 1, y: 2),
          'b': ScenePoint(x: 3, y: 4),
        },
        isTerminal: false,
      );
      ingress.accept(frame);
      expect(
        ingress.classify(frame),
        GraphLayoutFrameDisposition.duplicateOrBackwardSequence,
      );
    });

    test('rejects post-terminal frames', () {
      final ingress = GraphLayoutFrameIngress(request);
      ingress.accept(
        GraphLayoutFrame(
          ticket: request.ticket,
          sequence: 0,
          positions: {
            'a': ScenePoint(x: 1, y: 2),
            'b': ScenePoint(x: 3, y: 4),
          },
          isTerminal: true,
        ),
      );
      expect(
        ingress.classify(
          GraphLayoutFrame(
            ticket: request.ticket,
            sequence: 1,
            positions: {
              'a': ScenePoint(x: 1, y: 2),
              'b': ScenePoint(x: 3, y: 4),
            },
            isTerminal: false,
          ),
        ),
        GraphLayoutFrameDisposition.postTerminal,
      );
    });

    test('enforce fails when stream closes without terminal', () async {
      final stream = Stream<GraphLayoutFrame>.value(
        GraphLayoutFrame(
          ticket: request.ticket,
          sequence: 0,
          positions: {
            'a': ScenePoint(x: 1, y: 2),
            'b': ScenePoint(x: 3, y: 4),
          },
          isTerminal: false,
        ),
      );
      await expectLater(
        GraphLayoutFrameIngress.enforce(stream, request).toList(),
        throwsA(isA<GraphLayoutFrameProtocolException>()),
      );
    });
  });

  group('one-shot and streaming fakes', () {
    test('one-shot emits exactly one terminal frame', () async {
      final request = _request(owner: owner, nodes: {'solo': _layoutNode('solo')});
      final algorithm = _OneShotLayoutAlgorithm();
      final frames = await GraphLayoutFrameIngress.enforce(
        algorithm.layout(request),
        request,
      ).toList();
      expect(frames, hasLength(1));
      expect(frames.single.isTerminal, isTrue);
      expect(frames.single.sequence, 0);
    });

    test('streaming fake ends with terminal frame', () async {
      final request = _request(
        owner: owner,
        nodes: {'n': _layoutNode('n')},
      );
      final algorithm = _StreamingLayoutAlgorithm(steps: 3);
      final frames = await GraphLayoutFrameIngress.enforce(
        algorithm.layout(request),
        request,
      ).toList();
      expect(frames.last.isTerminal, isTrue);
      expect(frames.length, 4);
    });

    test('subscription cancel stops consuming before terminal', () async {
      final request = _request(
        owner: owner,
        nodes: {'n': _layoutNode('n')},
      );
      final algorithm = _CancellableStreamingLayoutAlgorithm();
      final sub = algorithm.layout(request).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await sub.cancel();
      expect(algorithm.cancelNotified, isTrue);
    });
  });

  group('FruchtermanReingoldSceneLayoutAlgorithm', () {
    test('empty graph yields single terminal frame', () async {
      final request = _request(owner: owner, nodes: {});
      const algorithm = FruchtermanReingoldSceneLayoutAlgorithm(iterations: 5);
      final frames = await GraphLayoutFrameIngress.enforce(
        algorithm.layout(request),
        request,
      ).toList();
      expect(frames.single.isTerminal, isTrue);
      expect(frames.single.positions, isEmpty);
    });

    test('zero iterations still yields terminal complete frame', () async {
      final request = _request(
        owner: owner,
        nodes: {'a': _layoutNode('a')},
      );
      const algorithm = FruchtermanReingoldSceneLayoutAlgorithm(iterations: 0);
      final frames = await GraphLayoutFrameIngress.enforce(
        algorithm.layout(request),
        request,
      ).toList();
      expect(frames.last.isTerminal, isTrue);
      expect(frames.last.positions.keys, ['a']);
      expect(frames.last.positions['a']!.x.isFinite, isTrue);
    });

    test('self-loop edge does not produce NaN', () async {
      final request = _request(
        owner: owner,
        nodes: {'a': _layoutNode('a')},
        edges: {
          'loop': const GraphLayoutEdge(
            id: 'loop',
            sourceId: 'a',
            destinationId: 'a',
          ),
        },
      );
      const algorithm = FruchtermanReingoldSceneLayoutAlgorithm(iterations: 3);
      final terminal = await GraphLayoutFrameIngress.enforce(
        algorithm.layout(request),
        request,
      ).last;
      final p = terminal.positions['a']!;
      expect(p.x.isFinite && p.y.isFinite, isTrue);
    });

    test('deterministic for stable ids across runs', () async {
      final nodes = {
        'alpha': _layoutNode('alpha'),
        'beta': _layoutNode('beta'),
      };
      const algorithm = FruchtermanReingoldSceneLayoutAlgorithm(
        iterations: 8,
        temperature: 50,
        optimalDistance: 80,
      );
      Future<Map<GraphNodeId, ScenePoint>> run() async {
        final request = _request(owner: Object(), nodes: nodes);
        final frame = await GraphLayoutFrameIngress.enforce(
          algorithm.layout(request),
          request,
        ).last;
        return frame.positions;
      }
      expect(await run(), await run());
    });

    test('simulationFixed node stays at prior position', () async {
      final priorTicket = mintGraphLayoutTicket(
        owner: owner,
        topologyRevision: 0,
        generation: 0,
      );
      final previous = SceneLayout(
        ticket: priorTicket,
        revision: 0,
        positions: {
          'fixed': ScenePoint(x: 250, y: 250),
          'free': ScenePoint(x: 80, y: 80),
        },
      );
      final request = _request(
        owner: owner,
        nodes: {
          'fixed': _layoutNode('fixed', fixed: true),
          'free': _layoutNode('free'),
        },
        previous: previous,
      );
      const algorithm = FruchtermanReingoldSceneLayoutAlgorithm(iterations: 20);
      final terminal = await GraphLayoutFrameIngress.enforce(
        algorithm.layout(request),
        request,
      ).last;
      expect(terminal.positions['fixed'], previous.positions['fixed']);
    });
  });

  group('LegacyGraphLayoutAlgorithmAdapter', () {
    test('wraps legacy FR with terminal frame protocol', () async {
      const node1 = Node<String>(data: 'n1', size: 100);
      const node2 = Node<String>(data: 'n2', size: 100);
      const edge = Edge(
        source: node1,
        destination: node2,
        data: 'e1',
      );
      const legacy = FruchtermanReingoldAlgorithm(
        iterations: 4,
        temperature: 40,
        optimalDistance: 70,
      );
      final adapter = LegacyGraphLayoutAlgorithmAdapter(
        delegate: legacy,
        nodes: {node1, node2},
        edges: {edge},
        nodeIdOf: (n) => (n as Node<String>).data,
        edgeIdOf: (e) => (e as Edge).data as String,
      );
      final request = GraphLayoutRequest(
        ticket: mintGraphLayoutTicket(
          owner: owner,
          topologyRevision: 1,
          generation: 1,
        ),
        canvasSize: SceneSize(width: 500, height: 500),
        nodesById: {
          'n1': GraphLayoutNode(
            id: 'n1',
            size: SceneSize(width: 100, height: 100),
            simulationFixed: node1.pinned,
          ),
          'n2': GraphLayoutNode(
            id: 'n2',
            size: SceneSize(width: 100, height: 100),
            simulationFixed: node2.pinned,
          ),
        },
        edgesById: {
          'e1': const GraphLayoutEdge(
            id: 'e1',
            sourceId: 'n1',
            destinationId: 'n2',
          ),
        },
      );

      final frames = await GraphLayoutFrameIngress.enforce(
        adapter.layout(request),
        request,
      ).toList();
      expect(frames.last.isTerminal, isTrue);
      expect(frames.last.positions.keys, containsAll(['n1', 'n2']));

      final direct = await legacy
          .layout(
            nodes: {node1, node2},
            edges: {edge},
            size: const Size(500, 500),
          )
          .last;
      expect(
        frames.last.positions['n1']!.x,
        closeTo(direct.getPosition(node1).dx, 0.001),
      );
      expect(
        frames.last.positions['n1']!.y,
        closeTo(direct.getPosition(node1).dy, 0.001),
      );
    });

    test('maps pinned to simulationFixed mismatch as error', () async {
      const node = Node<int>(data: 1, size: 50, pinned: true);
      final adapter = LegacyGraphLayoutAlgorithmAdapter(
        delegate: const FruchtermanReingoldAlgorithm(iterations: 0),
        nodes: {node},
        edges: {},
        nodeIdOf: (n) => '1',
        edgeIdOf: (_) => 'e',
      );
      final request = GraphLayoutRequest(
        ticket: mintGraphLayoutTicket(
          owner: owner,
          topologyRevision: 1,
          generation: 1,
        ),
        canvasSize: SceneSize(width: 100, height: 100),
        nodesById: {
          '1': GraphLayoutNode(
            id: '1',
            size: SceneSize(width: 50, height: 50),
            simulationFixed: false,
          ),
        },
        edgesById: {},
      );
      await expectLater(
        adapter.layout(request),
        emitsError(isA<ArgumentError>()),
      );
    });
  });
}

final class _OneShotLayoutAlgorithm implements SceneLayoutAlgorithm {
  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final positions = {
      for (final id in request.nodeIds)
        id: ScenePoint(x: 0, y: 0),
    };
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: positions,
      isTerminal: true,
    );
  }
}

final class _StreamingLayoutAlgorithm implements SceneLayoutAlgorithm {
  _StreamingLayoutAlgorithm({required this.steps});

  final int steps;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    for (var i = 0; i < steps; i++) {
      yield GraphLayoutFrame(
        ticket: request.ticket,
        sequence: i,
        positions: {
          for (final id in request.nodeIds)
            id: ScenePoint(x: i.toDouble(), y: 0),
        },
        isTerminal: false,
      );
    }
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: steps,
      positions: {
        for (final id in request.nodeIds) id: ScenePoint(x: steps.toDouble(), y: 0),
      },
      isTerminal: true,
    );
  }
}

final class _CancellableStreamingLayoutAlgorithm implements SceneLayoutAlgorithm {
  var cancelNotified = false;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) {
    late final StreamController<GraphLayoutFrame> controller;
    controller = StreamController<GraphLayoutFrame>(
      onCancel: () => cancelNotified = true,
    );
    Future<void>(() async {
      for (var i = 0; i < 50; i++) {
        if (controller.isClosed) {
          return;
        }
        controller.add(
          GraphLayoutFrame(
            ticket: request.ticket,
            sequence: i,
            positions: {
              for (final id in request.nodeIds)
                id: ScenePoint(x: i.toDouble(), y: 0),
            },
            isTerminal: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    });
    return controller.stream;
  }
}
