import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/p2p_message_entity.dart';

import '../database/tentura_db.dart';
import '../service/pg_notification_service.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class P2pMessageRepository {
  P2pMessageRepository(this._database, this._pgNotificationService);

  final TenturaDb _database;

  final PgNotificationService _pgNotificationService;

  Future<P2pMessageEntity> create({
    required String content,
    required String senderId,
    required String receiverId,
    required UuidValue clientId,
  }) async {
    final serverId = const Uuid().v4obj();
    final createdAt = DateTime.timestamp();

    await _database.managers.p2pMessages.create(
      (o) => o(
        clientId: clientId,
        serverId: Value(serverId),
        senderId: senderId,
        receiverId: receiverId,
        content: content,
        createdAt: Value(PgDateTime(createdAt)),
      ),
    );

    final entity = P2pMessageEntity(
      clientId: clientId.toString(),
      serverId: serverId.toString(),
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      createdAt: createdAt,
    );

    await _pgNotificationService.notify(
      'p2p_chat',
      jsonEncode({'event': 'new_message', ...entity.toJson()}),
    );

    return entity;
  }

  Future<void> markAsDelivered({
    required String clientId,
    required String serverId,
    required String receiverId,
  }) async {
    final clientUuid = UuidValue.fromString(clientId);
    final serverUuid = UuidValue.fromString(serverId);

    final rows = await _database.managers.p2pMessages
        .filter(
          (e) =>
              e.clientId(clientUuid) &
              e.serverId(serverUuid) &
              e.receiverId.id(receiverId),
        )
        .get();

    if (rows.isEmpty) return;

    final deliveredAt = DateTime.timestamp();
    await _database.managers.p2pMessages
        .filter(
          (e) =>
              e.clientId(clientUuid) &
              e.serverId(serverUuid) &
              e.receiverId.id(receiverId),
        )
        .update(
          (o) => o(deliveredAt: Value(PgDateTime(deliveredAt))),
        );

    final row = rows.first;
    final entity = P2pMessageEntity(
      clientId: clientId,
      serverId: serverId,
      senderId: row.senderId,
      receiverId: receiverId,
      content: row.content,
      createdAt: row.createdAt.dateTime,
      deliveredAt: deliveredAt,
    );
    await _pgNotificationService.notify(
      'p2p_chat',
      jsonEncode({'event': 'delivered', ...entity.toJson()}),
    );
  }

  Future<Iterable<P2pMessageEntity>> fetchByUserId({
    required DateTime from,
    required String id,
    required int limit,
  }) async {
    final pgFrom = Variable<PgDateTime>(
      PgDateTime(from),
      PgTypes.timestampWithTimezone,
    );
    final userId = Variable<String>(id);

    final messages = await _database
        .customSelect(
          '''
  (SELECT * FROM p2p_message
    WHERE receiver_id = ? AND created_at > ?)
  UNION
  (SELECT * FROM p2p_message
    WHERE sender_id = ? AND created_at > ?)
  UNION
  (SELECT * FROM p2p_message
    WHERE receiver_id = ? AND delivered_at > ?)
  UNION
  (SELECT * FROM p2p_message
    WHERE sender_id = ? AND delivered_at > ?)
  ORDER BY created_at ASC
  LIMIT ?
  ''',
          variables: [
            userId, pgFrom,
            userId, pgFrom,
            userId, pgFrom,
            userId, pgFrom,
            Variable<int>(limit),
          ],
          readsFrom: {_database.p2pMessages},
        )
        .get();

    return messages.map(
      (row) => P2pMessageEntity(
        clientId: row.data['client_id']! as String,
        serverId: row.data['server_id']! as String,
        content: row.data['content']! as String,
        senderId: row.data['sender_id']! as String,
        receiverId: row.data['receiver_id']! as String,
        createdAt: row.data['created_at']! as DateTime,
        deliveredAt: row.data['delivered_at'] as DateTime?,
      ),
    );
  }

  Future<Iterable<P2pMessageEntity>> fetchHistoryForPair({
    required String userId,
    required String peerId,
    required DateTime before,
    required int limit,
  }) async {
    final pgBefore = Variable<PgDateTime>(
      PgDateTime(before),
      PgTypes.timestampWithTimezone,
    );

    final messages = await _database
        .customSelect(
          '''
  SELECT * FROM p2p_message
  WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
    AND created_at < ?
  ORDER BY created_at DESC
  LIMIT ?
  ''',
          variables: [
            Variable<String>(userId),
            Variable<String>(peerId),
            Variable<String>(peerId),
            Variable<String>(userId),
            pgBefore,
            Variable<int>(limit),
          ],
          readsFrom: {_database.p2pMessages},
        )
        .get();

    return messages.map(
      (row) => P2pMessageEntity(
        clientId: row.data['client_id']! as String,
        serverId: row.data['server_id']! as String,
        content: row.data['content']! as String,
        senderId: row.data['sender_id']! as String,
        receiverId: row.data['receiver_id']! as String,
        createdAt: row.data['created_at']! as DateTime,
        deliveredAt: row.data['delivered_at'] as DateTime?,
      ),
    );
  }
}
