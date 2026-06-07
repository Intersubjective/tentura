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

/// Parity with email verify: re-preview invite page after OAuth with session cookie.
String appendSignedInIfInvite(String destination) {
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
          },
        )
        .toString();
  }
  return destination;
}

String destinationAfterOAuthCallback({
  required String returnTo,
  required String publicOrigin,
}) {
  if (returnTo.isEmpty) {
    return publicOrigin.endsWith('/')
        ? publicOrigin
        : '$publicOrigin/';
  }
  return appendSignedInIfInvite(returnTo);
}
