import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/oidc_identity.dart';
import 'package:tentura_server/domain/util/contact_linking_policy.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class OidcCase extends UseCaseBase {
  OidcCase(
    this._credentialAuthCase, {
    required super.env,
    required super.logger,
  });

  final CredentialAuthCase _credentialAuthCase;

  /// Resolve or create the account for a verified Google OIDC identity.
  Future<String> completeGoogle(
    OidcIdentity identity, {
    String? inviteId,
  }) {
    final contacts = emailContactsForCredential(
      source: CredentialType.oidcGoogle,
      rawEmail: identity.email,
      providerEmailVerified: identity.emailVerified,
    );
    return _credentialAuthCase.resolveOrCreate(
      type: CredentialType.oidcGoogle,
      identifier: identity.sub,
      displayName: identity.displayName,
      inviteId: inviteId,
      publicData: identity.publicData,
      assertedContacts: contacts,
    );
  }
}
