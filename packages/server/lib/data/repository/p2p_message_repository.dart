import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/p2p_message_entity.dart';

import '../database/tentura_db.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class P2pMessageRepository {
  const P2pMessageRepository(this._database);

  final TenturaDb _database;

  //
  //
  Future<void> create({
    required String content,
    required String senderId,
    required String receiverId,
    required UuidValue clientId,
  }) => _database.managers.p2pMessages.create(
    (o) => o(
      clientId: clientId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
    ),
  );

  ///
  /// Return number of affected rows
  ///
  Future<int> markAsDelivered({
    required String clientId,
    required String serverId,
    required String receiverId,
  }) => _database.managers.p2pMessages
      .filter(
        (e) =>
            e.clientId(UuidValue.fromString(clientId)) &
            e.serverId(UuidValue.fromString(serverId)) &
            e.receiverId.id(receiverId),
      )
      .update(
        (o) => o(
          deliveredAt: Value(PgDateTime(DateTime.timestamp())),
        ),
      );

  ///
  /// Fetches P2P messages for a specific user from a given point in time.
  ///
  Future<Iterable<P2pMessageEntity>> fetchByUserId({
    required DateTime from,
    required String id,
    required int limit,
  }) async {
    final fromString = from.toIso8601String();
    final messages = await _database
        .customSelect(
          '''
  (SELECT * FROM p2p_message
    WHERE receiver_id = '$id' AND created_at > '$fromString')
  UNION
  (SELECT * FROM p2p_message
    WHERE sender_id = '$id' AND created_at > '$fromString')
  UNION
  (SELECT * FROM p2p_message
    WHERE receiver_id = '$id' AND delivered_at > '$fromString')
  UNION
  (SELECT * FROM p2p_message
    WHERE sender_id = '$id' AND delivered_at > '$fromString')
  ORDER BY created_at ASC
  LIMIT $limit
  ''',
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
