/// Typed translations of the fact-history GraphQL error codes (plan §14).
///
/// Thrown by the routing link's `onGraphQLError` handler in
/// `data/service/remote_api_client/build_client.dart` when it recognizes one
/// of these codes in a GraphQL error's `extensions.code`, the same way
/// `BeaconHierarchyException` is already handled there.
sealed class BeaconFactCardException implements Exception {
  const BeaconFactCardException([this.message]);

  final Object? message;

  @override
  String toString() => message?.toString() ?? super.toString();
}

/// The fact was edited concurrently; the caller's edit was based on a stale
/// revision.
final class BeaconFactEditConflictException extends BeaconFactCardException {
  const BeaconFactEditConflictException({this.currentSeq, Object? message})
    : super(message);

  /// The fact's current revision seq, when the server reported one.
  final int? currentSeq;

  static const codeNumber = 1318;
}

/// The fact has been removed and no longer accepts edits.
final class BeaconFactRemovedException extends BeaconFactCardException {
  const BeaconFactRemovedException([super.message]);

  static const codeNumber = 1319;
}

/// The actor is editing facts faster than the per-actor rate limit allows.
final class BeaconFactRateLimitedException extends BeaconFactCardException {
  const BeaconFactRateLimitedException([super.message]);

  static const codeNumber = 1320;
}

/// Throws the matching [BeaconFactCardException] for a recognized fact-card
/// GraphQL error [code]. Returns normally (no throw) for any other code —
/// notably 1317 (`BeaconHierarchyCursorInvalidException`), which is handled
/// by `throwIfBeaconHierarchyError` — so the caller falls through to its
/// generic mapping.
void throwIfBeaconFactCardError(int? code, Map<String, dynamic>? extensions) {
  switch (code) {
    case BeaconFactEditConflictException.codeNumber:
      throw BeaconFactEditConflictException(
        currentSeq: (extensions?['currentSeq'] as num?)?.toInt(),
      );
    case BeaconFactRemovedException.codeNumber:
      throw const BeaconFactRemovedException();
    case BeaconFactRateLimitedException.codeNumber:
      throw const BeaconFactRateLimitedException();
  }
}
