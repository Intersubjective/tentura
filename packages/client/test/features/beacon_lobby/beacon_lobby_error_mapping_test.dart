import 'package:ferry/ferry.dart' show ServerException;
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/beacon_lobby/data/model/beacon_lobby_error_mapper.dart';
import 'package:tentura/features/beacon_lobby/domain/exception/beacon_lobby_exception.dart';

/// U088 — "not for you" (server 1347) stays a typed denial through the
/// error link; any other failure is not mistaken for it.
void main() {
  test('code 1347 becomes BeaconLobbyUnavailableException', () {
    expect(
      () => throwIfBeaconLobbyError(1347),
      throwsA(isA<BeaconLobbyUnavailableException>()),
    );
    expect(() => throwIfBeaconLobbyError(1102), returnsNormally);
    expect(() => throwIfBeaconLobbyError(null), returnsNormally);
  });

  test('the denial survives the link wrapper', () {
    expect(
      mapRemoteFailure(
        const ServerException(
          originalException: BeaconLobbyUnavailableException(),
        ),
      ),
      isA<BeaconLobbyUnavailableException>(),
    );
  });

  test('a refused Questions read (1102) is the denial; a refused post asks '
      'for a fresh read; never raw server text (#683)', () {
    const refused = RemoteApiException(
      'Room or item thread access required',
      code: '1102',
    );
    expect(
      beaconLobbyScopeError(refused),
      isA<BeaconLobbyUnavailableException>(),
    );
    expect(
      beaconLobbyScopeError(refused, write: true),
      isA<BeaconLobbyPostDeniedException>(),
    );
    const other = RemoteApiException('boom', code: '1000');
    expect(beaconLobbyScopeError(other), same(other));
    final network = Exception('network');
    expect(beaconLobbyScopeError(network), same(network));
  });
}
