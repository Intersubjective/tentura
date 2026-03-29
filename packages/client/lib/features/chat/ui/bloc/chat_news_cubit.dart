import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/enum.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../../domain/entity/peer_presence_entity.dart';
import '../../domain/use_case/chat_case.dart';
import 'chat_news_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'chat_news_state.dart';

/// Global Cubit
@singleton
class ChatNewsCubit extends Cubit<ChatNewsState> {
  ChatNewsCubit(
    this._chatCase,
    this._friendsRemoteRepository,
  ) : super(
        ChatNewsState(
          myId: '',
          messages: {},
          lastUpdate: DateTime.timestamp(),
        ),
      ) {
    _authChanges = _chatCase.authChanges.listen(
      _onAuthChanges,
      cancelOnError: false,
      onError: (Object e) => emit(state.copyWith(status: StateHasError(e))),
    );
    _webSocketStateSubscription = _chatCase.webSocketState.listen(
      _onWebSocketStateChanges,
      cancelOnError: false,
      onError: (Object e) => emit(state.copyWith(status: StateHasError(e))),
    );
    _messagesUpdatesSubscription = _chatCase.updates.listen(
      _onMessagesUpdate,
      cancelOnError: false,
      onError: (Object e) => emit(state.copyWith(status: StateHasError(e))),
    );
    _presenceUpdatesSubscription = _chatCase.presenceUpdates.listen(
      _onPresenceUpdate,
      cancelOnError: false,
      onError: (Object e) => emit(state.copyWith(status: StateHasError(e))),
    );
  }

  final ChatCase _chatCase;

  final FriendsRemoteRepository _friendsRemoteRepository;

  late final StreamSubscription<String> _authChanges;

  late final StreamSubscription<WebSocketState> _webSocketStateSubscription;

  late final StreamSubscription<Iterable<ChatMessageEntity>>
  _messagesUpdatesSubscription;

  late final StreamSubscription<Iterable<PeerPresenceEntity>>
  _presenceUpdatesSubscription;

  //
  @override
  @disposeMethod
  Future<void> close() async {
    await _authChanges.cancel();
    await _messagesUpdatesSubscription.cancel();
    await _presenceUpdatesSubscription.cancel();
    await _webSocketStateSubscription.cancel();
    return super.close();
  }

  //
  //
  Future<void> _onWebSocketStateChanges(WebSocketState wsState) async {
    if (wsState == WebSocketState.connected) {
      if (state.myId.isNotEmpty) {
        _chatCase.subscribeToUpdates(
          fromMoment: await _chatCase.getCursor(userId: state.myId),
        );
        await _subscribePresenceForFriends();
      }
    }
  }

  Future<void> _subscribePresenceForFriends() async {
    try {
      final friends = await _friendsRemoteRepository.fetch();
      _chatCase.subscribePresencePeers(friends.map((e) => e.id).toList());
    } catch (_) {
      // Friends fetch is optional for presence; chat still works.
    }
  }

  //
  //
  Future<void> _onAuthChanges(String userId) async {
    _chatCase.logger.fine('[ChatNewsCubit] _onAuthChanges: $userId');
    emit(
      ChatNewsState(
        myId: userId,
        messages: {},
        lastUpdate: DateTime.timestamp(),
      ),
    );

    if (userId.isNotEmpty) {
      emit(state.copyWith(status: StateStatus.isLoading));
      try {
        final unseen = await _chatCase.getUnseenMessagesFor(userId: userId);
        final messagesMap = _cloneMessagesMap(state.messages);
        final lastByPeer = Map<String, ChatMessageEntity>.from(
          state.lastMessageByPeerId,
        );
        for (final m in unseen) {
          _applyLastMessageForPeer(lastByPeer, m);
          _applyMessageUpdate(messagesMap, m);
        }
        emit(
          state.copyWith(
            messages: messagesMap,
            lastMessageByPeerId: lastByPeer,
            status: StateStatus.isSuccess,
          ),
        );
        unawaited(_subscribePresenceForFriends());
      } catch (e) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  static Map<String, List<ChatMessageEntity>> _cloneMessagesMap(
    Map<String, List<ChatMessageEntity>> source,
  ) =>
      source.map(
        (k, v) => MapEntry(k, List<ChatMessageEntity>.from(v)),
      );

  void _onPresenceUpdate(Iterable<PeerPresenceEntity> batch) {
    final next = Map<String, PeerPresenceEntity>.from(state.peerPresence);
    for (final p in batch) {
      next[p.userId] = p;
    }
    emit(
      state.copyWith(
        peerPresence: next,
        lastUpdate: DateTime.timestamp(),
      ),
    );
  }

  //
  //
  Future<void> _onMessagesUpdate(Iterable<ChatMessageEntity> messages) async {
    if (messages.isEmpty) {
      return;
    }
    final messagesMap = _cloneMessagesMap(state.messages);
    final lastByPeer = Map<String, ChatMessageEntity>.from(
      state.lastMessageByPeerId,
    );
    for (final m in messages) {
      _applyLastMessageForPeer(lastByPeer, m);
      _applyMessageUpdate(messagesMap, m);
    }
    emit(
      state.copyWith(
        messages: messagesMap,
        lastMessageByPeerId: lastByPeer,
        lastUpdate: DateTime.timestamp(),
      ),
    );
    await _chatCase.saveMessages(messages: messages);
  }

  void _applyLastMessageForPeer(
    Map<String, ChatMessageEntity> lastByPeer,
    ChatMessageEntity message,
  ) {
    if (state.myId.isEmpty) {
      return;
    }
    final peerId = message.senderId == state.myId
        ? message.receiverId
        : message.senderId;
    final existing = lastByPeer[peerId];
    if (existing == null || message.createdAt.isAfter(existing.createdAt)) {
      lastByPeer[peerId] = message;
    }
  }

  void _applyMessageUpdate(
    Map<String, List<ChatMessageEntity>> messagesMap,
    ChatMessageEntity message,
  ) {
    if (message.senderId == state.myId) {
      return;
    }

    switch (message.status) {
      case ChatMessageStatus.seen:
        final list = messagesMap[message.senderId];
        if (list != null) {
          list.removeWhere((e) => e.serverId == message.serverId);
        }

      case ChatMessageStatus.sent:
        final list = messagesMap[message.senderId];
        if (list != null) {
          final index = list.indexWhere(
            (e) => e.serverId == message.serverId,
          );
          if (index < 0) {
            list.add(message);
          } else {
            list[index] = message;
          }
        } else {
          messagesMap[message.senderId] = [message];
        }

      // ignore: no_default_cases //
      default:
    }
  }
}
