import 'package:drift/drift.dart';

import 'package:tentura/domain/enum.dart';

@TableIndex(name: 'p2p_messages_sender', columns: {#senderId})
@TableIndex(name: 'p2p_messages_receiver', columns: {#receiverId})
@TableIndex(name: 'p2p_messages_created_at', columns: {#createdAt})
@TableIndex(name: 'p2p_messages_delivered_at', columns: {#deliveredAt})
class P2pMessages extends Table {
  TextColumn get clientId => text()();

  TextColumn get serverId => text()();

  TextColumn get senderId => text()();

  TextColumn get receiverId => text()();

  TextColumn get content => text()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get deliveredAt => dateTime().nullable()();

  IntColumn get status => intEnum<ChatMessageStatus>()();

  @override
  bool get withoutRowId => true;

  @override
  Set<Column> get primaryKey => {clientId, serverId};
}
