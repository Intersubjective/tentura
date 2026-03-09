import 'dart:async';
import 'package:uuid/uuid_value.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/data/repository/fcm_remote_repository.dart';
import 'package:tentura_server/data/repository/fcm_token_repository.dart';
import 'package:tentura_server/data/repository/p2p_message_repository.dart';
import 'package:tentura_server/data/repository/user_presence_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';

import '../entity/p2p_message_entity.dart';
import '_use_case_base.dart';

@Injectable(order: 2)
final class P2pChatCase extends UseCaseBase {
  P2pChatCase(
    this._fcmTokenRepository,
    this._fcmRemoteRepository,
    this._p2pMessageRepository,
    this._userPresenceRepository,
    this._userRepository, {
    required super.env,
    required super.logger,
  });

  final FcmTokenRepository _fcmTokenRepository;

  final FcmRemoteRepository _fcmRemoteRepository;

  final P2pMessageRepository _p2pMessageRepository;

  final UserPresenceRepository _userPresenceRepository;

  final UserRepository _userRepository;

  //
  //
  Future<void> create({
    required String receiverId,
    required String senderId,
    required UuidValue clientMessageId,
    required String content,
  }) async {
    await _p2pMessageRepository.create(
      receiverId: receiverId,
      senderId: senderId,
      clientId: clientMessageId,
      content: content,
    );
    unawaited(
      _notifyUser(
        receiverId: receiverId,
        senderId: senderId,
        content: content,
        clientMessageId: clientMessageId,
      ),
    );
  }

  //
  //
  Future<void> markAsDelivered({
    required String clientId,
    required String serverId,
    required String receiverId,
  }) => _p2pMessageRepository.markAsDelivered(
    receiverId: receiverId,
    clientId: clientId,
    serverId: serverId,
  );

  ///
  /// Fetches P2P messages for a specific user from a given point in time.
  ///
  /// This method retrieves messages where the user with the given [userId] is
  /// either the sender or the receiver. It includes messages that were either
  /// created or delivered after the specified [from] timestamp.
  ///
  /// This is useful for syncing a client's message history, as it fetches
  /// both new messages sent/received by the user and updates to the delivery
  /// status of older messages.
  ///
  /// The results are ordered by their creation timestamp in ascending order
  /// and are limited to the [batchSize] specified.
  ///
  /// - [userId]: The ID of the user whose messages are to be fetched.
  ///   Be sure it is sanitized for prevent SQL injection!
  /// - [from]: The timestamp from which to start fetching messages. Only
  ///   messages created or delivered after this time will be returned.
  /// - [batchSize]: The maximum number of messages to return.
  ///
  Future<Iterable<P2pMessageEntity>> fetchByUserId({
    required DateTime from,
    required String userId,
    required int batchSize,
  }) => _p2pMessageRepository.fetchByUserId(
    id: userId,
    from: from,
    limit: batchSize,
  );

  //
  // TBD:
  //  make a dedicated Isolate for processing FCM jobs
  //  or use existing TaskWorker?
  //
  Future<void> _notifyUser({
    required String receiverId,
    required String senderId,
    required String content,
    required UuidValue clientMessageId,
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
    final results = await _fcmRemoteRepository.sendChatNotification(
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

    for (final e in results.whereType<FcmTokenNotFoundException>()) {
      await _fcmTokenRepository.deleteToken(e.token);
      logger.info('[P2pChatCase] Delete unregistered token: [${e.token}]');
    }
  }
}
