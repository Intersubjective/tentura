import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/forward/domain/forward_trail.dart';

/// #396 / #496: the viewer's forward trail is history, not membership.
final _t = DateTime.utc(2025);

ForwardEdge _edge(
  String id,
  String from,
  String to, {
  int minutes = 0,
  bool cancelled = false,
}) => ForwardEdge(
  id: id,
  beaconId: 'B1',
  createdAt: _t.add(Duration(minutes: minutes)),
  sender: Profile(id: from, displayName: from),
  recipient: Profile(id: to, displayName: to),
  cancelledAt: cancelled ? _t.add(const Duration(days: 1)) : null,
);

void main() {
  test('keeps outgoing and inbound edges of the viewer only', () {
    final trail = viewerForwardTrail([
      _edge('in', 'nina', 'me'),
      _edge('out', 'me', 'omar', minutes: 1),
      _edge('other', 'nina', 'omar', minutes: 2),
    ], viewerUserId: 'me');
    expect(trail.map((e) => e.id), ['out', 'in']);
  });

  test('a cancelled outgoing forward stays; a cancelled inbound one goes', () {
    final trail = viewerForwardTrail([
      _edge('out', 'me', 'omar', cancelled: true),
      _edge('in', 'nina', 'me', cancelled: true),
    ], viewerUserId: 'me');
    expect(trail.map((e) => e.id), ['out']);
    expect(trail.single.isCancelled, isTrue);
  });

  test('one row per direction and person; a live edge wins over a '
      'cancelled one', () {
    final trail = viewerForwardTrail([
      _edge('old', 'me', 'omar', cancelled: true),
      _edge('new', 'me', 'omar', minutes: -5),
      _edge('back', 'omar', 'me', minutes: 3),
    ], viewerUserId: 'me');
    expect(trail.map((e) => e.id), ['back', 'new']);
  });

  test('trailHasLiveForward ignores cancelled edges', () {
    final trail = [_edge('out', 'me', 'omar', cancelled: true)];
    expect(
      trailHasLiveForward(trail, senderId: 'me', recipientId: 'omar'),
      isFalse,
    );
    expect(
      trailHasLiveForward(
        [_edge('out', 'me', 'omar')],
        senderId: 'me',
        recipientId: 'omar',
      ),
      isTrue,
    );
  });
}
