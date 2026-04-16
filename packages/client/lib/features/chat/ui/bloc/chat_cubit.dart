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
    emit(
      state.copyWith(
        messages: [optimistic, ...List<ChatMessageEntity>.from(state.messages)],
        lastUpdate: DateTime.timestamp(),
      ),
    );

    try {
      await _chatCase.sendMessage(
        receiverId: state.friend.id,
        clientId: clientId,
        content: content,
      );
    } catch (e) {
      final msgs = List<ChatMessageEntity>.from(state.messages);
      final idx = msgs.indexWhere((m) => m.clientId == clientId);
      if (idx >= 0) {
        msgs[idx] = msgs[idx].copyWith(
          status: ChatMessageStatus.error,
        );
        emit(state.copyWith(messages: msgs, status: StateHasError(e)));
      }
    }
  }

  /// Resend a failed outgoing message (same [clientId] and content).
  Future<void> onRetrySend(String clientId) async {
    final msgs = List<ChatMessageEntity>.from(state.messages);
    final idx = msgs.indexWhere((m) => m.clientId == clientId);
    if (idx < 0) return;
    final m = msgs[idx];
    if (m.status != ChatMessageStatus.error) return;

    msgs[idx] = m.copyWith(status: ChatMessageStatus.sending);
    emit(
      state.copyWith(
        messages: msgs,
        lastUpdate: DateTime.timestamp(),
      ),
    );

    try {
      await _chatCase.sendMessage(
        receiverId: state.friend.id,
        clientId: clientId,
        content: m.content,
      );
    } catch (e) {
      final msgs = List<ChatMessageEntity>.from(state.messages);
      final i = msgs.indexWhere((x) => x.clientId == clientId);
      if (i >= 0) {
        msgs[i] = msgs[i].copyWith(
          status: ChatMessageStatus.error,
        );
        emit(state.copyWith(messages: msgs, status: StateHasError(e)));
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
      final msgs =
          state.messages
              .where(
                (m) =>
                    m.clientId != message.clientId ||
                    m.serverId != message.serverId,
              )
              .toList();
      emit(
        state.copyWith(
          messages: msgs,
          lastUpdate: DateTime.timestamp(),
        ),
      );
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
      final List<ChatMessageEntity> next;
      if (state.messages.isEmpty) {
        next = result.toList()..sort(_sortByDate);
      } else {
        next = [...result, ...state.messages]..sort(_sortByDate);
      }
      emit(
        state.copyWith(
          messages: next,
          status: StateStatus.isSuccess,
          lastUpdate: DateTime.timestamp(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  void _onMessage(ChatMessageEntity message) {
    final msgs = List<ChatMessageEntity>.from(state.messages);
    final index = msgs.indexWhere(
      (e) =>
          e.serverId == message.serverId ||
          (e.serverId.isEmpty && e.clientId == message.clientId),
    );
    if (index < 0) {
      msgs.insert(0, message);
    } else {
      msgs[index] = message;
    }
    emit(
      state.copyWith(
        messages: msgs,
        status: StateStatus.isSuccess,
        lastUpdate: DateTime.timestamp(),
      ),
    );
  }

  void _onMessageAck(MessageAck ack) {
    final msgs = List<ChatMessageEntity>.from(state.messages);
    final index = msgs.indexWhere(
      (e) => e.clientId == ack.clientId,
    );
    if (index >= 0) {
      msgs[index] = msgs[index].copyWith(
        serverId: ack.serverId,
        createdAt: ack.createdAt,
        status: ChatMessageStatus.sent,
      );
      emit(
        state.copyWith(
          messages: msgs,
          lastUpdate: DateTime.timestamp(),
        ),
      );
    }
  }

  void _onHistoryResponse(HistoryResponse response) {
    _isLoadingHistory = false;
    _hasMoreHistory = response.hasMore;

    final older = response.messages.toList();
    if (older.isEmpty) return;

    final existingIds = state.messages.map((m) => m.serverId).toSet();
    final newMessages = older.where((m) => !existingIds.contains(m.serverId));
    final merged = [...state.messages, ...newMessages]..sort(_sortByDate);

    emit(
      state.copyWith(
        messages: merged,
        status: StateStatus.isSuccess,
        lastUpdate: DateTime.timestamp(),
      ),
    );

    unawaited(_chatCase.saveMessages(messages: older));
  }

  int _sortByDate(ChatMessageEntity a, ChatMessageEntity b) =>
      b.createdAt.compareTo(a.createdAt);
}
