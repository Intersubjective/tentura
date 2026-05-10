import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/prune_directed_paths.dart';

const _w = 1.0;

EdgeDirected _e(String src, String dst) => (
      src: src,
      dst: dst,
      weight: _w,
      node: null,
    );

void main() {
  group('edgesOnSomeDirectedPath', () {
    test('linear chain keeps the full spine', () {
      final edges = {
        _e('R', 'A'),
        _e('A', 'B'),
        _e('B', 'F'),
      };
      final out = edgesOnSomeDirectedPath(
        edges: edges,
        root: 'R',
        focus: 'F',
      );
      expect(out, edges);
    });

    test('dead branch off the spine is removed', () {
      final edges = {
        _e('R', 'A'),
        _e('A', 'F'),
        _e('R', 'B'),
        _e('B', 'C'),
      };
      final out = edgesOnSomeDirectedPath(
        edges: edges,
        root: 'R',
        focus: 'F',
      );
      expect(out, {_e('R', 'A'), _e('A', 'F')});
    });

    test('diamond keeps both routes to the focus', () {
      final edges = {
        _e('R', 'A'),
        _e('R', 'B'),
        _e('A', 'X'),
        _e('B', 'X'),
        _e('X', 'F'),
      };
      final out = edgesOnSomeDirectedPath(
        edges: edges,
        root: 'R',
        focus: 'F',
      );
      expect(out, edges);
    });

    test('swap fallback: committer as root, author as focus uses author→…→committer chain', () {
      // Forward physical chain: author U -> … -> committer C (no C -> U edge).
      final edges = {
        _e('U', 'A'),
        _e('A', 'B'),
        _e('B', 'C'),
      };
      final out = edgesOnSomeDirectedPath(
        edges: edges,
        root: 'C',
        focus: 'U',
      );
      expect(out, edges);
    });

    test('empty input returns empty', () {
      expect(
        edgesOnSomeDirectedPath(edges: {}, root: 'R', focus: 'F'),
        isEmpty,
      );
    });
  });

  group('forwardReachFrom / verticesThatCanReachFocus', () {
    test('forwardReachFrom follows outgoing edges only', () {
      final edges = {_e('a', 'b'), _e('b', 'c')};
      expect(forwardReachFrom(edges, 'a'), {'a', 'b', 'c'});
      expect(forwardReachFrom(edges, 'b'), {'b', 'c'});
    });

    test('verticesThatCanReachFocus collects predecessors', () {
      final edges = {_e('a', 'b'), _e('b', 'c')};
      expect(verticesThatCanReachFocus(edges, 'c'), {'a', 'b', 'c'});
    });
  });
}
