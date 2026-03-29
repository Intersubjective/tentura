import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/enum.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../../domain/entity/peer_presence_entity.dart';
import '../../domain/use_case/chat_case.dart';
import 'chat_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  ChatCubit({
    required String friendId,
    ChatCase? chatCase,
  }) : _chatCase = chatCase ?? GetIt.I<ChatCase>(),
       super(
         ChatState(
           lastUpdate: kZeroAge,
           friend: Profile(id: friendId),
         ),
       ) {
    unawaited(
      _init().then(
        _fetchAll,
        onError: (Object e) => emit(state.copyWith(status: StateHasError(e))),
      ),
    );
  }

  final ChatCase _chatCase;

  late final StreamSubscription<ChatMessageEntity> _updatesSubscription;
  late final StreamSubscription<MessageAck> _ackSubscription;
  late final StreamSubscription<HistoryResponse> _historySubscription;
  late final StreamSubscription<PeerPresenceEntity> _presenceSubscription;
  late final StreamSubscription<TypingEvent> _typingSubscription;

  Timer? _typingHideTimer;

  Timer? _typingSendDebounce;

  bool _isLoadingHistory = false;
  bool _hasMoreHistory = true;

  bool get hasMoreHistory => _hasMoreHistory;

  @override
  Future<void> close() async {
    await _updatesSubscription.cancel();
    await _ackSubscription.cancel();
    await _historySubscription.cancel();
    await _presenceSubscription.cancel();
    await _typingSubscription.cancel();
    _typingHideTimer?.cancel();
    _typingSendDebounce?.cancel();
    return super.close();
  }

  /// Debounced outgoing typing indicator to the peer.
  void onComposerTextChanged(String text) {
    if (state.friend.id.isEmpty || state.me.id.isEmpty) {
      return;
    }
    if (text.trim().isEmpty) {
      return;
    }
    _typingSendDebounce?.cancel();
    _typingSendDebounce = Timer(const Duration(milliseconds: 500), () {
      if (isClosed) {
        return;
      }
      _chatCase.sendTyping(receiverId: state.friend.id);
    });
  }

  Future<void> onSendPressed(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;

    final clientId = const Uuid().v4();
    final optimistic = ChatMessageEntity(
      clientId: clientId,
      serverId: '',
      senderId: state.me.id,
      receiverId: state.friend.id,
      content: content,
      status: ChatMessageStatus.sending,
      createdAt: DateTime.timestamp(),
    );
    state.messages.insert(0, optimistic);
    emit(state.copyWith(lastUpdate: DateTime.timestamp()));

    try {
      await _chatCase.sendMessage(
        receiverId: state.friend.id,
        clientId: clientId,
        content: content,
      );
    } catch (e) {
      final idx = state.messages.indexWhere((m) => m.clientId == clientId);
      if (idx >= 0) {
        state.messages[idx] = state.messages[idx].copyWith(
          status: ChatMessageStatus.error,
        );
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  /// Resend a failed outgoing message (same [clientId] and content).
  Future<void> onRetrySend(String clientId) async {
    final idx = state.messages.indexWhere((m) => m.clientId == clientId);
    if (idx < 0) return;
    final m = state.messages[idx];
    if (m.status != ChatMessageStatus.error) return;

    state.messages[idx] = m.copyWith(status: ChatMessageStatus.sending);
    emit(state.copyWith(lastUpdate: DateTime.timestamp()));

    try {
      await _chatCase.sendMessage(
        receiverId: state.friend.id,
        clientId: clientId,
        content: m.content,
      );
    } catch (e) {
      final i = state.messages.indexWhere((x) => x.clientId == clientId);
      if (i >= 0) {
        state.messages[i] = state.messages[i].copyWith(
          status: ChatMessageStatus.error,
        );
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  Future<void> onMessageShown(ChatMessageEntity message) async {
    try {
      await _chatCase.setMessageSeen(message: message);
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  /// Load older messages when user scrolls to the top.
  void loadMoreHistory() {
    if (_isLoadingHistory || !_hasMoreHistory || state.messages.isEmpty) return;
    _isLoadingHistory = true;

    final oldest = state.messages.last;
    _chatCase.fetchHistory(
      peerId: state.friend.id,
      before: oldest.createdAt,
    );
  }

  // TBD
  Future<void> onChatClear() async {}

  Future<void> deleteMessageForMe(ChatMessageEntity message) async {
    try {
      await _chatCase.deleteMessageLocally(
        clientId: message.clientId,
        serverId: message.serverId,
      );
      state.messages.removeWhere(
        (m) =>
            m.clientId == message.clientId && m.serverId == message.serverId,
      );
      emit(state.copyWith(lastUpdate: DateTime.timestamp()));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  void _onPresenceEvent(PeerPresenceEntity p) {
    if (p.userId != state.friend.id) {
      return;
    }
    emit(
      state.copyWith(
        friendPresence: p,
        lastUpdate: DateTime.timestamp(),
      ),
    );
  }

  void _onTypingEvent(TypingEvent e) {
    if (e.senderId != state.friend.id || e.receiverId != state.me.id) {
      return;
    }
    _typingHideTimer?.cancel();
    emit(
      state.copyWith(
        peerIsTyping: true,
        lastUpdate: DateTime.timestamp(),
      ),
    );
    _typingHideTimer = Timer(const Duration(seconds: 3), () {
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          peerIsTyping: false,
          lastUpdate: DateTime.timestamp(),
        ),
      );
    });
  }

  Future<String> _init() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final myId = await _chatCase.getCurrentAccountId();

      _updatesSubscription = _chatCase.updates
          .expand((e) => e)
          .where(
            (m) =>
                (m.receiverId == state.friend.id && m.senderId == myId) ||
                (m.receiverId == myId && m.senderId == state.friend.id),
          )
          .listen(
            _onMessage,
            cancelOnError: false,
            onError: (Object e) =>
                emit(state.copyWith(status: StateHasError(e))),
          );

      _ackSubscription = _chatCase.messageAcks.listen(
        _onMessageAck,
        cancelOnError: false,
        onError: (Object e) =>
            emit(state.copyWith(status: StateHasError(e))),
      );

      _historySubscription = _chatCase.historyResponses.listen(
        _onHistoryResponse,
        cancelOnError: false,
        onError: (Object e) {
          _isLoadingHistory = false;
          emit(state.copyWith(status: StateHasError(e)));
        },
      );

      _presenceSubscription = _chatCase.presenceUpdates
          .expand((e) => e)
          .listen(
            _onPresenceEvent,
            cancelOnError: false,
            onError: (Object e) =>
                emit(state.copyWith(status: StateHasError(e))),
          );

      _typingSubscription = _chatCase.typingUpdates.listen(
        _onTypingEvent,
        cancelOnError: false,
        onError: (Object e) =>
            emit(state.copyWith(status: StateHasError(e))),
      );

      emit(
        ChatState(
          me: Profile(id: myId),
          friend: await _chatCase.fetchProfileById(state.friend.id),
          lastUpdate: DateTime.timestamp(),
        ),
      );
      _chatCase.subscribePresencePeers([state.friend.id]);
      return myId;
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
    return state.me.id;
  }

  Future<void> _fetchAll(String myId) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final result = await _chatCase.getChatMessagesForPair(
        receiverId: myId,
        senderId: state.friend.id,
      );
      emit(
        state.copyWith(
          messages:
              state.messages.isEmpty
                    ? result.toList()
                    : [
                        ...result,
                        ...state.messages,
                      ]
                ..sort(_sortByDate),
          status: StateStatus.isSuccess,
          lastUpdate: DateTime.timestamp(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  void _onMessage(ChatMessageEntity message) {
    final index = state.messages.indexWhere(
      (e) =>
          e.serverId == message.serverId ||
          (e.serverId.isEmpty && e.clientId == message.clientId),
    );
    if (index < 0) {
      state.messages.insert(0, message);
    } else {
      state.messages[index] = message;
    }
    emit(
      state.copyWith(
        status: StateStatus.isSuccess,
        lastUpdate: DateTime.timestamp(),
      ),
    );
  }

  void _onMessageAck(MessageAck ack) {
    final index = state.messages.indexWhere(
      (e) => e.clientId == ack.clientId,
    );
    if (index >= 0) {
      state.messages[index] = state.messages[index].copyWith(
        serverId: ack.serverId,
        createdAt: ack.createdAt,
        status: ChatMessageStatus.sent,
      );
      emit(state.copyWith(lastUpdate: DateTime.timestamp()));
    }
  }

  void _onHistoryResponse(HistoryResponse response) {
    _isLoadingHistory = false;
    _hasMoreHistory = response.hasMore;

    final older = response.messages.toList();
    if (older.isEmpty) return;

    final existingIds = state.messages.map((m) => m.serverId).toSet();
    final newMessages = older.where((m) => !existingIds.contains(m.serverId));
    state.messages.addAll(newMessages);
    state.messages.sort(_sortByDate);

    emit(
      state.copyWith(
        status: StateStatus.isSuccess,
        lastUpdate: DateTime.timestamp(),
      ),
    );

    unawaited(_chatCase.saveMessages(messages: older));
  }

  int _sortByDate(ChatMessageEntity a, ChatMessageEntity b) =>
      b.createdAt.compareTo(a.createdAt);
}
