import 'package:freezed_annotation/freezed_annotation.dart';

import 'evaluation_received.dart';

part 'evaluations_written_about_viewer.freezed.dart';

@freezed
abstract class EvaluationsWrittenAboutViewerRow
    with _$EvaluationsWrittenAboutViewerRow {
  const factory EvaluationsWrittenAboutViewerRow({
    required String beaconId,
    required String beaconTitle,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required EvaluationReceivedTrustTone trustTone,
    required DateTime occurredAt,
    DateTime? beaconClosedAt,
    @Default([]) List<String> reasonTags,
    @Default('') String note,
  }) = _EvaluationsWrittenAboutViewerRow;
}
