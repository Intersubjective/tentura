import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';

/// Whether an email from [source] is authoritative for identity unification.
bool isAuthoritativeEmail({
  required CredentialType source,
  required bool providerEmailVerified,
}) {
  switch (source) {
    case CredentialType.emailOtp:
      return true;
    case CredentialType.oidcGoogle:
    case CredentialType.oidcApple:
      return providerEmailVerified;
    case CredentialType.ed25519Device:
    case CredentialType.webauthn:
      return false;
  }
}

/// Builds email [AssertedContact]s for a credential [source].
List<AssertedContact> emailContactsForCredential({
  required CredentialType source,
  required String rawEmail,
  required bool providerEmailVerified,
}) {
  final authoritative = isAuthoritativeEmail(
    source: source,
    providerEmailVerified: providerEmailVerified,
  );
  final contact = AssertedContact.email(
    rawEmail: rawEmail,
    authoritative: authoritative,
  );
  if (contact == null) return const [];
  return [contact];
}
