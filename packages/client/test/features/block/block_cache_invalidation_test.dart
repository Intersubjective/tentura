import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'support/controllable_block_case.dart';

Future<void> _settle() => pumpEventQueue(times: 5);

void main() {
  group('block cache invalidation', () {
    test('GraphCubit refetches trust graph when BlockCase.changes emits', () async {
      final source = _FakeGraphSource();
      final blockCase = ControllableBlockCase();
      final cubit = GraphCubit(
        me: const Profile(id: 'Ume', displayName: 'Me'),
        graphSourceRepository: source,
        edgeColors: const GraphEdgeColors(
          negative: Colors.red,
          ego: Colors.orange,
          neutral: Colors.blue,
          target: Colors.green,
        ),
        beaconRepository: _FakeBeaconRepository(),
        profileRepository: _FakeProfileRepository(),
        blockCase: blockCase,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      addTearDown(blockCase.dispose);

      await _settle();
      final callsAfterBootstrap = source.calls;

      blockCase.emitBlock();
      await _settle();

      expect(source.calls, greaterThan(callsAfterBootstrap));
    });
  });
}

class _FakeGraphSource implements GraphSourceRepository {
  int calls = 0;

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
    return const {};
  }

  @override
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async =>
      const {};
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  Future<Profile> fetchById(String id) async => Profile(id: id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
