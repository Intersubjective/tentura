import 'dart:math' as math;

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
  group('Forward tree people placed beside the saved Field positions', () {
    for (final restoreAfterArrange in [false, true]) {
      testWidgets(
        restoreAfterArrange
            ? 'turning tree arrangement on then off seats tree-only people beside their forwarders without overlapping the Field'
            : 'opening the tree seats tree-only people beside their forwarders without overlapping the Field',
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
                  cubit.toggleForwardTreeArrange();
                }
                expect(cubit.state.forwardTreeOverlay?.arrangeAsTree, isFalse);
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);

                final snapshot = cubit.graphController.renderSnapshot;
                final nodes = snapshot.topology.nodesById;
                expect(nodes, contains('fp:tree-relay'));
                expect(nodes, contains('fp:tree-helper'));
                Rect body(String id) {
                  final p = snapshot.resolvePosition(id)!;
                  final s = nodes[id]!.payload.size;
                  return Rect.fromCenter(
                    center: Offset(p.x, p.y),
                    width: s,
                    height: s,
                  );
                }

                double dist(String a, String b) {
                  final pa = snapshot.resolvePosition(a)!;
                  final pb = snapshot.resolvePosition(b)!;
                  return math.sqrt(
                    math.pow(pa.x - pb.x, 2) + math.pow(pa.y - pb.y, 2),
                  );
                }

                for (final entry in saved.entries) {
                  expect(
                    snapshot.resolvePosition(entry.key),
                    entry.value,
                    reason: '${entry.key} must keep its Field position',
                  );
                }
                // Forward path: am -> tree-relay -> tree-helper.
                const forwarderOf = {
                  'fp:tree-relay': 'fp:am',
                  'fp:tree-helper': 'fp:tree-relay',
                };
                const pathOf = {
                  'fp:tree-relay': {'fp:am'},
                  'fp:tree-helper': {'fp:am', 'fp:tree-relay'},
                };
                for (final treeId in forwarderOf.keys) {
                  for (final savedId in saved.keys) {
                    final overlap = body(treeId).intersect(body(savedId));
                    expect(
                      overlap.width > 0 && overlap.height > 0,
                      isFalse,
                      reason: '$treeId must not sit on Field node $savedId',
                    );
                  }
                  final forwarder = forwarderOf[treeId]!;
                  for (final savedId in saved.keys) {
                    if (pathOf[treeId]!.contains(savedId)) continue;
                    expect(
                      dist(treeId, forwarder),
                      lessThan(dist(treeId, savedId)),
                      reason:
                          '$treeId must sit nearer its forwarder $forwarder '
                          'than Field node $savedId',
                    );
                  }
                }
              },
            ),
          );
        },
      );
    }
  });
}
