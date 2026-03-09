import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/chat_message_entity.dart';
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

  @override
  Future<void> close() async {
    await _updatesSubscription.cancel();
    return super.close();
  }

  //
  //
  Future<void> onSendPressed(String text) async {
    try {
      await _chatCase.sendMessage(
        receiverId: state.friend.id,
        content: text.trim(),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> onMessageShown(ChatMessageEntity message) async {
    try {
      await _chatCase.setMessageSeen(message: message);
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  // TBD
  Future<void> onChatClear() async {}

  //
  //
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

      emit(
        ChatState(
          me: Profile(id: myId),
          friend: await _chatCase.fetchProfileById(state.friend.id),
          lastUpdate: DateTime.timestamp(),
        ),
      );
      return myId;
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
    return state.me.id;
  }

  //
  //
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

  //
  //
  void _onMessage(ChatMessageEntity message) {
    final index = state.messages.indexWhere(
      (e) => e.serverId == message.serverId,
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

  //
  //
  int _sortByDate(ChatMessageEntity a, ChatMessageEntity b) =>
      b.createdAt.compareTo(a.createdAt);
}
