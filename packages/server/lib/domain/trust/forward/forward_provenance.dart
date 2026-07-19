import 'package:freezed_annotation/freezed_annotation.dart';

part 'forward_provenance.freezed.dart';

@freezed
abstract class ForwardProvenanceEdge with _$ForwardProvenanceEdge {
  const factory ForwardProvenanceEdge({
    required String id,
    required String senderId,
    required String recipientId,
    required DateTime createdAt,
    String? parentEdgeId,
    String? batchId,
    DateTime? cancelledAt,
  }) = _ForwardProvenanceEdge;
}

@freezed
abstract class ForwardAttributionInput with _$ForwardAttributionInput {
  const factory ForwardAttributionInput({
    required String batchId,
    required String parentForwardEdgeId,
    required double weight,
  }) = _ForwardAttributionInput;
}

extension ForwardProvenanceEdgeMapper on ForwardProvenanceEdge {
  static ForwardProvenanceEdge fromEntity({
    required String id,
    required String senderId,
    required String recipientId,
    required DateTime createdAt,
    String? parentEdgeId,
    String? batchId,
    DateTime? cancelledAt,
  }) =>
      ForwardProvenanceEdge(
        id: id,
        senderId: senderId,
        recipientId: recipientId,
        createdAt: createdAt,
        parentEdgeId: parentEdgeId,
        batchId: batchId,
        cancelledAt: cancelledAt,
      );
}
