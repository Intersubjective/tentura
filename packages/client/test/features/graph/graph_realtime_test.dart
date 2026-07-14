import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';
import 'package:tentura/domain/port/realtime_watch_grant_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/domain/use_case/graph_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

void main() {
  group('Graph realtime convergence', () {
    late _GraphHarness harness;

    setUp(() => harness = _GraphHarness());

    tearDown(() => harness.dispose());

    test(
      'registers the exact fetched user-node watch and removes it',
      () async {
        harness.source.result = {
          _edge('U-me', 'U-a'),
          _edge('U-me', 'U-b'),
        };
        harness.start();
        await harness.waitFor(() => harness.watchGrants.descriptors.isNotEmpty);

        final descriptor = harness.watchGrants.descriptors.single;
        expect(descriptor.scope, RealtimeWatchScope.graph);
        expect(descriptor.focusId, 'U-me');
        expect(descriptor.context, isEmpty);
        expect(descriptor.positiveOnly, isTrue);
        expect(descriptor.requestedSubjectIds, {'U-me', 'U-a', 'U-b'});

        await harness.closeCubit();
        expect(harness.realtimePort.removedWatches, [RealtimeWatchScope.graph]);
      },
    );

    test(
      'visible relationship change replaces truth and keeps valid focus pin',
      () async {
        harness.source.result = {
          _edge('U-me', 'U-a'),
          _edge('U-me', 'U-b'),
        };
        harness.start();
        await harness.waitFor(() => harness.nodeIds.contains('U-a'));
        harness.cubit.setFocus(harness.node('U-a'));
        await harness.waitFor(() => harness.source.fetchCalls >= 2);
        harness.source.result = {
          _edge('U-me', 'U-a'),
          _edge('U-a', 'U-c'),
        };

        harness.realtimePort.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.relationship,
            aggregateId: 'U-a',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await harness.waitFor(() => harness.source.fetchCalls >= 3);
        await harness.waitFor(() => !harness.nodeIds.contains('U-b'));

        expect(harness.cubit.state.focus, 'U-a');
        expect(harness.node('U-a').pinned, isTrue);
        expect(harness.effects.emitted, isEmpty);
      },
    );

    test('unrelated profile change is ignored', () async {
      harness.source.result = {_edge('U-me', 'U-a')};
      harness.start();
      await harness.waitFor(() => harness.source.fetchCalls == 1);

      harness.realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.profile,
          aggregateId: 'U-other',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(harness.source.fetchCalls, 1);
    });

    test('newer catch-up replacement wins over a stale completion', () async {
      harness.source.result = {_edge('U-me', 'U-a')};
      harness.start();
      await harness.waitFor(() => harness.source.fetchCalls == 1);
      final stale = Completer<Set<EdgeDirected>>();
      final fresh = Completer<Set<EdgeDirected>>();
      harness.source.pending.addAll([stale, fresh]);

      harness.realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.profile,
          aggregateId: 'U-a',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await harness.waitFor(() => harness.source.fetchCalls == 2);
      harness.realtimePort.emitCatchUp();
      await harness.waitFor(() => harness.source.fetchCalls == 3);

      fresh.complete({_edge('U-me', 'U-fresh')});
      await harness.waitFor(() => harness.nodeIds.contains('U-fresh'));
      stale.complete({_edge('U-me', 'U-stale')});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(harness.nodeIds, contains('U-fresh'));
      expect(harness.nodeIds, isNot(contains('U-stale')));
    });

    test(
      'background failure keeps the usable graph without an effect',
      () async {
        harness.source.result = {_edge('U-me', 'U-stable')};
        harness.start();
        await harness.waitFor(() => harness.nodeIds.contains('U-stable'));
        harness.source.error = StateError('offline');

        harness.realtimePort.emitCatchUp();
        await harness.waitFor(() => harness.source.fetchCalls == 2);
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(harness.nodeIds, contains('U-stable'));
        expect(harness.effects.emitted, isEmpty);
      },
    );

    test(
      'replacement resolution failure restores the usable graph',
      () async {
        harness.source.result = {_edge('U-me', 'U-stable')};
        harness.start();
        await harness.waitFor(() => harness.nodeIds.contains('U-stable'));
        harness.source.result = {_unresolvedEdge('U-me', 'U-unresolved')};
        harness.profiles.error = StateError('profile offline');

        harness.realtimePort.emitCatchUp();
        await harness.waitFor(() => harness.source.fetchCalls == 2);
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(harness.nodeIds, containsAll({'U-me', 'U-stable'}));
        expect(harness.nodeIds, isNot(contains('U-unresolved')));
        expect(harness.effects.emitted, isEmpty);
      },
    );
  });
}

const _colors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

EdgeDirected _edge(String source, String target) => (
  src: source,
  dst: target,
  weight: 1,
  node: UserNode(
    user: Profile(id: target, displayName: target),
  ),
  branch: null,
  srcTotalNeighborCount: null,
  dstTotalNeighborCount: null,
);

EdgeDirected _unresolvedEdge(String source, String target) => (
  src: source,
  dst: target,
  weight: 1,
  node: null,
  branch: null,
  srcTotalNeighborCount: null,
  dstTotalNeighborCount: null,
);

final class _GraphHarness {
  _GraphHarness() {
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    realtimeCase = realtime.case_;
    case_ = GraphCase.forTesting(
      meritRank: source,
      beacons: _FakeBeaconRepository(),
      profiles: profiles,
      realtime: realtimeCase,
      watchGrants: watchGrants,
      env: const Env(),
      logger: Logger('test'),
    );
  }

  final source = _ControllableGraphSource();
  final profiles = _FakeProfileRepository();
  final watchGrants = _FakeWatchGrantPort();
  final effects = FakeUiEffectPort();

  late final TestRealtimeSyncPort realtimePort;
  late final RealtimeSyncCase realtimeCase;
  late final GraphCase case_;
  GraphCubit? _cubit;

  GraphCubit get cubit => _cubit!;

  Set<String> get nodeIds =>
      cubit.graphController.nodes.map((node) => node.id).toSet();

  NodeDetails node(String id) =>
      cubit.graphController.nodes.singleWhere((node) => node.id == id);

  void start() {
    _cubit = GraphCubit(
      me: const Profile(id: 'U-me', displayName: 'Me'),
      edgeColors: _colors,
      graphCase: case_,
      effects: effects,
    );
  }

  Future<void> closeCubit() async {
    await _cubit?.close();
    _cubit = null;
  }

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for Graph convergence.');
  }

  Future<void> dispose() async {
    await closeCubit();
    await realtimeCase.dispose();
    await realtimePort.dispose();
  }
}

final class _ControllableGraphSource implements GraphSourceRepository {
  Set<EdgeDirected> result = const {};
  Object? error;
  int fetchCalls = 0;
  final pending = <Completer<Set<EdgeDirected>>>[];

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
  }) async {
    fetchCalls++;
    if (pending.isNotEmpty) return pending.removeAt(0).future;
    final failure = error;
    if (failure is Exception) throw failure;
    if (failure is Error) throw failure;
    return result;
  }
}

final class _FakeWatchGrantPort implements RealtimeWatchGrantPort {
  final descriptors = <RealtimeWatchDescriptor>[];

  @override
  Future<RealtimeWatchGrant> requestGrant(
    RealtimeWatchDescriptor descriptor,
  ) async {
    descriptors.add(descriptor);
    return RealtimeWatchGrant(
      token: 'graph-${descriptors.length}',
      scope: descriptor.scope,
      authorizedSubjectIds: descriptor.requestedSubjectIds,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }
}

final class _FakeProfileRepository implements ProfileRepositoryPort {
  Object? error;

  @override
  Future<Profile> fetchById(String id) async {
    final failure = error;
    if (failure is Exception) throw failure;
    if (failure is Error) throw failure;
    return Profile(id: id, displayName: id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
