import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/utils/id.dart';

import 'user_entity.dart';

part 'forward_edge_entity.freezed.dart';

@freezed
abstract class ForwardEdgeEntity with _$ForwardEdgeEntity {
  static String get newId => generateId('F');

  const factory ForwardEdgeEntity({
    required String id,
    required String beaconId,
    required String senderId,
    required String recipientId,
    required DateTime createdAt,
    @Default('') String note,
    String? context,
    String? parentEdgeId,
    String? batchId,
    @Default(false) bool recipientRejected,
    @Default('') String recipientRejectionMessage,
    UserEntity? sender,
    UserEntity? recipient,
  }) = _ForwardEdgeEntity;

  const ForwardEdgeEntity._();
}
