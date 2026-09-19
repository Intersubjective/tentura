import 'package:tentura_server/domain/attention/attention_clear_models.dart';

/// Storage side of the U08 clear command.
///
/// Two halves, deliberately separated: [captureEligible] decides *what a clear
/// may touch*, once; [apply] decides *what it still may touch*, again, and
/// writes the outcome. Nothing between them widens the membership.
abstract interface class AttentionClearPort {
  /// The viewer's active optional receipts, scoped to [beaconId] (and to
  /// [receiptId] for a single-event dismiss), together with the Request's
  /// outcome identity at this instant.
  Future<AttentionClearCapture> captureEligible({
    required String accountId,
    String? beaconId,
    String? receiptId,
    int limit,
  });

  /// Clears the still-eligible part of [receiptIds] under [operationId].
  ///
  /// Idempotent by [operationId]: the first call records the membership and
  /// its outcome; every later call — including a concurrent one — returns that
  /// same outcome without clearing anything more.
  Future<AttentionClearResult> apply({
    required String accountId,
    required String operationId,
    required String? beaconId,
    required AttentionClearCaptureKind kind,
    required int outcomeGeneration,
    required List<String> receiptIds,
  });
}

class AttentionClearCapture {
  const AttentionClearCapture({
    required this.receiptIds,
    required this.outcomeGeneration,
    required this.decisionRevision,
  });

  final List<String> receiptIds;
  final int outcomeGeneration;
  final int decisionRevision;
}
