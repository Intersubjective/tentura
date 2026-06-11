import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/oidc_identity.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/util/contact_linking_policy.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class OidcCase extends UseCaseBase {
  OidcCase(
    this._credentialAuthCase,
    this._userRepository, {
    required super.env,
    required super.logger,
  });

  final CredentialAuthCase _credentialAuthCase;
  final UserRepositoryPort _userRepository;

  /// Resolve or create the account for a verified Google OIDC identity (login).
  /// Returns the account id, the linked credential id (session attribution),
  /// and whether a brand-new account was created (drives post-signup UX).
  Future<({String accountId, String? credentialId, bool isNewAccount})>
  completeGoogle(
    OidcIdentity identity, {
    String? inviteId,
  }) async {
    final contacts = emailContactsForCredential(
      source: CredentialType.oidcGoogle,
      rawEmail: identity.email,
      providerEmailVerified: identity.emailVerified,
    );
    final resolved = await _credentialAuthCase.resolveOrCreate(
      type: CredentialType.oidcGoogle,
      identifier: identity.sub,
      displayName: identity.displayName,
      inviteId: inviteId,
      publicData: identity.publicData,
      assertedContacts: contacts,
    );
    final credentialId = await _userRepository.findCredentialId(
      type: CredentialType.oidcGoogle,
      identifier: identity.sub,
    );
    return (
      accountId: resolved.accountId,
      credentialId: credentialId,
      isNewAccount: resolved.isNewAccount,
    );
  }

  /// Settings link mode: strict-link a verified Google identity to [accountId]
  /// (never resolve-or-create, never switch accounts). Authoritative email is
  /// attached only when the provider says it is verified.
  Future<AccountCredentialEntity> linkGoogle({
    required String accountId,
    required OidcIdentity identity,
  }) {
    final contacts = emailContactsForCredential(
      source: CredentialType.oidcGoogle,
      rawEmail: identity.email,
      providerEmailVerified: identity.emailVerified,
    );
    return _userRepository.linkCredentialToAccountStrict(
      accountId: accountId,
      type: CredentialType.oidcGoogle,
      identifier: identity.sub,
      publicData: identity.publicData,
      contacts: contacts,
    );
  }
}
