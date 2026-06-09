///
/// Decoded landing -> app session-handoff payload.
///
/// Transferred via a URL fragment (`#th=<base64url(utf8(json))>`) from the
/// static landing to the WASM app on the same public origin, then written to
/// secure storage by the app itself. See `docs/handoff-contract.md`.
///
class HandoffPayload {
  const HandoffPayload({
    required this.userId,
    required this.seed,
    this.displayName,
  });

  final String userId;

  /// base64url-encoded 32-byte account seed (same format as `AuthCase.signUp`).
  final String seed;

  final String? displayName;
}
