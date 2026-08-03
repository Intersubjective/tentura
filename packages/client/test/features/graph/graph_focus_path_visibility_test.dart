import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeGraphSource implements GraphSourceRepository {
  /// Edges returned per requested focus (`null` = the initial ego fetch).
  final pages = <String?, Set<EdgeDirected>>{};

  /// When set, overrides [pages] entirely.
  Set<EdgeDirected> Function(String? focus, String context)? onFetch;

  /// Closure edges returned by [fetchEdgesBetween].
  Set<EdgeDirected> closureEdges = const {};

  /// Optional per-call override; receives the requested [nodeIds].
  Set<EdgeDirected> Function(Set<String> nodeIds)? onClosure;

  /// Completer to hold the next [fetchEdgesBetween] until completed in a test.
  Completer<void>? blockClosure;

  int calls = 0;
  int closureCalls = 0;
  final callLog = <({String? focus, String context, Set<String> exclude})>[];
  final closureLog = <Set<String>>[];

  static Set<EdgeDirected> _filterExcluded(
    String? focus,
    Set<EdgeDirected> edges,
    Set<String> excludeNeighborIds,
  ) {
    if (excludeNeighborIds.isEmpty || focus == null || focus.isEmpty) {
      return edges;
    }
    return {
      for (final e in edges)
        if (!_isExcludedNeighbor(e, focus, excludeNeighborIds)) e,
    };
  }

  static bool _isExcludedNeighbor(
    EdgeDirected e,
    String focus,
    Set<String> exclude,
  ) {
    final other = e.src == focus
        ? e.dst
        : e.dst == focus
        ? e.src
        : null;
    if (other == null) {
      return false;
    }
    return exclude.contains(other);
  }

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) async {
    calls += 1;
    callLog.add((
      focus: focus,
      context: context,
      exclude: Set<String>.from(excludeNeighborIds),
    ));
    final custom = onFetch;
    final raw = custom != null
        ? custom(focus, context)
        : pages[focus] ?? const {};
    return _filterExcluded(focus, raw, excludeNeighborIds);
  }

  @override
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async {
    closureCalls += 1;
    closureLog.add(Set<String>.from(nodeIds));
    final gate = blockClosure;
    if (gate != null) {
      await gate.future;
    }
    final custom = onClosure;
    if (custom != null) {
      return custom(nodeIds);
    }
    // Real SQL only returns edges whose both ends are in [nodeIds].
    return {
      for (final e in closureEdges)
        if (nodeIds.contains(e.src) && nodeIds.contains(e.dst)) e,
    };
  }
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  final fetchedIds = <String>[];

  @override
  Future<Profile> fetchById(String id) async {
    fetchedIds.add(id);
    return Profile(id: id, displayName: id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

const _me = Profile(id: 'Ume', displayName: 'Me');

EdgeDirected _e(
  String src,
  String dst, {
  double weight = 1,
  int? srcTotal,
  int? dstTotal,
}) => (
  src: src,
  dst: dst,
  weight: weight,
  node: UserNode(
    user: Profile(id: dst, displayName: dst),
  ),
  branch: null,
  srcTotalNeighborCount: srcTotal,
  dstTotalNeighborCount: dstTotal,
);

GraphCubit _cubit(_FakeGraphSource source) => GraphCubit(
  me: _me,
  graphSourceRepository: source,
  edgeColors: _edgeColors,
  beaconRepository: _FakeBeaconRepository(),
  profileRepository: _FakeProfileRepository(),
  effects: FakeUiEffectPort(),
);

Future<void> _settle() => pumpEventQueue(times: 5);

Set<String> _nodeIds(GraphCubit cubit) =>
    cubit.graphController.nodes.map((n) => n.id).toSet();

Set<(String, String)> _edgePairs(GraphCubit cubit) => {
  for (final e in cubit.graphController.edges) (e.source.id, e.destination.id),
};

void _assertOneNodePerId(GraphCubit cubit) {
  final ids = cubit.graphController.nodes.map((node) => node.id).toList();
  expect(ids.toSet().length, ids.length);
}

Future<({Set<String> nodes, Set<(String, String)> edges})> _exploreAndReset(
  GraphCubit cubit,
  List<String> order,
) async {
  for (final id in order) {
    cubit.selectNode(_liveNode(cubit, 'Ume'));
    await _settle();
    await _selectAndExpand(cubit, id);
  }
  cubit.resetToEgo();
  await _settle();
  return (nodes: _nodeIds(cubit), edges: _edgePairs(cubit));
}

Future<void> _selectAndExpand(GraphCubit cubit, String id) async {
  cubit.selectNode(_liveNode(cubit, id));
  await _settle();
  cubit.expandNode(_liveNode(cubit, id));
  await _settle();
}

NodeDetails _liveNode(GraphCubit cubit, String id) =>
    cubit.graphController.nodes.singleWhere((n) => n.id == id);

void main() {
  test('canPageMore reflects paging state for the current focus', () async {
    final source = _FakeGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub', dstTotal: 3)},
        'Ub': {_e('Ub', 'Ue'), _e('Ub', 'Uf'), _e('Ub', 'Ug')},
      });
    final cubit = _cubit(source);
    await _settle();

    expect(cubit.isCurrentFocus('Ume'), isTrue);
    expect(cubit.canPageMore('Ume'), isFalse);

    cubit.handleNodeTap(_liveNode(cubit, 'Ub'));
    await _settle();

    expect(cubit.isCurrentFocus('Ub'), isTrue);
    expect(cubit.canPageMore('Ub'), isFalse);

    await cubit.close();
  });

  test('canPageMore is true only when hidden neighbor count is positive', () async {
    final source = _FakeGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub')},
        'Ub': {_e('Ub', 'Ue', srcTotal: 3)},
      });
    final cubit = _cubit(source);
    await _settle();

    expect(cubit.canPageMore('Ub'), isFalse);

    cubit.handleNodeTap(_liveNode(cubit, 'Ub'));
    await _settle();

    expect(cubit.isCurrentFocus('Ub'), isTrue);
    expect(cubit.canPageMore('Ub'), isTrue);

    await cubit.close();
  });

  test(
    'rollback tap on ancestor with hidden badge does not fetch',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub'), _e('Ume', 'Uc')},
          'Ub': {_e('Ub', 'Ue')},
        });
      final cubit = _cubit(source);
      await _settle();
      expect(source.calls, 1);

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      cubit.expandNode(_liveNode(cubit, 'Ue'));
      await _settle();
      expect(source.calls, 3);
      expect(cubit.hasEverFocused('Ume'), isTrue);

      cubit.handleNodeTap(_liveNode(cubit, 'Ume'));
      await _settle();

      expect(source.calls, 3);
      expect(cubit.state.focus, 'Ume');
      expect(_nodeIds(cubit), containsAll(['Ume', 'Ub', 'Uc']));
      await cubit.close();
    },
  );

  test(
    'resetToEgo keeps everFocused so rollback taps do not refetch',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
          'Ub': {_e('Ub', 'Ue')},
        });
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      final callsAfterExplore = source.calls;

      cubit.resetToEgo();
      await _settle();
      expect(cubit.state.focus, isEmpty);

      cubit.handleNodeTap(_liveNode(cubit, 'Ub'));
      await _settle();

      expect(source.calls, callsAfterExplore);
      expect(cubit.state.focus, 'Ub');
      await cubit.close();
    },
  );

  test(
    'setContext clears everFocused so a cached node can explore again',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
          'Ub': {_e('Ub', 'Ue')},
        });
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      cubit.resetToEgo();
      await _settle();

      await cubit.setContext('work');
      await _settle();
      expect(source.calls, 3);

      cubit.handleNodeTap(_liveNode(cubit, 'Ub'));
      await _settle();

      expect(source.calls, 4);
      await cubit.close();
    },
  );

  test(
    'new focus neighbours immediately show cached chords to already-visible '
    'nodes (including trail ancestors)',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
          'Ub': {_e('Ub', 'Ue')},
        })
        ..closureEdges = {_e('Ue', 'Ume')};
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      cubit.expandNode(_liveNode(cubit, 'Ue'));
      await _settle();

      expect(_edgePairs(cubit), {
        ('Ume', 'Ub'),
        ('Ub', 'Ue'),
        ('Ue', 'Ume'),
      });

      await cubit.close();
    },
  );

  test(
    'new neighbour draws all links to other already-visible focus neighbours',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
          'Ub': {
            _e('Ub', 'Ue'),
            _e('Ub', 'Uf'),
          },
        })
        ..closureEdges = {_e('Ue', 'Uf')};
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();

      expect(_nodeIds(cubit), {'Ume', 'Ub', 'Ue', 'Uf'});
      expect(_edgePairs(cubit), {
        ('Ume', 'Ub'),
        ('Ub', 'Ue'),
        ('Ub', 'Uf'),
        ('Ue', 'Uf'),
      });

      await cubit.close();
    },
  );

  test(
    'tap sequence A→B→E→back-to-B spotlights the ego→focus path '
    'and backtracking refetches nothing',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub'), _e('Ume', 'Uc'), _e('Ume', 'Ud')},
          'Ub': {_e('Ub', 'Ue'), _e('Ub', 'Uf')},
          'Ue': {_e('Ue', 'Ug'), _e('Ue', 'Uh')},
        });
      final cubit = _cubit(source);
      await _settle();

      expect(_nodeIds(cubit), {'Ume', 'Ub', 'Uc', 'Ud'});
      expect(_edgePairs(cubit), {
        ('Ume', 'Ub'),
        ('Ume', 'Uc'),
        ('Ume', 'Ud'),
      });

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();

      // C, D and their ego edges fade; A–B survives; B's fresh
      // neighbors E, F appear.
      expect(_nodeIds(cubit), {'Ume', 'Ub', 'Ue', 'Uf'});
      expect(_edgePairs(cubit), {
        ('Ume', 'Ub'),
        ('Ub', 'Ue'),
        ('Ub', 'Uf'),
      });
      expect(source.calls, 2);

      cubit.expandNode(_liveNode(cubit, 'Ue'));
      await _settle();

      // F is a sibling off the ego→E path now; G, H are E's fresh neighbors.
      expect(_nodeIds(cubit), {'Ume', 'Ub', 'Ue', 'Ug', 'Uh'});
      expect(_edgePairs(cubit), {
        ('Ume', 'Ub'),
        ('Ub', 'Ue'),
        ('Ue', 'Ug'),
        ('Ue', 'Uh'),
      });
      expect(source.calls, 3);

      cubit.selectNode(_liveNode(cubit, 'Ub'));
      await _settle();

      // Backtrack: E and F re-revealed from cache, G and H hidden again,
      // repository untouched.
      expect(_nodeIds(cubit), {'Ume', 'Ub', 'Ue', 'Uf'});
      expect(_edgePairs(cubit), {
        ('Ume', 'Ub'),
        ('Ub', 'Ue'),
        ('Ub', 'Uf'),
      });
      expect(source.calls, 3);

      await cubit.close();
    },
  );

  test('diamond: only the tapped branch stays on the ego→focus path', () async {
    final source = _FakeGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub'), _e('Ume', 'Uc')},
        'Ub': {_e('Ub', 'Ue')},
        'Uc': {_e('Uc', 'Ue')},
      });
    final cubit = _cubit(source);
    await _settle();

    cubit.expandNode(_liveNode(cubit, 'Ub'));
    await _settle();

    // C is spotlight-hidden while B has focus; refocusing ego re-reveals
    // ego's own neighborhood so C can be tapped again.
    cubit.selectNode(_liveNode(cubit, 'Ume'));
    await _settle();
    expect(_nodeIds(cubit), contains('Uc'));

    cubit.expandNode(_liveNode(cubit, 'Uc'));
    await _settle();
    cubit.expandNode(_liveNode(cubit, 'Ue'));
    await _settle();

    expect(_nodeIds(cubit), {'Ume', 'Ub', 'Uc', 'Ue'});
    // Ub is a focus-neighbour of Ue; Ume↔Ub is therefore a chord between two
    // already-visible nodes and must be drawn immediately.
    expect(_edgePairs(cubit), {
      ('Ume', 'Ub'),
      ('Ume', 'Uc'),
      ('Ub', 'Ue'),
      ('Uc', 'Ue'),
    });

    await cubit.close();
  });

  test(
    'reciprocal off-path edges do not keep sibling nodes visible',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {
            _e('Ume', 'Ub'),
            _e('Ume', 'Uc'),
            _e('Uc', 'Ume'),
          },
        });
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();

      expect(_nodeIds(cubit), {'Ume', 'Ub'});
      expect(_edgePairs(cubit), {('Ume', 'Ub')});

      await cubit.close();
    },
  );

  test('reciprocal trust edges are marked isReciprocal', () async {
    final source = _FakeGraphSource()
      ..pages.addAll({
        null: {
          _e('Ume', 'Ub'),
          _e('Ub', 'Ume'),
        },
      });
    final cubit = _cubit(source);
    await _settle();

    final edges = cubit.graphController.edges.toList();
    expect(edges, hasLength(1));
    expect(edges.single.isReciprocal, isTrue);

    await cubit.close();
  });

  test(
    'focus reachable only via an incoming edge keeps a connected spine '
    'through the swapped-endpoints fallback',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ux', 'Ume')},
        });
      final cubit = _cubit(source);
      await _settle();

      expect(_nodeIds(cubit), {'Ume', 'Ux'});

      cubit.selectNode(_liveNode(cubit, 'Ux'));
      await _settle();

      // No ego→X path exists; the X→ego edge must survive via the swap
      // fallback instead of leaving X orphaned.
      expect(_nodeIds(cubit), {'Ume', 'Ux'});
      expect(_edgePairs(cubit), {('Ux', 'Ume')});

      await cubit.close();
    },
  );

  test('tapping ego again hides the focused branch expansion', () async {
    final source = _FakeGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub'), _e('Ume', 'Uc')},
        'Ub': {_e('Ub', 'Ue')},
      });
    final cubit = _cubit(source);
    await _settle();

    cubit.expandNode(_liveNode(cubit, 'Ub'));
    await _settle();

    expect(_nodeIds(cubit), {'Ume', 'Ub', 'Ue'});
    expect(_edgePairs(cubit), {
      ('Ume', 'Ub'),
      ('Ub', 'Ue'),
    });

    cubit.selectNode(_liveNode(cubit, 'Ume'));
    await _settle();

    expect(_nodeIds(cubit), {'Ume', 'Ub', 'Uc'});
    expect(_edgePairs(cubit), {
      ('Ume', 'Ub'),
      ('Ume', 'Uc'),
    });

    await cubit.close();
  });

  test(
    'previously focused nodes stay pinned while they remain visible',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
          'Ub': {_e('Ub', 'Ue')},
        });
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      cubit.expandNode(_liveNode(cubit, 'Ue'));
      await _settle();

      // B stays visible because it is on the ego→E path, so it keeps the
      // pinned state it received when it was focused.
      final pinnedIds = cubit.graphController.nodes
          .where((n) => n.pinned)
          .map((n) => n.id)
          .toSet();
      expect(pinnedIds, {'Ume', 'Ub', 'Ue'});

      await cubit.close();
    },
  );

  test(
    'nodes off the active focus path are unpinned when focus moves away',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub'), _e('Ume', 'Uc')},
        });
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      cubit.selectNode(_liveNode(cubit, 'Ume'));
      await _settle();
      cubit.selectNode(_liveNode(cubit, 'Uc'));
      await _settle();

      expect(_nodeIds(cubit), {'Ume', 'Uc'});

      cubit.selectNode(_liveNode(cubit, 'Ume'));
      await _settle();

      final pinnedIds = cubit.graphController.nodes
          .where((n) => n.pinned)
          .map((n) => n.id)
          .toSet();
      expect(pinnedIds, {'Ume'});

      await cubit.close();
    },
  );

  test(
    'hidden-neighbor badge drops when a tap reveals neighbors and rises '
    'again when they become path-hidden',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          // B has 3 neighbors in total: me, E, F.
          null: {_e('Ume', 'Ub', srcTotal: 1, dstTotal: 3)},
          'Ub': {
            _e('Ub', 'Ue', srcTotal: 3, dstTotal: 1),
            _e('Ub', 'Uf', srcTotal: 3, dstTotal: 1),
          },
        });
      final cubit = _cubit(source);
      await _settle();

      expect(cubit.state.hiddenNeighborCounts, {'Ub': 2});

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();

      // E and F now visible: badge gone.
      expect(cubit.state.hiddenNeighborCounts, isEmpty);
      final callsAfterFocusB = source.calls;

      cubit.expandNode(_liveNode(cubit, 'Ue'));
      await _settle();

      // F path-hidden again: B's badge rises back by 1, derived purely from
      // cached totals (the E fetch returned nothing). F's own entry is for a
      // node that is currently hidden — harmless, the renderer only draws
      // badges on visible nodes.
      expect(cubit.state.hiddenNeighborCounts['Ub'], 1);
      expect(source.calls, callsAfterFocusB + 1);

      await cubit.close();
    },
  );

  test(
    'setContext resets the full-history edge cache along with the '
    'controller',
    () async {
      final source = _FakeGraphSource()
        ..onFetch = (focus, context) => context == 'work'
            ? {_e('Ume', 'Ud')}
            : switch (focus) {
                null => {_e('Ume', 'Ub'), _e('Ume', 'Uc')},
                'Ub' => {_e('Ub', 'Ue')},
                _ => const {},
              };
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();

      await cubit.setContext('work');
      await _settle();

      // Focus is reset to '', which renders *everything* cached — if the
      // old context's edges leaked into _allEdges they would resurface here.
      expect(_nodeIds(cubit), {'Ume', 'Ud'});
      expect(_edgePairs(cubit), {('Ume', 'Ud')});

      await cubit.close();
    },
  );

  test(
    'first expand on a chord node excludes already-known neighbors',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub', dstTotal: 2)},
          'Ub': {
            _e('Ub', 'Uc', srcTotal: 3, dstTotal: 2),
            _e('Ub', 'Ud', srcTotal: 3, dstTotal: 1),
          },
          'Uc': {
            _e('Uc', 'Ue', srcTotal: 3, dstTotal: 1),
            _e('Uc', 'Uf', srcTotal: 3, dstTotal: 1),
          },
        })
        ..closureEdges = {_e('Uc', 'Ud')};
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();

      expect(_nodeIds(cubit), containsAll({'Ume', 'Ub', 'Uc', 'Ud'}));

      final callsBeforeExpandC = source.calls;
      cubit.expandNode(_liveNode(cubit, 'Uc'));
      await _settle();

      expect(source.calls, callsBeforeExpandC + 1);
      expect(
        source.callLog.last.exclude,
        containsAll({'Ub', 'Ud'}),
      );
      expect(_nodeIds(cubit), containsAll({'Ue', 'Uf'}));

      await cubit.close();
    },
  );

  test('expand on the current focus still pages in more neighbors', () async {
    final source = _FakeGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub')},
        'Ub': {_e('Ub', 'Ue')},
      });
    final cubit = _cubit(source);
    await _settle();

    cubit.expandNode(_liveNode(cubit, 'Ub'));
    await _settle();
    expect(source.calls, 2);

    cubit.expandNode(_liveNode(cubit, 'Ub'));
    await _settle();

    // Same-node expand is the "load more" gesture: it must keep fetching.
    expect(source.calls, 3);
    expect(source.callLog.last.focus, 'Ub');

    await cubit.close();
  });

  test(
    'relationships hidden-neighbor count drops to 0 across paginated merges',
    () async {
      var ubFetches = 0;
      final source = _FakeGraphSource()
        ..onFetch = (focus, _) {
          if (focus == null) {
            return {_e('Ume', 'Ub', srcTotal: 1, dstTotal: 3)};
          }
          if (focus == 'Ub') {
            ubFetches += 1;
            if (ubFetches == 1) {
              // First page reveals only E; F still hidden (total=3 includes me).
              return {_e('Ub', 'Ue', srcTotal: 3, dstTotal: 1)};
            }
            return {
              _e('Ub', 'Ue', srcTotal: 3, dstTotal: 1),
              _e('Ub', 'Uf', srcTotal: 3, dstTotal: 1),
            };
          }
          return const {};
        };
      final cubit = _cubit(source);
      await _settle();

      expect(cubit.state.hiddenNeighborCounts, {'Ub': 2});

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      expect(cubit.state.hiddenNeighborCounts['Ub'], 1);

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      expect(cubit.state.hiddenNeighborCounts, isEmpty);

      await cubit.close();
    },
  );

  test(
    'closure query is scoped to the visible set and draws chords among it',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
          'Ub': {_e('Ub', 'Ue')},
        })
        ..closureEdges = {_e('Ue', 'Ume'), _e('Ub', 'Uc')};
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();

      // Ub→Uc is not among the visible set {Ume, Ub, Ue}, so a real
      // graph_edges_between would not return it; the fake mirrors that filter.
      expect(_edgePairs(cubit), {
        ('Ume', 'Ub'),
        ('Ub', 'Ue'),
        ('Ue', 'Ume'),
      });
      expect(
        source.closureLog.last,
        containsAll({'Ume', 'Ub', 'Ue'}),
      );
      expect(source.closureLog.last, isNot(contains('Uc')));

      await cubit.close();
    },
  );

  test(
    'togglePositiveOnly filters cached edges without refetching',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {
            _e('Ume', 'Ub'),
            _e('Ume', 'Uc', weight: -1),
          },
        });
      final cubit = _cubit(source);
      await _settle();
      final edgesBefore = _edgePairs(cubit);
      final callsBefore = source.calls;

      cubit.togglePositiveOnly();
      await _settle();
      cubit.togglePositiveOnly();
      await _settle();

      expect(_edgePairs(cubit), edgesBefore);
      expect(source.calls, callsBefore);

      await cubit.close();
    },
  );

  test('canPopFocus is false at start', () async {
    final cubit = _cubit(_FakeGraphSource());
    await _settle();
    expect(cubit.canPopFocus, isFalse);
    await cubit.close();
  });

  test(
    'popFocus restores the previous visible edge set without refetching',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
          'Ub': {_e('Ub', 'Ue')},
        });
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      cubit.expandNode(_liveNode(cubit, 'Ue'));
      await _settle();
      final callsAfterExpand = source.calls;

      cubit.popFocus();
      await _settle();

      expect(cubit.state.focus, 'Ub');
      expect(_edgePairs(cubit), {
        ('Ume', 'Ub'),
        ('Ub', 'Ue'),
      });
      expect(source.calls, callsAfterExpand);

      cubit.popFocus();
      await _settle();

      expect(cubit.state.focus, isEmpty);
      expect(
        _edgePairs(cubit),
        containsAll({
          ('Ume', 'Ub'),
          ('Ub', 'Ue'),
        }),
      );
      expect(source.calls, callsAfterExpand);

      cubit.selectNode(_liveNode(cubit, 'Ue'));
      await _settle();
      // Ue brings Ub (its neighbour); Ume stays as trail/root — so the
      // already-known Ume↔Ub chord is drawn between two visible nodes.
      expect(_edgePairs(cubit), {
        ('Ume', 'Ub'),
        ('Ub', 'Ue'),
      });
      expect(source.calls, callsAfterExpand);

      await cubit.close();
    },
  );

  test(
    'resetToEgo clears the trail and does not refetch',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub'), _e('Ume', 'Uc')},
          'Ub': {_e('Ub', 'Ue')},
        });
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      cubit.expandNode(_liveNode(cubit, 'Ue'));
      await _settle();
      final callsAfterExpand = source.calls;

      cubit.resetToEgo();
      await _settle();

      expect(cubit.state.focus, isEmpty);
      expect(cubit.canPopFocus, isFalse);
      expect(source.calls, callsAfterExpand);

      await cubit.close();
    },
  );

  test('one-way A→B shows B with a drawn edge when ego focuses A', () async {
    final source = _FakeGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub')},
      });
    final cubit = _cubit(source);
    await _settle();

    expect(_nodeIds(cubit), {'Ume', 'Ub'});
    expect(_edgePairs(cubit), {('Ume', 'Ub')});
    expect(cubit.graphController.edges, hasLength(1));

    await cubit.close();
  });

  test(
    'transitive A→B→C shows the full chain after expanding A then B',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
          'Ub': {_e('Ub', 'Uc')},
        });
      final cubit = _cubit(source);
      await _settle();

      cubit.expandNode(_liveNode(cubit, 'Ub'));
      await _settle();
      cubit.expandNode(_liveNode(cubit, 'Uc'));
      await _settle();

      expect(_nodeIds(cubit), containsAll({'Ume', 'Ub', 'Uc'}));
      expect(
        _edgePairs(cubit),
        containsAll({
          ('Ume', 'Ub'),
          ('Ub', 'Uc'),
        }),
      );

      await cubit.close();
    },
  );

  test(
    'cyclic A→B→C→A terminates with one layout position per node',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
          'Ub': {_e('Ub', 'Uc')},
          'Uc': {_e('Uc', 'Ume')},
        })
        ..closureEdges = {
          _e('Ub', 'Uc'),
          _e('Uc', 'Ume'),
          _e('Ume', 'Ub'),
        };
      final cubit = _cubit(source);
      await _settle();

      await _selectAndExpand(cubit, 'Ub');
      await _selectAndExpand(cubit, 'Uc');
      await _selectAndExpand(cubit, 'Ume');

      expect(_nodeIds(cubit), containsAll({'Ume', 'Ub', 'Uc'}));
      _assertOneNodePerId(cubit);

      await cubit.close();
    },
  );

  test(
    'order independence: expanding A→B→C matches A→C→B final visibility',
    () async {
      Future<({Set<String> nodes, Set<(String, String)> edges})> explore(
        List<String> order,
      ) async {
        final source = _FakeGraphSource()
          ..pages.addAll({
            null: {_e('Ume', 'Ub'), _e('Ume', 'Uc')},
            'Ub': {_e('Ub', 'Ud')},
            'Uc': {_e('Uc', 'Ud')},
          });
        final cubit = _cubit(source);
        await _settle();
        final result = await _exploreAndReset(cubit, order);
        await cubit.close();
        return result;
      }

      final viaB = await explore(['Ub', 'Uc']);
      final viaC = await explore(['Uc', 'Ub']);

      expect(viaB.nodes, viaC.nodes);
      expect(viaB.edges, viaC.edges);
    },
  );

  test(
    'staged neighbourhood is not painted until visible-set closure returns',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub')},
          'Ub': {_e('Ub', 'Ue')},
        })
        ..closureEdges = {_e('Ue', 'Ume')};
      final cubit = _cubit(source);
      await _settle();

      final gate = Completer<void>();
      source.blockClosure = gate;
      final expandDone = cubit.expandNode(_liveNode(cubit, 'Ub'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(_nodeIds(cubit), isNot(contains('Ue')));
      cubit.resetToEgo();
      expect(_nodeIds(cubit), isNot(contains('Ue')));

      gate.complete();
      await expandDone;
      await _settle();

      expect(_nodeIds(cubit), containsAll({'Ume', 'Ub', 'Ue'}));
      expect(_edgePairs(cubit), contains(('Ue', 'Ume')));

      await cubit.close();
    },
  );

  test(
    'setContext discards in-flight closure merges from the old cache epoch',
    () async {
      final source = _FakeGraphSource()
        ..closureEdges = {_e('Ue', 'Ume')}
        ..onFetch = (focus, context) => context == 'work'
            ? {_e('Ume', 'Ud')}
            : switch (focus) {
                null => {_e('Ume', 'Ub')},
                'Ub' => {_e('Ub', 'Ue')},
                _ => const {},
              };
      final cubit = _cubit(source);
      await _settle();

      final gate = Completer<void>();
      source.blockClosure = gate;
      final expandDone = cubit.expandNode(_liveNode(cubit, 'Ub'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Must not await setContext before releasing the gate — the new fetch
      // also waits on the same closure block.
      final contextDone = cubit.setContext('work');
      gate.complete();
      await expandDone;
      await contextDone;
      await _settle();

      expect(_nodeIds(cubit), {'Ume', 'Ud'});
      expect(_edgePairs(cubit), {('Ume', 'Ud')});
      expect(_edgePairs(cubit), isNot(contains(('Ue', 'Ume'))));

      await cubit.close();
    },
  );

  test(
    'select during in-flight fetch does not prevent the fetch from painting',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub'), _e('Ume', 'Uc')},
          'Ub': {_e('Ub', 'Ue')},
        })
        ..closureEdges = {_e('Ue', 'Ume')};
      final cubit = _cubit(source);
      await _settle();
      final ub = _liveNode(cubit, 'Ub');
      final uc = _liveNode(cubit, 'Uc');

      final gate = Completer<void>();
      source.blockClosure = gate;
      final expandDone = cubit.expandNode(ub);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Must not bump fetch/cache epochs — only changes focus/path.
      cubit.selectNode(uc);
      gate.complete();
      await expandDone;
      await _settle();

      // Fetch still merged Ub's neighbourhood despite the mid-flight select;
      // re-focus Ub to surface Ue from the cache.
      cubit.selectNode(ub);
      await _settle();

      expect(_nodeIds(cubit), contains('Ue'));
      expect(_edgePairs(cubit), contains(('Ub', 'Ue')));

      await cubit.close();
    },
  );
}
