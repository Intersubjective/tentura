import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/enum.dart';
import 'package:tentura/domain/entity/identifiable.dart';

import '../../domain/entity/chat_message_entity.dart';

part 'chat_message_remote_model.freezed.dart';
part 'chat_message_remote_model.g.dart';

@freezed
abstract class ChatMessageRemoteModel
    with _$ChatMessageRemoteModel
    implements Identifiable {
  // ignore: invalid_annotation_target //
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory ChatMessageRemoteModel({
    required String clientId,
    required String serverId,
    required String senderId,
    required String receiverId,
    required String content,
    required DateTime createdAt,
    DateTime? deliveredAt,
  }) = _ChatMessageRemoteModel;

  factory ChatMessageRemoteModel.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageRemoteModelFromJson(json);

  const ChatMessageRemoteModel._();

  @override
  String get id => serverId;

  ChatMessageEntity get asEntity => ChatMessageEntity(
    clientId: clientId,
    serverId: serverId,
    senderId: senderId,
    receiverId: receiverId,
    createdAt: createdAt,
    deliveredAt: deliveredAt,
    content: content,
    status: deliveredAt == null
        ? ChatMessageStatus.sent
        : ChatMessageStatus.seen,
  );
}
