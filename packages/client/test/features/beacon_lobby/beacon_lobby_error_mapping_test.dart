import 'package:ferry/ferry.dart' show ServerException;
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
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
}
