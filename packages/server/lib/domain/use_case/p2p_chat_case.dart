import 'dart:async';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/p2p_message_repository_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';

import '../entity/p2p_message_entity.dart';
import '_use_case_base.dart';

@Injectable(order: 2)
final class P2pChatCase extends UseCaseBase {
  P2pChatCase(
    this._fcmTokenRepository,
    this._fcmBatchQueuePort,
    this._p2pMessageRepository,
    this._userPresenceRepository,
    this._userRepository, {
    required super.env,
    required super.logger,
  });

  final FcmTokenRepositoryPort _fcmTokenRepository;

  final FcmBatchQueuePort _fcmBatchQueuePort;

  final P2pMessageRepositoryPort _p2pMessageRepository;

  final UserPresenceRepositoryPort _userPresenceRepository;

  final UserRepositoryPort _userRepository;

  /// Creates a message, emits Postgres NOTIFY, and enqueues FCM if needed.
  /// Returns the created entity (with server-assigned serverId and createdAt).
  Future<P2pMessageEntity> create({
    required String receiverId,
    required String senderId,
    required String clientMessageId,
    required String content,
  }) async {
    final entity = await _p2pMessageRepository.create(
      receiverId: receiverId,
      senderId: senderId,
      clientId: UuidValue.fromString(clientMessageId),
      content: content,
    );
    unawaited(
      _enqueueFcmIfNeeded(
        receiverId: receiverId,
        senderId: senderId,
        content: content,
      ),
    );
    return entity;
  }

  Future<void> markAsDelivered({
    required String clientId,
    required String serverId,
    required String receiverId,
  }) => _p2pMessageRepository.markAsDelivered(
    receiverId: receiverId,
    clientId: clientId,
    serverId: serverId,
  );

  /// Fetches P2P messages for a specific user from a given point in time.
  /// Used for catch-up sync after (re)connect.
  Future<Iterable<P2pMessageEntity>> fetchByUserId({
    required DateTime from,
    required String userId,
    required int batchSize,
  }) => _p2pMessageRepository.fetchByUserId(
    id: userId,
    from: from,
    limit: batchSize,
  );

  /// Fetches chat history for a pair of users, paginated by cursor.
  Future<Iterable<P2pMessageEntity>> fetchHistory({
    required String userId,
    required String peerId,
    required DateTime before,
    int limit = 20,
  }) => _p2pMessageRepository.fetchHistoryForPair(
    userId: userId,
    peerId: peerId,
    before: before,
    limit: limit,
  );

  /// Checks presence and enqueues to the FCM batch queue if the user
  /// should be notified (offline or not recently notified).
  Future<void> _enqueueFcmIfNeeded({
    required String receiverId,
    required String senderId,
    required String content,
  }) async {
    final userStatus = await _userPresenceRepository.get(receiverId);
    if (userStatus == null || !userStatus.shouldNotify) {
      return;
    }

    final fcmTokens = await _fcmTokenRepository.getTokensByUserId(
      receiverId,
    );
    if (fcmTokens.isEmpty) {
      return;
    }

    final senderProfile = await _userRepository.getById(senderId);

    _fcmBatchQueuePort.enqueue(
      receiverId: receiverId,
      fcmTokens: fcmTokens.map((e) => e.token).toSet(),
      message: FcmNotificationEntity(
        actionUrl: '/#$kPathAppLinkChat/$senderId?receiver_id=$receiverId',
        imageUrl: senderProfile.imageUrl,
        title: senderProfile.title,
        body: content,
      ),
    );

    await _userPresenceRepository.update(
      receiverId,
      lastNotifiedAt: DateTime.timestamp(),
    );
  }
}
