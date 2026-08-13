import 'package:freezed_annotation/freezed_annotation.dart';

part 'forward_delivery_result.freezed.dart';

@freezed
abstract class ForwardDeliveryResult with _$ForwardDeliveryResult {
  const factory ForwardDeliveryResult({
    required String batchId,
    required List<String> deliveredRecipientIds,
    required List<String> availabilitySkippedRecipientIds,
  }) = _ForwardDeliveryResult;
}
