import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/profile.dart';

part 'forward_edge.freezed.dart';

@freezed
abstract class ForwardEdge with _$ForwardEdge {
  const factory ForwardEdge({
    required String id,
    required String beaconId,
    required DateTime createdAt,
    @Default('') String note,
    @Default('') String context,
    @Default(Profile()) Profile sender,
    @Default(Profile()) Profile recipient,
    String? parentEdgeId,
    String? batchId,
    @Default(false) bool recipientRejected,
    @Default('') String recipientRejectionMessage,
    DateTime? recipientReadAt,

    /// Set when the sender cancelled the forward (or a block cancelled it).
    /// A cancelled forward is history, not a deleted row: the sender's trail
    /// keeps it, marked cancelled (#396).
    DateTime? cancelledAt,
  }) = _ForwardEdge;

  const ForwardEdge._();

  bool get isCancelled => cancelledAt != null;
}
