import 'package:freezed_annotation/freezed_annotation.dart';

part 'forward_delivery_result.freezed.dart';

@freezed
abstract class ForwardDeliveryResult with _$ForwardDeliveryResult {
  const factory ForwardDeliveryResult({
    required String batchId,
    required List<String> deliveredRecipientIds,
    required List<String> availabilitySkippedRecipientIds,

    /// Not delivered: this sender already has an active edge to them on this
    /// beacon (including one inserted concurrently).
    @Default(<String>[]) List<String> alreadyForwardedRecipientIds,

    /// Not delivered: blocked by or hidden from the sender.
    @Default(<String>[]) List<String> blockedSkippedRecipientIds,
  }) = _ForwardDeliveryResult;
}
