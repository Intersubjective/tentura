import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/credentials/domain/entity/credential_entity.dart';
import 'package:tentura/features/credentials/domain/entity/credential_link_policy.dart';
import 'package:tentura/features/credentials/domain/entity/credential_types.dart';

CredentialEntity _credential({
  required String id,
  required String type,
  String identifier = 'id',
}) =>
    CredentialEntity(id: id, type: type, identifier: identifier);

void main() {
  group('CredentialLinkPolicy.canLink', () {
    test('empty linked list allows Google, Email, and recovery seed', () {
      const linked = <CredentialEntity>[];

      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.oidcGoogle, linked),
        isTrue,
      );
      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.emailOtp, linked),
        isTrue,
      );
      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.ed25519Device, linked),
        isTrue,
      );
    });

    test('linked Google blocks Google only', () {
      final linked = [
        _credential(id: 'c1', type: CredentialTypes.oidcGoogle),
      ];

      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.oidcGoogle, linked),
        isFalse,
      );
      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.emailOtp, linked),
        isTrue,
      );
      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.ed25519Device, linked),
        isTrue,
      );
    });

    test('linked Email blocks Email only', () {
      final linked = [
        _credential(id: 'c1', type: CredentialTypes.emailOtp),
      ];

      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.oidcGoogle, linked),
        isTrue,
      );
      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.emailOtp, linked),
        isFalse,
      );
      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.ed25519Device, linked),
        isTrue,
      );
    });

    test('multiple device keys still allow Google, Email, and more seeds', () {
      final linked = [
        _credential(id: 'c1', type: CredentialTypes.ed25519Device, identifier: 'pk1'),
        _credential(id: 'c2', type: CredentialTypes.ed25519Device, identifier: 'pk2'),
      ];

      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.oidcGoogle, linked),
        isTrue,
      );
      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.emailOtp, linked),
        isTrue,
      );
      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.ed25519Device, linked),
        isTrue,
      );
    });

    test('linked Google and Email allow only recovery seed', () {
      final linked = [
        _credential(id: 'c1', type: CredentialTypes.oidcGoogle),
        _credential(id: 'c2', type: CredentialTypes.emailOtp),
      ];

      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.oidcGoogle, linked),
        isFalse,
      );
      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.emailOtp, linked),
        isFalse,
      );
      expect(
        CredentialLinkPolicy.canLink(CredentialTypes.ed25519Device, linked),
        isTrue,
      );
    });

    test('unknown type is not linkable', () {
      expect(
        CredentialLinkPolicy.canLink('webauthn', const []),
        isFalse,
      );
    });
  });
}
