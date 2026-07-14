import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/domain/use_case/graph_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/env.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeGraphSource implements GraphSourceRepository {
  /// Edges returned per requested focus (`null` = the initial ego fetch).
  final pages = <String?, Set<EdgeDirected>>{};

  /// When set, overrides [pages] entirely.
  Set<EdgeDirected> Function(String? focus, String context)? onFetch;

  int calls = 0;
  final callLog = <({String? focus, String context})>[];

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
  }) async {
    calls += 1;
    callLog.add((focus: focus, context: context));
    final custom = onFetch;
    if (custom != null) {
      return custom(focus, context);
    }
    return pages[focus] ?? const {};
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
  graphCase: GraphCase.forTesting(
    meritRank: source,
    beacons: _FakeBeaconRepository(),
    profiles: _FakeProfileRepository(),
    env: const Env(),
    logger: Logger('test'),
  ),
  edgeColors: _edgeColors,
  effects: FakeUiEffectPort(),
);

Future<void> _settle() => pumpEventQueue(times: 5);

Set<String> _nodeIds(GraphCubit cubit) =>
    cubit.graphController.nodes.map((n) => n.id).toSet();

Set<(String, String)> _edgePairs(GraphCubit cubit) => {
  for (final e in cubit.graphController.edges) (e.source.id, e.destination.id),
};

NodeDetails _liveNode(GraphCubit cubit, String id) =>
    cubit.graphController.nodes.singleWhere((n) => n.id == id);

void main() {
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

      cubit.setFocus(_liveNode(cubit, 'Ub'));
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

      cubit.setFocus(_liveNode(cubit, 'Ue'));
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

      cubit.setFocus(_liveNode(cubit, 'Ub'));
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

    cubit.setFocus(_liveNode(cubit, 'Ub'));
    await _settle();

    // C is spotlight-hidden while B has focus; refocusing ego re-reveals
    // ego's own neighborhood so C can be tapped again.
    cubit.setFocus(_liveNode(cubit, 'Ume'));
    await _settle();
    expect(_nodeIds(cubit), contains('Uc'));

    cubit.setFocus(_liveNode(cubit, 'Uc'));
    await _settle();
    cubit.setFocus(_liveNode(cubit, 'Ue'));
    await _settle();

    expect(_nodeIds(cubit), {'Ume', 'Ub', 'Uc', 'Ue'});
    expect(_edgePairs(cubit), {
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

      cubit.setFocus(_liveNode(cubit, 'Ub'));
      await _settle();

      expect(_nodeIds(cubit), {'Ume', 'Ub'});
      expect(_edgePairs(cubit), {('Ume', 'Ub')});

      await cubit.close();
    },
  );

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

      cubit.setFocus(_liveNode(cubit, 'Ux'));
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

    cubit.setFocus(_liveNode(cubit, 'Ub'));
    await _settle();

    expect(_nodeIds(cubit), {'Ume', 'Ub', 'Ue'});
    expect(_edgePairs(cubit), {
      ('Ume', 'Ub'),
      ('Ub', 'Ue'),
    });

    cubit.setFocus(_liveNode(cubit, 'Ume'));
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

      cubit.setFocus(_liveNode(cubit, 'Ub'));
      await _settle();
      cubit.setFocus(_liveNode(cubit, 'Ue'));
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
    'previously focused nodes stay pinned after they reappear from cache',
    () async {
      final source = _FakeGraphSource()
        ..pages.addAll({
          null: {_e('Ume', 'Ub'), _e('Ume', 'Uc')},
        });
      final cubit = _cubit(source);
      await _settle();

      cubit.setFocus(_liveNode(cubit, 'Ub'));
      await _settle();
      cubit.setFocus(_liveNode(cubit, 'Ume'));
      await _settle();
      cubit.setFocus(_liveNode(cubit, 'Uc'));
      await _settle();

      expect(_nodeIds(cubit), {'Ume', 'Uc'});

      cubit.setFocus(_liveNode(cubit, 'Ume'));
      await _settle();

      final pinnedIds = cubit.graphController.nodes
          .where((n) => n.pinned)
          .map((n) => n.id)
          .toSet();
      expect(pinnedIds, containsAll({'Ume', 'Ub', 'Uc'}));

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

      cubit.setFocus(_liveNode(cubit, 'Ub'));
      await _settle();

      // E and F now visible: badge gone.
      expect(cubit.state.hiddenNeighborCounts, isEmpty);
      final callsAfterFocusB = source.calls;

      cubit.setFocus(_liveNode(cubit, 'Ue'));
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

      cubit.setFocus(_liveNode(cubit, 'Ub'));
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

  test('re-tapping the current focus still pages in more neighbors', () async {
    final source = _FakeGraphSource()
      ..pages.addAll({
        null: {_e('Ume', 'Ub')},
        'Ub': {_e('Ub', 'Ue')},
      });
    final cubit = _cubit(source);
    await _settle();

    cubit.setFocus(_liveNode(cubit, 'Ub'));
    await _settle();
    expect(source.calls, 2);

    cubit.setFocus(_liveNode(cubit, 'Ub'));
    await _settle();

    // Same-node re-tap is the "load more" gesture: it must keep fetching.
    expect(source.calls, 3);
    expect(source.callLog.last.focus, 'Ub');

    await cubit.close();
  });
}
