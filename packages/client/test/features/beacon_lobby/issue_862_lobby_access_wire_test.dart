// #862 real-path: lobby access refresh maps readOnlyReason from the wire.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_lobby/data/repository/beacon_lobby_repository.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';

import '../../support/remote_wire_harness.dart';

void main() {
  test('BeaconLobbyAccess maps readOnlyReason cantHelp from GraphQL', () async {
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        'BeaconLobbyAccess': {
          '__typename': 'query_root',
          'BeaconLobbyAccess': {
            '__typename': 'BeaconLobbyAccess',
            'beaconId': 'B862',
            'canRead': true,
            'canPost': false,
            'messageCount': 2,
            'unreadCount': 0,
            'readOnlyReason': 'cant_help',
            'isHelper': true,
            'takesOffers': true,
          },
        },
      },
      sent,
      (remote) async {
        final access = await BeaconLobbyRepository(remote).access('B862');
        expect(access.canPost, isFalse);
        expect(access.limitReason, BeaconLobbyLimitReason.cantHelp);
        expect(sent.single.operationName, 'BeaconLobbyAccess');
        expect(sent.single.variables['beaconId'], 'B862');
      },
    );
  });
}
