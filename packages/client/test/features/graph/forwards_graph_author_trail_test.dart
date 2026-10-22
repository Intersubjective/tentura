import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/data/repository/forwards_graph_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

/// #396: "How this request spread" draws the author's forward to a helper,
/// whatever the helper did since (offered, was admitted, withdrew). The
/// server keeps the edge (see the server's
/// `forward_provenance_survives_withdrawal_pg_test.dart`); the graph must
/// draw it, with the viewer once.

const _me = Profile(id: 'Ume', displayName: 'Author Name');

class _FakeForwardsGraphRepository implements ForwardsGraphRepository {
  _FakeForwardsGraphRepository(this.payload);

  final ForwardsGraphPayload payload;

  @override
  Future<ForwardsGraphPayload> fetchForwardsGraph({
    required String beaconId,
  }) async => payload;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  Future<Profile> fetchById(String id) async =>
      Profile(id: id, displayName: id == _me.id ? _me.displayName : id);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

EdgeDirected _edge(String src, String dst) => (
  src: src,
  dst: dst,
  weight: 1,
  node: null,
  branch: null,
  srcTotalNeighborCount: null,
  dstTotalNeighborCount: null,
);

void main() {
  test('author sees their forward to a withdrawn helper, and themselves '
      'once', () async {
    final cubit = GraphCubit(
      me: _me,
      edgeColors: const GraphEdgeColors(
        negative: Colors.red,
        ego: Colors.orange,
        neutral: Colors.blue,
        target: Colors.green,
      ),
      forwardsGraphBeaconId: 'B1',
      graphSourceRepository: _FakeForwardsGraphRepository((
        edges: {_edge('Ume', 'Uhelper')},
        // The helper withdrew: no longer an active help offerer.
        helpOffererIds: const <String>{},
        authorId: 'Ume',
        viewerId: 'Ume',
      )),
      beaconRepository: _FakeBeaconRepository(),
      profileRepository: _FakeProfileRepository(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await pumpEventQueue(times: 10);

    final ids = cubit.graphController.nodes.map((n) => n.id).toList();
    expect(ids.toSet(), {'Ume', 'Uhelper'});
    expect(ids, hasLength(2), reason: 'the viewer is one node, not two');
    expect(
      {
        for (final e in cubit.graphController.edges)
          (e.source.id, e.destination.id),
      },
      {('Ume', 'Uhelper')},
    );
  });
}
