import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/enum.dart';
import 'package:tentura/data/database/database.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../../domain/port/chat_local_repository_port.dart';
import '../model/chat_message_local_model.dart';

@Singleton(
  as: ChatLocalRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class ChatLocalRepository implements ChatLocalRepositoryPort {
  ChatLocalRepository(this._database);

  final Database _database;

  //
  //
  @override
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
  @override
  Future<Iterable<ChatMessageEntity>> getChatMessagesForPair({
    required String senderId,
    required String receiverId,
  }) => _database.managers.p2pMessages
      .filter(
        (f) =>
            (f.senderId(senderId) & f.receiverId(receiverId)) |
            (f.senderId(receiverId) & f.receiverId(senderId)),
      )
      .orderBy((o) => o.createdAt.asc())
      .get()
      .then((v) => v.map((e) => (e as ChatMessageLocalModel).toEntity()));

  ///
  /// Incoming messages not yet marked delivered (seen) by [userId] as receiver.
  ///
  @override
  Future<Iterable<ChatMessageEntity>> getAllNewMessagesFor({
    required String userId,
  }) => _database.managers.p2pMessages
      .filter(
        (f) =>
            f.receiverId(userId) & f.status(ChatMessageStatus.sent),
      )
      .get()
      .then((v) => v.map((e) => (e as ChatMessageLocalModel).toEntity()));

  ///
  /// Get the most recent message timestamp for a user.
  ///
  @override
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

  /// Remove a row from local storage only (does not affect server history).
  @override
  Future<void> deleteMessageForMe({
    required String clientId,
    required String serverId,
  }) =>
      _database.managers.p2pMessages
          .filter((f) => f.clientId(clientId) & f.serverId(serverId))
          .delete();
}
