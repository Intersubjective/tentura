import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/forward/domain/forward_trail.dart';

/// #496 review: the People tab checks every helper tile's "forwarded
/// directly" claim against this viewer's forward trail. The trail is derived
/// once per state, not once per tile on every build.
final _t = DateTime.utc(2026, 10, 20);
const _author = Profile(id: 'auth', displayName: 'Author');

ForwardEdge _forward(String id, String from, String to, {int minutes = 0}) =>
    ForwardEdge(
      id: id,
      beaconId: 'B496',
      createdAt: _t.add(Duration(minutes: minutes)),
      sender: Profile(id: from, displayName: from),
      recipient: Profile(id: to, displayName: to),
    );

BeaconViewState _state(List<ForwardEdge> edges) => BeaconViewState(
  beacon: Beacon(
    id: 'B496',
    title: 'T',
    author: _author,
    createdAt: _t,
    updatedAt: _t,
  ),
  myProfile: _author,
  helpOffers: [
    TimelineHelpOffer(
      user: const Profile(id: 'h1', displayName: 'h1'),
      message: 'I can help',
      createdAt: _t,
      updatedAt: _t,
      isDirectAuthorForward: true,
    ),
    TimelineHelpOffer(
      user: const Profile(id: 'h2', displayName: 'h2'),
      message: 'Me too',
      createdAt: _t,
      updatedAt: _t,
      isDirectAuthorForward: true,
    ),
  ],
  viewerForwardEdges: edges,
  forwardsLoaded: true,
);

void main() {
  final edges = [
    _forward('e1', 'auth', 'h1'),
    _forward('e2', 'auth', 'h3', minutes: 1),
    _forward('e3', 'x', 'h1', minutes: 2),
  ];

  test('the viewer trail is derived once per state and reused', () {
    final state = _state(edges);
    final trail = state.viewerTrail;
    expect(identical(state.viewerTrail, trail), isTrue);
    expect(
      trail.map((e) => e.id),
      viewerForwardTrail(edges, viewerUserId: 'auth').map((e) => e.id),
    );
  });

  test('a new state derives its own trail', () {
    final first = _state(edges);
    final second = first.copyWith(viewerForwardEdges: [edges.first]);
    expect(second.viewerTrail.map((e) => e.id), ['e1']);
    expect(first.viewerTrail.map((e) => e.id), ['e2', 'e1']);
  });

  test('helper tiles read the direct-forward claim off the shared trail', () {
    final state = _state(edges);
    // h1: a live author forward on the trail confirms the server flag.
    expect(
      state.offerOnForwardTrail(state.helpOffers[0]).isDirectAuthorForward,
      isTrue,
    );
    // h2: no author forward to h2 on the trail, so no claim.
    expect(
      state.offerOnForwardTrail(state.helpOffers[1]).isDirectAuthorForward,
      isFalse,
    );
  });
}
