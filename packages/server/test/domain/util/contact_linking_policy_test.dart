import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
import 'package:tentura_server/domain/util/contact_linking_policy.dart';

void main() {
  group('contact_linking_policy', () {
    test('email_otp is always authoritative', () {
      expect(
        isAuthoritativeEmail(
          source: CredentialType.emailOtp,
          providerEmailVerified: false,
        ),
        isTrue,
      );
    });

    test('oidc requires provider email_verified', () {
      expect(
        isAuthoritativeEmail(
          source: CredentialType.oidcGoogle,
          providerEmailVerified: true,
        ),
        isTrue,
      );
      expect(
        isAuthoritativeEmail(
          source: CredentialType.oidcGoogle,
          providerEmailVerified: false,
        ),
        isFalse,
      );
    });

    test('emailContactsForCredential normalizes and filters invalid email', () {
      final contacts = emailContactsForCredential(
        source: CredentialType.oidcGoogle,
        rawEmail: 'Ada@Example.COM',
        providerEmailVerified: true,
      );
      expect(contacts, hasLength(1));
      expect(contacts.single.value, 'ada@example.com');
      expect(contacts.single.authoritative, isTrue);
    });

    test('unverified oidc email is not authoritative', () {
      final contacts = emailContactsForCredential(
        source: CredentialType.oidcGoogle,
        rawEmail: 'ada@example.com',
        providerEmailVerified: false,
      );
      expect(contacts.single.authoritative, isFalse);
    });

    test('invalid email yields no contacts', () {
      expect(
        emailContactsForCredential(
          source: CredentialType.emailOtp,
          rawEmail: 'not-an-email',
          providerEmailVerified: true,
        ),
        isEmpty,
      );
    });
  });

  group('AssertedContact', () {
    test('authoritativeOnly drops non-authoritative contacts', () {
      final result = AssertedContact.authoritativeOnly([
        AssertedContact.email(rawEmail: 'a@example.com', authoritative: true),
        AssertedContact.email(rawEmail: 'b@example.com', authoritative: false),
        null,
      ]);
      expect(result, hasLength(1));
      expect(result.single.value, 'a@example.com');
    });
  });
}
