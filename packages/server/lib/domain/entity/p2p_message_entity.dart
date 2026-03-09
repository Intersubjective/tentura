import 'package:freezed_annotation/freezed_annotation.dart';

part 'p2p_message_entity.freezed.dart';

@freezed
abstract class P2pMessageEntity with _$P2pMessageEntity {
  const factory P2pMessageEntity({
    required String clientId,
    required String content,
    required String senderId,
    required String receiverId,
    required DateTime createdAt,
    String? serverId,
    DateTime? deliveredAt,
  }) = _P2pMessageEntity;

  const P2pMessageEntity._();

  bool get isDelivered => deliveredAt != null;

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'server_id': serverId,
    'sender_id': senderId,
    'receiver_id': receiverId,
    'created_at': createdAt.toIso8601String(),
    'delivered_at': deliveredAt?.toIso8601String(),
    'content': content,
  };
}
