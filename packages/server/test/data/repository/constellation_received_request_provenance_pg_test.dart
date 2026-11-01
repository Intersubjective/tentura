@Tags(['pg', 'repo-files'])
library;

import 'package:test/test.dart';

import '../../support/forwarded_request_field_response.dart';

const _viewer = 'Uviewer000001';
const _bob = 'Uforwardbob01';
const _alice = 'Uauthoralice1';
const _request = 'Bforwarded001';

void main() {
  test('the Field response identifies the contact who forwarded a distant '
      "author's Request to the viewer", () async {
    final scenario = await readForwardedRequestFieldResponse();
    if (scenario == null) {
      markTestSkipped('Postgres unavailable');
      return;
    }
    // Assert the graph through the reader's explicit-trust predicate. Alice
    // is exactly two hops away; Zed's sole ordinary visible contact is Bob.
    expect(
      scenario.trustEdges,
      unorderedEquals([
        (_viewer, _bob),
        (_bob, _viewer),
        (_bob, _alice),
        (_alice, _bob),
      ]),
    );
    expect(scenario.ordinaryVisiblePeerIds, [_bob]);
    expect(
      scenario.forwards,
      unorderedEquals([
        (_alice, _bob),
        (_bob, _viewer),
      ]),
    );
    final field =
        scenario.response['constellationField'] as Map<String, dynamic>;
    expect(field['directContactIds'], [_bob]);
    final author = (field['peers'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (peer) => peer['id'] == _alice,
        );
    expect(author['presence'], 'temporary');
    expect(author['temporaryBeaconId'], _request);
    final request = (field['requests'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (request) => request['id'] == _request,
        );
    expect(request['authorId'], _alice);
    expect(request['viewerHasForwardEdge'], isTrue);

    // The helper executes the production client .graphql document against
    // the real Field resolver. Compare that response with the incoming edge
    // and its sender's database profile, independently of the client fixture.
    final incomingSender = scenario.forwards
        .singleWhere(
          (edge) => edge.$2 == _viewer,
        )
        .$1;
    expect(incomingSender, _bob);
    expect(scenario.forwarder.id, incomingSender);
    expect(scenario.forwarder.displayName, 'Bob');
    expect(
      request,
      allOf([
        containsPair('forwardedById', incomingSender),
        containsPair('forwardedByName', scenario.forwarder.displayName),
      ]),
      reason:
          'The Request author is Alice and the viewer is Zed, but the '
          'received-forward sender must be Bob.',
    );
  });
}
