import 'package:freezed_annotation/freezed_annotation.dart';

part 'evaluation_received.freezed.dart';

enum EvaluationReceivedTrustTone {
  up,
  down,
  noChange,
  noBasis;

  /// Maps server `tone` wire strings (`EvaluationReceivedTrustTone.name`).
  static EvaluationReceivedTrustTone fromWire(String tone) => switch (tone) {
        'up' => EvaluationReceivedTrustTone.up,
        'down' => EvaluationReceivedTrustTone.down,
        'noChange' => EvaluationReceivedTrustTone.noChange,
        'noBasis' => EvaluationReceivedTrustTone.noBasis,
        _ => EvaluationReceivedTrustTone.noChange,
      };
}

@freezed
abstract class EvaluationReceivedRow with _$EvaluationReceivedRow {
  const factory EvaluationReceivedRow({
    required String reviewerId,
    required String reviewerDisplayName,
    required String reviewerImageId,
    required int reviewerRole,
    required int value,
    required EvaluationReceivedTrustTone trustTone,
    required DateTime occurredAt,
    @Default([]) List<String> reasonTags,
    @Default([]) List<String> acknowledgedHelpTags,
    @Default('') String note,
  }) = _EvaluationReceivedRow;
}

@freezed
abstract class EvaluationReceived with _$EvaluationReceived {
  const factory EvaluationReceived({
    required String beaconId,
    required String beaconTitle,
    required bool windowClosed,
    @Default([]) List<EvaluationReceivedRow> rows,
  }) = _EvaluationReceived;
}
