import 'package:freezed_annotation/freezed_annotation.dart';

part 'forward_edge_created.freezed.dart';

@freezed
abstract class ForwardEdgeCreated with _$ForwardEdgeCreated {
  const factory ForwardEdgeCreated({
    required String edgeId,
    required String recipientId,
  }) = _ForwardEdgeCreated;
}
