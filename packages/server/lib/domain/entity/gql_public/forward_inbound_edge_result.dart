import 'package:freezed_annotation/freezed_annotation.dart';

part 'forward_inbound_edge_result.freezed.dart';

@freezed
abstract class ForwardInboundEdgeResult with _$ForwardInboundEdgeResult {
  const factory ForwardInboundEdgeResult({
    required String edgeId,
    required String senderId,
    required String senderName,
    required DateTime createdAt,
    required bool isSuggestedSource,
  }) = _ForwardInboundEdgeResult;
}
