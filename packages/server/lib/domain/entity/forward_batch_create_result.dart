import 'package:freezed_annotation/freezed_annotation.dart';

import 'forward_edge_created.dart';

part 'forward_batch_create_result.freezed.dart';

@freezed
abstract class ForwardBatchCreateResult with _$ForwardBatchCreateResult {
  const factory ForwardBatchCreateResult({
    required List<ForwardEdgeCreated> createdEdges,
    required List<String> availabilitySkippedRecipientIds,

    /// Not inserted because this sender already has an active edge to them,
    /// including one a concurrent call inserted first.
    @Default(<String>[]) List<String> alreadyForwardedRecipientIds,

    /// The active edge ID keyed by recipient ID for already-forwarded recipients.
    @Default(<String, String>{}) Map<String, String> alreadyForwardedEdgeIds,
  }) = _ForwardBatchCreateResult;
}
