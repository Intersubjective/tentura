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
}
