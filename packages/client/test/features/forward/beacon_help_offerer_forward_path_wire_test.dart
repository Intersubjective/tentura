import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';

void main() {
  test('fetchHelpOffererForwardPath maps path nodes from GraphQL', () async {
    const beaconId = 'B0000000000000000000000001';
    const helperId = 'U0000000000000000000000002';
    const authorId = 'U0000000000000000000000001';

    final sent = <WireSent>[];
    await withRemoteWire(
      {
        'BeaconHelpOffererForwardPath': {
          'beaconHelpOffererForwardPath': {
            'beaconId': beaconId,
            'authorId': authorId,
            'viewerId': authorId,
            'helpOffererIds': [helperId],
            'edges': <Map<String, dynamic>>[],
            'path': [
              {
                'userId': authorId,
                'displayName': 'Anna',
                'anonymousCount': 0,
              },
              {
                'userId': 'U0000000000000000000000003',
                'displayName': 'Boris',
                'anonymousCount': 0,
              },
              {
                'userId': null,
                'displayName': null,
                'anonymousCount': 1,
              },
              {
                'userId': helperId,
                'displayName': 'Vera',
                'anonymousCount': 0,
              },
            ],
          },
        },
      },
      sent,
      (remote) async {
        final repo = ForwardRepository(
          remote,
          _UnusedBeaconRepository(),
          buildTestRealtimeSync().port,
        );
        final graph = await repo.fetchHelpOffererForwardPath(
          beaconId: beaconId,
          helpOffererId: helperId,
        );
        expect(sent.single.variables, {
          'id': beaconId,
          'helpOffererId': helperId,
        });
        expect(graph.path, hasLength(4));
        expect(graph.path[0].displayName, 'Anna');
        expect(graph.path[1].displayName, 'Boris');
        expect(graph.path[2].anonymousCount, 1);
        expect(graph.path[3].userId, helperId);
      },
    );
  });
}

class _UnusedBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
