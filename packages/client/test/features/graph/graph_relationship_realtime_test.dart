import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

// #359 / #402 / #530: the open trust graph converges on a trust change made
// by the other person, in another session or on another screen. A
// `relationship` hint (or a reconnect catch-up) re-reads the edges among the
// loaded people and replaces the cached ones; before this the graph only
// ever added edges and had no realtime subscription at all.

class _FakeGraphSource implements GraphSourceRepository {
  final pages = <String?, Set<EdgeDirected>>{};

  /// Server truth for `graph_edges_between`.
  final between = <EdgeDirected>{};
  final betweenCalls = <Set<String>>[];

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) async => pages[focus] ?? const {};

  @override
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async {
    betweenCalls.add({...nodeIds});
    return {
      for (final e in between)
        if (nodeIds.contains(e.src) &&
            nodeIds.contains(e.dst) &&
            (!positiveOnly || e.weight > 0))
          e,
    };
  }
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  final fetchedIds = <String>[];
  final byId = <String, Profile>{};

  @override
  Future<Profile> fetchById(String id) async {
    fetchedIds.add(id);
    return byId[id] ?? Profile(id: id, displayName: id);
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

const _aliceMutual = Profile(
  id: 'Ualice',
  displayName: 'Alice',
  myVote: 1,
  subjectExplicitlyTrustsViewer: true,
  isMutualFriend: true,
);
const _bob = Profile(id: 'Ubob', displayName: 'Bob', myVote: 1);
const _carol = Profile(id: 'Ucarol', displayName: 'Carol');

EdgeDirected _e(
  String src,
  String dst, {
  double weight = 1,
  NodeDetails? dstNode,
}) => (
  src: src,
  dst: dst,
  weight: weight,
  node: dstNode,
  branch: null,
  srcTotalNeighborCount: null,
  dstTotalNeighborCount: null,
);

/// Me <-> Alice, Me -> Bob, Alice -> Carol; the server agrees.
_FakeGraphSource _source() {
  final edges = {
    _e('Ume', 'Ualice', dstNode: const UserNode(user: _aliceMutual)),
    _e('Ualice', 'Ume'),
    _e('Ume', 'Ubob', dstNode: const UserNode(user: _bob)),
    _e('Ualice', 'Ucarol', dstNode: const UserNode(user: _carol)),
  };
  return _FakeGraphSource()
    ..pages[null] = edges
    ..between.addAll(edges);
}

RealtimeEntityChange _relationshipHint(String id) => RealtimeEntityChange(
  kind: RealtimeEntityKind.relationship,
  aggregateId: id,
  operation: RealtimeOperation.update,
  source: RealtimeChangeSource.serverInvalidation,
);

Future<void> _settle() => pumpEventQueue(times: 10);

/// Past the hint debounce, then let the re-read finish.
Future<void> _afterRefresh() async {
  await Future<void>.delayed(
    GraphCubit.relationshipRefreshDebounce + const Duration(milliseconds: 50),
  );
  await _settle();
}

Set<String> _liveNodeIds(GraphCubit cubit) => {
  for (final n in cubit.graphController.nodes) n.id,
};

void main() {
  late _FakeGraphSource source;
  late _FakeProfileRepository profiles;
  late TestRealtimeSyncPort port;
  late GraphCubit cubit;

  setUp(() async {
    source = _source();
    profiles = _FakeProfileRepository();
    final realtime = buildTestRealtimeSync();
    port = realtime.port;
    cubit = GraphCubit(
      me: _me,
      graphSourceRepository: source,
      edgeColors: _edgeColors,
      beaconRepository: _FakeBeaconRepository(),
      profileRepository: profiles,
      realtimeSyncCase: realtime.case_,
      effects: FakeUiEffectPort(),
    );
    await _settle();
  });

  tearDown(() async {
    await cubit.close();
    await port.dispose();
  });

  test('the other person stopping trust drops their edge and the mutual '
      'badge, and nobody else leaves the graph (#359, #402)', () async {
    expect(cubit.viewerLink('Ualice'), (fromViewer: 1.0, toViewer: 1.0));

    // Alice withdrew her trust in me from her own device.
    source.between.removeWhere((e) => e.src == 'Ualice' && e.dst == 'Ume');
    profiles.byId['Ualice'] = _aliceMutual.copyWith(
      subjectExplicitlyTrustsViewer: false,
      isMutualFriend: false,
    );
    port.emitChange(_relationshipHint('Ualice'));
    await _afterRefresh();

    expect(cubit.viewerLink('Ualice'), (fromViewer: 1.0, toViewer: null));
    final alice = cubit.graphController.nodes.singleWhere(
      (n) => n.id == 'Ualice',
    );
    expect((alice as UserNode).user.isMutualFriend, isFalse);
    expect(
      _liveNodeIds(cubit),
      containsAll(<String>['Ume', 'Ualice', 'Ubob', 'Ucarol']),
    );
    expect(cubit.viewerLink('Ubob'), (fromViewer: 1.0, toViewer: null));
  });

  test('a trust given by someone else shows up without a reload', () async {
    source.between.add(_e('Ubob', 'Ume'));
    port.emitChange(_relationshipHint('Ubob'));
    await _afterRefresh();

    expect(cubit.viewerLink('Ubob'), (fromViewer: 1.0, toViewer: 1.0));
    expect(profiles.fetchedIds, contains('Ubob'));
  });

  test('a burst of hints is read once', () async {
    final callsBefore = source.betweenCalls.length;
    port
      ..emitChange(_relationshipHint('Ualice'))
      ..emitChange(_relationshipHint('Ubob'))
      ..emitChange(_relationshipHint('Ume'));
    await _afterRefresh();

    expect(source.betweenCalls.length, callsBefore + 1);
    expect(
      source.betweenCalls.last,
      containsAll(<String>['Ume', 'Ualice', 'Ubob', 'Ucarol']),
    );
  });

  test('a reconnect catch-up re-reads the edges too', () async {
    source.between.removeWhere((e) => e.src == 'Ualice' && e.dst == 'Ucarol');
    port.emitCatchUp();
    await _afterRefresh();

    expect(
      {
        for (final e in cubit.graphController.edges)
          (e.source.id, e.destination.id),
      },
      isNot(contains(('Ualice', 'Ucarol'))),
    );
  });

  test('my own withdrawal holds while the server still has the edge, and '
      'the guard ends once it catches up', () async {
    cubit.patchLoadedProfile(_aliceMutual.copyWith(myVote: 0));
    await _settle();
    expect(cubit.viewerLink('Ualice'), (fromViewer: null, toViewer: 1.0));

    // The vote hint arrives before the trust edge is rewritten.
    port.emitChange(_relationshipHint('Ualice'));
    await _afterRefresh();
    expect(cubit.viewerLink('Ualice'), (fromViewer: null, toViewer: 1.0));
    final alice =
        cubit.graphController.nodes.singleWhere((n) => n.id == 'Ualice')
            as UserNode;
    expect(alice.user.myVote, 0);
    expect(alice.user.isMutualFriend, isFalse);

    // The edge rewrite lands; the next hint finds the server agreeing.
    source.between.removeWhere((e) => e.src == 'Ume' && e.dst == 'Ualice');
    port.emitChange(_relationshipHint('Ualice'));
    await _afterRefresh();
    expect(cubit.viewerLink('Ualice'), (fromViewer: null, toViewer: 1.0));

    // Re-trust from another session: with the guard gone it is shown.
    source.between.add(_e('Ume', 'Ualice'));
    profiles.byId['Ualice'] = _aliceMutual;
    port.emitChange(_relationshipHint('Ualice'));
    await _afterRefresh();
    expect(cubit.viewerLink('Ualice'), (fromViewer: 1.0, toViewer: 1.0));
  });
}
