import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';

import '../../support/remote_wire_harness.dart';

const _postId = 'Bpostaliaswire1';

void main() {
  test('PostViewRoute path param feeds BeaconKindFetch on the wire', () async {
    final route = PostViewRoute(id: _postId);
    expect(route.rawPathParams['id'], _postId);

    final sent = <WireSent>[];
    await withRemoteWire(
      {
        'BeaconKindFetch': {
          '__typename': 'query_root',
          'beacon_by_pk': {
            '__typename': 'beacon',
            'id': _postId,
            'kind': 1,
          },
        },
      },
      sent,
      (remote) async {
        await remote.setSessionAuth();
        final repo = BeaconKindRepository(remote);
        await repo.fetchKind(route.rawPathParams['id']! as String);
      },
    );

    expect(
      sent.where((w) => w.operationName == 'BeaconKindFetch').map((w) => w.variables['id']),
      contains(_postId),
    );
    expect(sent.map((w) => w.variables['id']), isNot(contains(':id')));
  });
}
