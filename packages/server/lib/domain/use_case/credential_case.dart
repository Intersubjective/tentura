import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/port/oidc_provider_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

import 'auth_case.dart';
import 'oidc_case.dart';
import '_use_case_base.dart';

/// Authenticated credential management (`/accounts/me/credentials`): list, link
/// and remove the `account_credential` rows of one account.
///
/// Phase 1 slice 2 wires the `ed25519_device` provider only — linking proves
/// possession of a new device key via [AuthCase.verifyDeviceAuthRequest]. The
/// externally-gated providers (WebAuthn, OIDC, email-OTP) land in later slices.
///
/// Conflict policy: refuse a `(type, identifier)` already linked to a different
/// account. Verified-contact unification may auto-link new credentials when
/// an authoritative contact matches exactly one existing account. Removal policy
/// (cannot remove the last credential) is enforced in [UserRepositoryPort].
/// Removing a credential does **not** yet revoke its live sessions — JWTs are
/// stateless and expire in ~1h; immediate revocation is owed.
@Injectable(order: 2)
final class CredentialCase extends UseCaseBase {
  CredentialCase(
    this._userRepository,
    this._authCase,
    this._oidcProvider,
    this._oidcCase, {
    required super.env,
    required super.logger,
  });

  final UserRepositoryPort _userRepository;

  final AuthCase _authCase;

  final OidcProviderPort _oidcProvider;

  final OidcCase _oidcCase;

  /// All credentials linked to [accountId].
  Future<List<AccountCredentialEntity>> list({
    required String accountId,
  }) => _userRepository.listCredentials(accountId: accountId);

  /// Link a new `ed25519_device` credential. [authRequestToken] is an EdDSA
  /// auth-request JWT signed by the new device key (same shape as sign-in).
  Future<AccountCredentialEntity> linkDevice({
    required String accountId,
    required String authRequestToken,
  }) => _userRepository.addCredential(
    accountId: accountId,
    type: CredentialType.ed25519Device,
    identifier: _authCase.verifyDeviceAuthRequest(authRequestToken),
  );

  /// Link a Google identity proven by a native `google_sign_in` [idToken]
  /// (verified directly — no redirect). Strict-links `oidc:google` to
  /// [accountId]; throws `CredentialConflictException` /
  /// `ContactConflictException` on cross-account ownership.
  Future<AccountCredentialEntity> linkGoogleNative({
    required String accountId,
    required String idToken,
  }) async {
    final identity = await _oidcProvider.verifyGoogleIdToken(idToken);
    return _oidcCase.linkGoogle(accountId: accountId, identity: identity);
  }

  /// Remove credential [credentialId] from [accountId].
  Future<void> remove({
    required String accountId,
    required String credentialId,
  }) => _userRepository.removeCredential(
    accountId: accountId,
    credentialId: credentialId,
  );
}
