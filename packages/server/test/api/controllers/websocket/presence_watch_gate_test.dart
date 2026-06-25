import 'package:test/test.dart';

import 'package:tentura_server/domain/port/beacon_room_co_participant_lookup_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';

/// Mirrors [WebsocketPathUserPresence.onUserPresenceSubscription] peer filter.
Future<List<String>> filterPresenceWatchPeers({
  required VoteUserFriendshipLookupPort friendshipLookup,
  required BeaconRoomCoParticipantLookupPort coParticipantLookup,
  required String viewerId,
  required List<String> requested,
}) async {
  final friends = await friendshipLookup.reciprocalPositivePeerIds(
    viewerId: viewerId,
    peerIds: requested,
  );
  final coParticipants = await coParticipantLookup.coParticipantPeerIds(
    viewerId: viewerId,
    peerIds: requested,
  );
  final allowed = {...friends, ...coParticipants};
  return requested.where(allowed.contains).toList();
}

void main() {
  const viewerId = 'Uviewer';

  group('presence watch peer filter', () {
    test('allows union of friends and co-participants', () async {
      final friendship = _FakeFriendshipLookup({'Ufriend'});
      final coParticipant = _FakeCoParticipantLookup({'Uroommate'});
      final requested = ['Ufriend', 'Uroommate', 'Ustranger'];

      final allowed = await filterPresenceWatchPeers(
        friendshipLookup: friendship,
        coParticipantLookup: coParticipant,
        viewerId: viewerId,
        requested: requested,
      );

      expect(allowed, ['Ufriend', 'Uroommate']);
    });

    test('deduplicates when peer is both friend and co-participant', () async {
      final friendship = _FakeFriendshipLookup({'Uboth'});
      final coParticipant = _FakeCoParticipantLookup({'Uboth'});
      final requested = ['Uboth'];

      final allowed = await filterPresenceWatchPeers(
        friendshipLookup: friendship,
        coParticipantLookup: coParticipant,
        viewerId: viewerId,
        requested: requested,
      );

      expect(allowed, ['Uboth']);
    });

    test('returns empty when neither gate allows anyone', () async {
      final allowed = await filterPresenceWatchPeers(
        friendshipLookup: _FakeFriendshipLookup({}),
        coParticipantLookup: _FakeCoParticipantLookup({}),
        viewerId: viewerId,
        requested: ['Ustranger'],
      );

      expect(allowed, isEmpty);
    });
  });
}

final class _FakeFriendshipLookup implements VoteUserFriendshipLookupPort {
  _FakeFriendshipLookup(this._allowed);

  final Set<String> _allowed;

  @override
  Future<Set<String>> reciprocalPositivePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async =>
      _allowed.intersection(peerIds.toSet());

  @override
  Future<bool> isReciprocalSubscribe({
    required String viewerId,
    required String peerId,
  }) async =>
      _allowed.contains(peerId);

  @override
  Future<bool> isSubscribedTo({
    required String viewerId,
    required String peerId,
  }) async =>
      _allowed.contains(peerId);
}

final class _FakeCoParticipantLookup implements BeaconRoomCoParticipantLookupPort {
  _FakeCoParticipantLookup(this._allowed);

  final Set<String> _allowed;

  @override
  Future<Set<String>> coParticipantPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async =>
      _allowed.intersection(peerIds.toSet());
}
