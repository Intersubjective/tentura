import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/data/service/remote_api_client/enum.dart';

import 'package:tentura/features/auth/data/repository/auth_local_repository.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';

import '../../data/repository/chat_local_repository.dart';
import '../../data/repository/chat_remote_repository.dart';
import '../entity/chat_message_entity.dart';
import '../entity/peer_presence_entity.dart';

export 'package:tentura/data/service/remote_api_client/enum.dart';

typedef MessageAck = ({String clientId, String serverId, DateTime createdAt});
typedef HistoryResponse = ({Iterable<ChatMessageEntity> messages, bool hasMore});
typedef TypingEvent = ({String senderId, String receiverId});

@singleton
final class ChatCase extends UseCaseBase {
  ChatCase(
    this._authLocalRepository,
    this._chatLocalRepository,
    this._chatRemoteRepository,
    this._profileRepository, {
    required super.env,
    required super.logger,
  });

  final AuthLocalRepository _authLocalRepository;

  final ChatLocalRepository _chatLocalRepository;

  final ChatRemoteRepository _chatRemoteRepository;

  final ProfileRepository _profileRepository;

  Stream<WebSocketState> get webSocketState =>
      _chatRemoteRepository.webSocketState;

  Stream<String> get authChanges =>
      _authLocalRepository.currentAccountChanges();

  Stream<Iterable<ChatMessageEntity>> get updates =>
      _chatRemoteRepository.updates;

  Stream<MessageAck> get messageAcks => _chatRemoteRepository.messageAcks;

  Stream<HistoryResponse> get historyResponses =>
      _chatRemoteRepository.historyResponses;

  Stream<Iterable<PeerPresenceEntity>> get presenceUpdates =>
      _chatRemoteRepository.presenceUpdates;

  Stream<TypingEvent> get typingUpdates =>
      _chatRemoteRepository.typingUpdates;

  Future<String> getCurrentAccountId() =>
      _authLocalRepository.getCurrentAccountId();

  Future<Profile> fetchProfileById(String id) =>
      _profileRepository.fetchById(id);

  void subscribeToUpdates({
    required DateTime fromMoment,
    int batchSize = 10,
  }) {
    logger.fine('[ChatCase] Subscribe to updates.');
    _chatRemoteRepository.subscribeToUpdates(
      fromMoment: fromMoment,
      batchSize: batchSize,
    );
  }

  void subscribePresencePeers(List<String> peerIds) {
    if (peerIds.isEmpty) {
      return;
    }
    logger.fine('[ChatCase] Subscribe presence for ${peerIds.length} peers.');
    _chatRemoteRepository.subscribePresencePeers(peerIds);
  }

  void sendTyping({required String receiverId}) =>
      _chatRemoteRepository.sendTyping(receiverId: receiverId);

  Future<void> sendMessage({
    required String receiverId,
    required String clientId,
    required String content,
  }) => _chatRemoteRepository.sendMessage(
    receiverId: receiverId,
    clientId: clientId,
    content: content,
  );

  Future<void> setMessageSeen({
    required ChatMessageEntity message,
  }) => _chatRemoteRepository.setMessageSeen(
    message: message,
  );

  void fetchHistory({
    required String peerId,
    required DateTime before,
    int limit = 20,
  }) => _chatRemoteRepository.fetchHistory(
    peerId: peerId,
    before: before,
    limit: limit,
  );

  Future<Iterable<ChatMessageEntity>> getChatMessagesForPair({
    required String senderId,
    required String receiverId,
  }) => _chatLocalRepository.getChatMessagesForPair(
    senderId: senderId,
    receiverId: receiverId,
  );

  Future<Iterable<ChatMessageEntity>> getUnseenMessagesFor({
    required String userId,
  }) => _chatLocalRepository.getAllNewMessagesFor(
    userId: userId,
  );

  Future<DateTime> getCursor({
    required String userId,
  }) => _chatLocalRepository.getMostRecentMessageTimestamp(
    userId: userId,
  );

  Future<void> saveMessages({
    required Iterable<ChatMessageEntity> messages,
  }) => _chatLocalRepository.saveMessages(
    messages: messages,
  );

  Future<void> deleteMessageLocally({
    required String clientId,
    required String serverId,
  }) => _chatLocalRepository.deleteMessageForMe(
    clientId: clientId,
    serverId: serverId,
  );
}
