import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/exception/credential_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/features/auth/data/service/web_redirect.dart';
import 'package:tentura/features/credentials/data/repository/credentials_repository.dart';
import 'package:tentura/features/credentials/domain/entity/credential_entity.dart';

void main() {
  group('CredentialEntity.fromMap', () {
    test('parses the server credential shape', () {
      final c = CredentialEntity.fromMap(const {
        'id': 'c1',
        'type': 'ed25519_device',
        'identifier': 'PUBKEY',
        'createdAt': '2026-05-31T10:20:30.000Z',
      });
      expect(c.id, 'c1');
      expect(c.type, 'ed25519_device');
      expect(c.identifier, 'PUBKEY');
      expect(c.createdAt, DateTime.utc(2026, 5, 31, 10, 20, 30));
    });

    test('tolerates a missing / non-string createdAt', () {
      final c = CredentialEntity.fromMap(const {
        'id': 'c2',
        'type': 'ed25519_device',
        'identifier': 'PK',
      });
      expect(c.createdAt, isNull);
    });
  });

  group('CredentialsRepository.mapRemoveStatus', () {
    test('409 -> last credential', () {
      expect(
        CredentialsRepository.mapRemoveStatus(409),
        isA<LastCredentialException>(),
      );
    });

    test('404 -> not found', () {
      expect(
        CredentialsRepository.mapRemoveStatus(404),
        isA<CredentialNotFoundException>(),
      );
    });

    test('other status -> unknown', () {
      expect(
        CredentialsRepository.mapRemoveStatus(500),
        isA<ServerUnknownException>(),
      );
    });
  });

  group('goToLanding (native stub)', () {
    test('is a no-op off the web and reports it did not navigate', () {
      // On the Dart VM the conditional export resolves to the stub.
      expect(goToLanding(), isFalse);
      expect(goToLanding(invitePath: '/invite/I1'), isFalse);
    });
  });
}
