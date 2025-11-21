import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'package:tentura/features/graph/domain/entity/node_details.dart';

void main() {
  const userNode1 = UserNode(
    user: Profile(id: 'U1'),
  );
  const userNode2 = UserNode(
    user: Profile(id: 'U2'),
  );
  final now = DateTime.timestamp();
  final beaconNode1 = BeaconNode(
    beacon: Beacon(
      createdAt: now,
      updatedAt: now,
      id: 'B1',
      author: Profile(
        id: userNode1.id,
      ),
    ),
  );
  final beaconNode2 = BeaconNode(
    beacon: Beacon(
      createdAt: now,
      updatedAt: now,
      id: 'B2',
      author: Profile(
        id: userNode2.id,
      ),
    ),
  );

  test('test set 1', () {
    final s = <NodeDetails>{
      userNode1,
      userNode2,
      beaconNode1,
      beaconNode2,
    };

    expect(s.length, 4);
  });

  test('test set 2', () {
    final s = <Node<NodeDetails>>{
      const Node(data: userNode1, size: 40),
      const Node(data: userNode2, size: 40),
      Node(data: beaconNode1, size: 40),
      Node(data: beaconNode2, size: 40),
    };

    expect(s.length, 4);
  });
}
