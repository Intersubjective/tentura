/// Same-origin OAuth return targets for invite landing flows.
String sanitizeOAuthReturnTo({
  required String? raw,
  required String publicOrigin,
}) {
  if (raw == null || raw.isEmpty) return '';
  final allowedOrigin = Uri.parse(publicOrigin).origin;

  if (raw.startsWith('/')) {
    final combined = Uri.parse('$allowedOrigin$raw');
    if (combined.origin != allowedOrigin) return '';
    return combined.toString();
  }

  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) return '';
  if (uri.origin != allowedOrigin) return '';
  return uri.toString();
}

/// Parity with email verify: re-preview invite page after OAuth with session
/// cookie. `isNewAccount` adds `new=1` (post-signup name + onboarding flow).
String appendSignedInIfInvite(
  String destination, {
  bool isNewAccount = false,
}) {
  final uri = Uri.parse(destination);
  final segments = uri.pathSegments;
  if (segments.length == 2 &&
      segments[0] == 'invite' &&
      segments[1].isNotEmpty) {
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'signed_in': '1',
            if (isNewAccount) 'new': '1',
          },
        )
        .toString();
  }
  return destination;
}

String destinationAfterOAuthCallback({
  required String returnTo,
  required String publicOrigin,
  bool isNewAccount = false,
}) {
  if (returnTo.isEmpty) {
    // New account with no return target: `/` would route into WASM
    // (cookie-presence split, ADR 0002); `/invite/` always serves the landing,
    // which owns the post-signup name + onboarding flow.
    if (isNewAccount) {
      return Uri.parse(publicOrigin)
          .replace(
            path: '/invite/',
            queryParameters: {'signed_in': '1', 'new': '1'},
          )
          .toString();
    }
    return publicOrigin.endsWith('/')
        ? publicOrigin
        : '$publicOrigin/';
  }
  return appendSignedInIfInvite(returnTo, isNewAccount: isNewAccount);
}
