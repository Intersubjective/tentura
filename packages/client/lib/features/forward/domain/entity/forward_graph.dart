import 'package:freezed_annotation/freezed_annotation.dart';

part 'forward_graph.freezed.dart';

/// One forward edge as returned by the V2 `beaconForwardGraph` query.
@freezed
abstract class ForwardGraphEdge with _$ForwardGraphEdge {
  const factory ForwardGraphEdge({
    required String id,
    required String beaconId,
    required String senderId,
    required String recipientId,
    String? parentEdgeId,
    String? batchId,
  }) = _ForwardGraphEdge;

  const ForwardGraphEdge._();
}

/// Result payload for `ForwardRepository.fetchForwardGraph`.
@freezed
abstract class ForwardGraph with _$ForwardGraph {
  const factory ForwardGraph({
    required String beaconId,
    required String authorId,
    @Default(<ForwardGraphEdge>[]) List<ForwardGraphEdge> edges,
    @Default(<String>{}) Set<String> committerIds,
  }) = _ForwardGraph;

  const ForwardGraph._();
}
