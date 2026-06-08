import 'package:test/test.dart';

import 'package:tentura/domain/exception/credential_exception.dart';
import 'package:tentura/features/credentials/data/repository/credentials_repository.dart';

void main() {
  test('mapLinkStatus maps 409 to CredentialConflictException', () {
    final error = CredentialsRepository.mapLinkStatus(409);
    expect(error, isA<CredentialConflictException>());
  });

  test('mapRemoveStatus maps 409 to LastCredentialException', () {
    final error = CredentialsRepository.mapRemoveStatus(409);
    expect(error, isA<LastCredentialException>());
  });
}
