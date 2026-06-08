import 'package:tentura_server/domain/entity/oidc_identity.dart';

/// Exchange an OAuth authorization code for a verified OIDC identity.
abstract class OidcProviderPort {
  bool get isConfigured;

  /// Google authorization URL query (without host).
  Uri buildGoogleAuthorizeUri({
    required String redirectUri,
    required String state,
    required String codeChallenge,
    required String nonce,
  });

  Future<OidcIdentity> exchangeGoogleCode({
    required String code,
    required String redirectUri,
    required String codeVerifier,
    required String expectedNonce,
  });

  /// Verify a Google-issued id token directly (native `google_sign_in` flow):
  /// JWKS signature, issuer, and an `aud` allow-list (web + iOS client ids).
  /// When [expectedNonce] is null the nonce check is skipped (native tokens
  /// carry no server-issued nonce). Requires only the Google client id (no
  /// client secret), so it works even when the web OAuth flow is unconfigured.
  Future<OidcIdentity> verifyGoogleIdToken(
    String idToken, {
    String? expectedNonce,
  });
}
