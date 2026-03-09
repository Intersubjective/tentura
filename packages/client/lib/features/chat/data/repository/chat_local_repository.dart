import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/enum.dart';
import 'package:tentura/data/database/database.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../model/chat_message_local_model.dart';

@singleton
class ChatLocalRepository {
  ChatLocalRepository(this._database);

  final Database _database;

  //
  //
  Future<void> saveMessages({
    required Iterable<ChatMessageEntity> messages,
  }) => _database.managers.p2pMessages.bulkCreate(
    (p2pMessageCompanion) => [
      for (final message in messages)
        p2pMessageCompanion(
          clientId: message.clientId,
          serverId: message.serverId,
          senderId: message.senderId,
          receiverId: message.receiverId,
          content: message.content,
          createdAt: message.createdAt,
          deliveredAt: Value(message.deliveredAt),
          status: message.status,
        ),
    ],
    mode: InsertMode.replace,
  );

  ///
  /// Get all messages for pair from local DB
  ///
  Future<Iterable<ChatMessageEntity>> getChatMessagesForPair({
    required String senderId,
    required String receiverId,
  }) => _database.managers.p2pMessages
      .filter(
        (f) =>
            (f.senderId(senderId) & f.receiverId(receiverId)) |
            (f.receiverId(receiverId) & f.senderId(senderId)),
      )
      .orderBy((o) => o.createdAt.asc())
      .get()
      .then((v) => v.map((e) => (e as ChatMessageLocalModel).toEntity()));

  ///
  /// Get all unseen messages for user from local DB
  ///
  Future<Iterable<ChatMessageEntity>> getAllNewMessagesFor({
    required String userId,
  }) => _database.managers.p2pMessages
      .filter((f) => f.senderId(userId) & f.status(ChatMessageStatus.sent))
      .get()
      .then((v) => v.map((e) => (e as ChatMessageLocalModel).toEntity()));

  ///
  /// Get the most recent message timestamp for a user.
  ///
  Future<DateTime> getMostRecentMessageTimestamp({
    required String userId,
  }) => _database
      .customSelect(
        '''
SELECT * FROM (
  SELECT coalesce(delivered_at, created_at) as ts FROM p2p_messages
    WHERE sender_id = ?1
    ORDER BY ts DESC
    LIMIT 1)
UNION
SELECT * FROM (
  SELECT coalesce(delivered_at, created_at) as ts FROM p2p_messages
    WHERE receiver_id = ?1
    ORDER BY ts DESC
    LIMIT 1)
ORDER BY ts DESC
LIMIT 1;
''',
        readsFrom: {_database.p2pMessages},
        variables: [
          Variable.withString(userId),
        ],
      )
      .getSingleOrNull()
      .then((r) => r == null ? kZeroAge : r.read('ts'));
}
