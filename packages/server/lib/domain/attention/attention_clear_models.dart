/// U08 — the clear command's vocabulary.
///
/// Clearing is the *optional* axis (D02): a receipt that no longer asks for
/// attention. It is not `seen_at`, which keeps meaning "read", and it is never
/// a wall-clock boundary — the set of receipts a clear may touch is captured
/// once, as a finite membership, and never re-derived at apply time. Collapse
/// rewrites `created_at`, so "everything older than my tap" is not a boundary
/// this system can express.
library;

import 'dart:convert';

/// Why a receipt was cleared. `sweep` (U09) and `legacy_seen` (U18) are in the
/// frozen vocabulary of `notification_outbox.clear_reason` but are not issued
/// by this unit.
enum AttentionClearCaptureKind {
  /// The viewer dismissed one event, or the optional set of one card.
  explicit('explicit'),

  /// The viewer opened the Request and its optional updates were absorbed.
  requestOpen('request_open');

  const AttentionClearCaptureKind(this.wireName);

  final String wireName;

  static AttentionClearCaptureKind fromWireName(String value) =>
      AttentionClearCaptureKind.values.firstWhere(
        (kind) => kind.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'kind',
          "must be 'explicit' or 'request_open'",
        ),
      );
}

/// What an apply did with the membership it was handed.
enum AttentionClearStatus {
  /// Every member was cleared.
  complete,

  /// Some members were cleared; the rest were skipped or denied.
  partial,

  /// Nothing was cleared and nothing was denied: the membership had gone
  /// ineligible (already cleared, or no longer visible) before the apply.
  stale,

  /// Nothing was cleared and at least one member did not belong to the caller.
  denied,
}

/// An issued capture: the opaque token plus the diagnostics a caller (and the
/// tests) need to reason about it.
class AttentionClearSnapshot {
  const AttentionClearSnapshot({
    required this.token,
    required this.receiptIds,
    required this.beaconId,
    required this.kind,
    required this.outcomeGeneration,
    required this.decisionRevision,
  });

  final String token;
  final List<String> receiptIds;
  final String? beaconId;
  final AttentionClearCaptureKind kind;

  /// Read from `attention_request_state` at capture time and carried onto
  /// every operation member. That table has no writer yet (U09/U10 own it), so
  /// both values are `0` today; once those writers exist, a mismatch between
  /// the captured generation and the live one is how U09 detects that the
  /// Request's outcome moved under an in-flight clear.
  final int outcomeGeneration;
  final int decisionRevision;
}

/// The authoritative answer of one apply. Replaying the same `operationId`
/// reproduces it.
class AttentionClearResult {
  const AttentionClearResult({
    required this.operationId,
    required this.appliedReceiptIds,
    required this.skippedReceiptIds,
    required this.deniedReceiptIds,
    required this.status,
  });

  final String operationId;
  final List<String> appliedReceiptIds;
  final List<String> skippedReceiptIds;

  /// Ids the caller supplied that do not resolve to a receipt of this account.
  /// A receipt belonging to somebody else and a receipt that never existed are
  /// reported identically, so the answer discloses neither.
  final List<String> deniedReceiptIds;

  final AttentionClearStatus status;
}

/// The decoded snapshot token.
///
/// Transport is the base64url-JSON shape the feed cursor uses, with its own
/// schema version so the two can never be confused. The token is *opaque*, not
/// *trusted*: the account inside it is checked against the caller's JWT, and
/// every member is re-authorized against `visible_attention_receipts` at apply
/// time. Tampering with the member list therefore cannot clear anything the
/// caller could not already clear — it only produces denials.
class AttentionClearSnapshotToken {
  const AttentionClearSnapshotToken({
    required this.accountId,
    required this.beaconId,
    required this.kind,
    required this.outcomeGeneration,
    required this.decisionRevision,
    required this.receiptIds,
  });

  factory AttentionClearSnapshotToken.decode(String value) {
    try {
      final padding = '=' * ((4 - value.length % 4) % 4);
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode('$value$padding')),
      );
      if (decoded is! Map) throw const FormatException();
      if (decoded['v'] != schemaVersion) throw const FormatException();
      final accountId = decoded['a'];
      final beaconId = decoded['b'];
      final kind = decoded['k'];
      final outcomeGeneration = decoded['g'];
      final decisionRevision = decoded['d'];
      final receiptIds = decoded['r'];
      if (accountId is! String ||
          accountId.isEmpty ||
          (beaconId != null && beaconId is! String) ||
          kind is! String ||
          outcomeGeneration is! int ||
          decisionRevision is! int ||
          outcomeGeneration < 0 ||
          decisionRevision < 0 ||
          receiptIds is! List ||
          receiptIds.length > maxMembers ||
          receiptIds.any(
            (id) => id is! String || id.isEmpty || id.length > 64,
          )) {
        throw const FormatException();
      }
      return AttentionClearSnapshotToken(
        accountId: accountId,
        beaconId: beaconId as String?,
        kind: AttentionClearCaptureKind.fromWireName(kind),
        outcomeGeneration: outcomeGeneration,
        decisionRevision: decisionRevision,
        receiptIds: [for (final id in receiptIds) id as String],
      );
    } on Object {
      throw ArgumentError.value(
        value,
        'snapshotToken',
        'invalid attention clear snapshot token',
      );
    }
  }

  /// Bumped independently of the feed cursor's shape.
  static const int schemaVersion = 1;

  /// One Request's optional set. A sweep across a whole surface is U09 and
  /// does not use this token.
  static const int maxMembers = 500;

  final String accountId;
  final String? beaconId;
  final AttentionClearCaptureKind kind;
  final int outcomeGeneration;
  final int decisionRevision;
  final List<String> receiptIds;

  String encode() => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'v': schemaVersion,
            'a': accountId,
            'b': beaconId,
            'k': kind.wireName,
            'g': outcomeGeneration,
            'd': decisionRevision,
            'r': receiptIds,
          }),
        ),
      )
      .replaceAll('=', '');
}
