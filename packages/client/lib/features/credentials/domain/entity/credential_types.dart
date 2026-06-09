/// Wire values for credential `type` fields (mirrors server `CredentialType`).
abstract final class CredentialTypes {
  static const ed25519Device = 'ed25519_device';
  static const oidcGoogle = 'oidc:google';
  static const emailOtp = 'email_otp';
}
