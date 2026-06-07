/// Strict parser for OIDC `email_verified` claims.
///
/// Only boolean `true` and the string `"true"` are treated as verified.
/// Missing, false, or ambiguous values are non-authoritative.
bool parseOidcEmailVerified(Object? raw) {
  if (identical(raw, true)) return true;
  if (raw is String && raw.toLowerCase() == 'true') return true;
  return false;
}
