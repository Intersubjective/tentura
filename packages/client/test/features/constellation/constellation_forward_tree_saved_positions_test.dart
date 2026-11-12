import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';
import '../graph/scene_layout_test_support.dart';
import 'fixtures/constellation_reference_fixture.dart';

final class _FieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => constellationReferenceField();
}

final class _UnusedBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _edge(
  String id,
  String sender,
  String recipient, {
  String? parent,
}) => {
  'id': id,
  'beaconId': 'req-am-1',
  'senderId': sender,
  'recipientId': recipient,
  'parentEdgeId': parent,
  'batchId': null,
  'createdAt': '2026-11-06T12:00:00Z',
  'readAt': null,
  'declinedInvite': false,
  'forwardedOn': recipient != 'tree-helper',
  'offerStatus': recipient == 'tree-helper' ? 'accepted' : null,
  'sender': {'userId': sender, 'displayName': sender, 'anonymousCount': 0},
  'recipient': {
    'userId': recipient,
    'displayName': recipient,
    'anonymousCount': 0,
  },
};

void main() {
  group('Forward tree on an already positioned Field', () {
    for (final restoreAfterArrange in [false, true]) {
      testWidgets(
        restoreAfterArrange
            ? 'turning off tree arrangement places tree-only people and restores Field positions'
            : 'opening without tree arrangement places tree-only people and preserves Field positions',
        (tester) async {
          final sent = <WireSent>[];
          await tester.runAsync(
            () => withRemoteWire(
              {
                'BeaconForwardGraph': {
                  'beaconForwardGraph': {
                    'beaconId': 'req-am-1',
                    'authorId': 'am',
                    'viewerId': 'ego',
                    'helpOffererIds': ['tree-helper'],
                    'edges': [
                      _edge('to-viewer', 'am', 'ego'),
                      _edge('to-relay', 'am', 'tree-relay'),
                      _edge(
                        'to-helper',
                        'tree-relay',
                        'tree-helper',
                        parent: 'to-relay',
                      ),
                    ],
                  },
                },
              },
              sent,
              (remote) async {
                final realtime = buildTestRealtimeSync();
                final forwards = ForwardRepository(
                  remote,
                  _UnusedBeaconRepository(),
                  realtime.port,
                );
                addTearDown(() async {
                  await forwards.dispose();
                  await realtime.port.dispose();
                });
                final fixture = ConstellationStoreFixture(
                  _FieldRepository(),
                  accountId: kRefEgo.id,
                );
                final cubit = fixture.createCubit(
                  viewer: kRefEgo,
                  forwardCase: buildTestForwardCase(forwards),
                )..reduceMotionMediaOverrideForTest = true;
                await fixture.ready();
                await cubit.load();
                await pumpConstellationBody(
                  tester,
                  cubit,
                  size: const Size(375, 667),
                  disableAnimations: true,
                );
                await tester.pumpAndSettle();
                final before = cubit.graphController.renderSnapshot;
                expect(
                  before.topology.nodesById,
                  isNot(contains('fp:tree-helper')),
                );
                final saved = {
                  for (final id in before.topology.nodesById.keys)
                    id: before.resolvePosition(id),
                };
                expect(saved, isNotEmpty);
                expect(
                  saved.values,
                  everyElement(isNotNull),
                  reason:
                      'the Field must have completed layout before opening the tree',
                );

                await cubit.enterForwardTreeMode(beaconId: 'req-am-1');
                expect(cubit.state.forwardTreeOverlay?.error, isNull);
                expect(sent.single.operationName, 'BeaconForwardGraph');
                expect(sent.single.variables, {'id': 'req-am-1'});
                expect(
                  cubit.state.forwardTreeOverlay?.savedPersonPositions,
                  isNotEmpty,
                );

                if (restoreAfterArrange) {
                  cubit.toggleForwardTreeArrange();
                  expect(cubit.state.forwardTreeOverlay?.arrangeAsTree, isTrue);
                  await tester.pumpAndSettle();
                  expect(
                    cubit.graphController.renderSnapshot.resolvePosition(
                      'fp:tree-helper',
                    ),
                    isNotNull,
                  );
                  cubit.toggleForwardTreeArrange();
                }
                expect(cubit.state.forwardTreeOverlay?.arrangeAsTree, isFalse);
                final topology = cubit.graphController.renderSnapshot.topology;
                expect(topology.nodesById, contains('fp:tree-relay'));
                expect(topology.nodesById, contains('fp:tree-helper'));
                final positions = await layoutPositionsOnce(
                  cubit.graphSceneLayoutAlgorithm,
                  nodes: {
                    for (final node in topology.nodesById.values) node.payload,
                  },
                  edges: {
                    for (final edge in topology.edgesById.values) edge.payload,
                  },
                ).timeout(const Duration(seconds: 10));
                expect(
                  positions.keys,
                  unorderedEquals(topology.nodesById.keys),
                  reason:
                      'a complete frame must place the help path as well as saved Field nodes',
                );
                for (final entry in saved.entries) {
                  expect(
                    positions[entry.key],
                    entry.value,
                    reason:
                        'opening a tree without arrangement must preserve ${entry.key}',
                  );
                }
                for (final id in ['fp:tree-relay', 'fp:tree-helper']) {
                  expect(
                    positions[id]!.x.isFinite && positions[id]!.y.isFinite,
                    isTrue,
                  );
                }
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                for (final id in ['fp:tree-relay', 'fp:tree-helper']) {
                  final point = cubit.graphController.renderSnapshot
                      .resolvePosition(id);
                  expect(
                    point,
                    isNotNull,
                    reason: '$id must be placed in the rendered tree',
                  );
                  expect(point!.x.isFinite && point.y.isFinite, isTrue);
                }
              },
            ),
          );
        },
      );
    }
  });
}
