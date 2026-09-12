import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

void main() {
  final size = SceneSize(width: 40, height: 40);

  GraphSceneNode<String> node(String id, {String payload = 'p'}) =>
      GraphSceneNode(id: id, payload: payload, size: size);

  GraphSceneEdge<String> edge(
    String id,
    String from,
    String to, {
    String payload = 'e',
  }) =>
      GraphSceneEdge(
        id: id,
        sourceId: from,
        destinationId: to,
        payload: payload,
      );

  group('ScenePoint and SceneSize validation', () {
    test('rejects non-finite coordinates', () {
      expect(
        () => ScenePoint(x: double.nan, y: 0),
        throwsArgumentError,
      );
      expect(
        () => SceneSize(width: -1, height: 10),
        throwsArgumentError,
      );
    });

    test('allows zero-size nodes', () {
      final zero = SceneSize(width: 0, height: 0);
      expect(zero.width, 0);
      expect(zero.height, 0);
    });
  });

  group('GraphTopology validation', () {
    test('accepts empty topology', () {
      final topology = GraphTopology<String, String>.fromEntries(
        nodes: const [],
        edges: const [],
      );
      expect(topology.isEmpty, isTrue);
    });

    test('rejects empty node id', () {
      expect(
        () => GraphTopology<String, String>.fromEntries(
          nodes: [node('')],
          edges: const [],
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate node ids', () {
      expect(
        () => GraphTopology<String, String>.fromEntries(
          nodes: [node('a'), node('a')],
          edges: const [],
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate edge ids', () {
      expect(
        () => GraphTopology<String, String>.fromEntries(
          nodes: [node('a'), node('b')],
          edges: [
            edge('e1', 'a', 'b'),
            edge('e1', 'a', 'b'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects missing endpoints', () {
      expect(
        () => GraphTopology<String, String>.fromEntries(
          nodes: [node('a')],
          edges: [edge('e1', 'a', 'missing')],
        ),
        throwsArgumentError,
      );
    });

    test('allows parallel edges and self-loops', () {
      final topology = GraphTopology<String, String>.fromEntries(
        nodes: [node('a'), node('b')],
        edges: [
          edge('trust:a->b', 'a', 'b', payload: 'trust'),
          edge('path:a->b', 'a', 'b', payload: 'path'),
          edge('loop:a', 'a', 'a', payload: 'self'),
        ],
      );
      expect(topology.edgesById, hasLength(3));
    });

    test('accepts opaque genealogy-like node keys without parsing', () {
      const genealogyKey = 'genealogy:branch:7f3c2a1b-deleted-anon';
      final topology = GraphTopology<String, String>.fromEntries(
        nodes: [
          GraphSceneNode(
            id: genealogyKey,
            payload: 'deleted-node',
            size: size,
          ),
        ],
        edges: const [],
      );
      expect(topology.nodesById[genealogyKey]?.payload, 'deleted-node');
    });
  });

  group('defensive copies and equality', () {
    test('topology maps are unmodifiable and independent of caller maps', () {
      final nodes = [node('a')];
      final topology = GraphTopology<String, String>.fromEntries(
        nodes: nodes,
        edges: const [],
      );
      expect(
        () => topology.nodesById['x'] = node('x'),
        throwsUnsupportedError,
      );

      final same = GraphTopology<String, String>.fromEntries(
        nodes: [node('a')],
        edges: const [],
      );
      expect(topology, equals(same));
    });

    test('SceneLayout copies positions map', () {
      final ticket = GraphLayoutTicket.mint(
        owner: Object(),
        topologyRevision: 1,
        generation: 1,
      );
      final source = {'a': ScenePoint(x: 1, y: 2)};
      final layout = SceneLayout(
        ticket: ticket,
        revision: 3,
        positions: source,
      );
      source['a'] = ScenePoint(x: 9, y: 9);
      source['b'] = ScenePoint(x: 0, y: 0);
      expect(layout.positions['a'], ScenePoint(x: 1, y: 2));
      expect(
        () => layout.positions['b'] = ScenePoint(x: 0, y: 0),
        throwsUnsupportedError,
      );

      final layout2 = SceneLayout(
        ticket: ticket,
        revision: 3,
        positions: {'a': ScenePoint(x: 1, y: 2)},
      );
      expect(layout, equals(layout2));
    });

    test('ScenePresentation copies overrides and paint order', () {
      final overrides = {'n': ScenePoint(x: 5, y: 6)};
      final order = <GraphNodeId>['n'];
      final presentation = ScenePresentation(
        overrides: overrides,
        paintOrder: order,
      );
      overrides['n'] = ScenePoint(x: 0, y: 0);
      order.add('other');
      expect(presentation.overrides['n'], ScenePoint(x: 5, y: 6));
      expect(presentation.paintOrder, ['n']);
    });

    test('GraphLayoutTicket distinguishes controller owners', () {
      final ownerA = Object();
      final ownerB = Object();
      final t1 = GraphLayoutTicket.mint(
        owner: ownerA,
        topologyRevision: 1,
        generation: 1,
      );
      final t2 = GraphLayoutTicket.mint(
        owner: ownerB,
        topologyRevision: 1,
        generation: 1,
      );
      expect(t1, isNot(equals(t2)));
    });
  });

  group('GraphSceneSnapshot.resolvePosition precedence', () {
    late GraphTopology<String, String> topology;
    late GraphLayoutTicket ticket;

    setUp(() {
      topology = GraphTopology<String, String>.fromEntries(
        nodes: [node('a')],
        edges: const [],
      );
      ticket = GraphLayoutTicket.mint(
        owner: Object(),
        topologyRevision: 0,
        generation: 0,
      );
    });

    test('override beats layout, transition, and seed', () {
      final snapshot = GraphSceneSnapshot(
        topology: topology,
        layout: SceneLayout(
          ticket: ticket,
          revision: 1,
          positions: {'a': ScenePoint(x: 10, y: 10)},
        ),
        transition: SceneTransition(
          positions: {'a': ScenePoint(x: 20, y: 20)},
        ),
        presentation: ScenePresentation(
          overrides: {'a': ScenePoint(x: 30, y: 30)},
        ),
        seedPositions: {'a': ScenePoint(x: 40, y: 40)},
      );
      expect(
        snapshot.resolvePosition('a'),
        ScenePoint(x: 30, y: 30),
      );
    });

    test('transition beats layout and seed when no override', () {
      final snapshot = GraphSceneSnapshot(
        topology: topology,
        layout: SceneLayout(
          ticket: ticket,
          revision: 1,
          positions: {'a': ScenePoint(x: 10, y: 10)},
        ),
        transition: SceneTransition(
          positions: {'a': ScenePoint(x: 20, y: 20)},
        ),
        seedPositions: {'a': ScenePoint(x: 40, y: 40)},
      );
      expect(
        snapshot.resolvePosition('a'),
        ScenePoint(x: 20, y: 20),
      );
    });

    test('layout beats seed when no override or transition', () {
      final snapshot = GraphSceneSnapshot(
        topology: topology,
        layout: SceneLayout(
          ticket: ticket,
          revision: 1,
          positions: {'a': ScenePoint(x: 10, y: 10)},
        ),
        seedPositions: {'a': ScenePoint(x: 40, y: 40)},
      );
      expect(
        snapshot.resolvePosition('a'),
        ScenePoint(x: 10, y: 10),
      );
    });

    test('seed used when no layout or presentation', () {
      final snapshot = GraphSceneSnapshot(
        topology: topology,
        seedPositions: {'a': ScenePoint(x: 40, y: 40)},
      );
      expect(
        snapshot.resolvePosition('a'),
        ScenePoint(x: 40, y: 40),
      );
    });

    test('returns null for unknown node id', () {
      final snapshot = GraphSceneSnapshot(topology: topology);
      expect(snapshot.resolvePosition('missing'), isNull);
    });
  });
}
