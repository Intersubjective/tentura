import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/enum.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/chat_message_entity.dart';
import '../../domain/use_case/chat_case.dart';
import 'chat_news_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'chat_news_state.dart';

/// Global Cubit
@singleton
class ChatNewsCubit extends Cubit<ChatNewsState> {
  ChatNewsCubit(this._chatCase)
    : super(
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
  }

  final ChatCase _chatCase;

  late final StreamSubscription<String> _authChanges;

  late final StreamSubscription<WebSocketState> _webSocketStateSubscription;

  late final StreamSubscription<Iterable<ChatMessageEntity>>
  _messagesUpdatesSubscription;

  //
  @override
  @disposeMethod
  Future<void> close() async {
    await _authChanges.cancel();
    await _messagesUpdatesSubscription.cancel();
    await _webSocketStateSubscription.cancel();
    return super.close();
  }

  //
  //
  Future<void> _onWebSocketStateChanges(WebSocketState wsState) async {
    if (wsState == WebSocketState.connected) {
      _chatCase.subscribeToUpdates(
        fromMoment: await _chatCase.getCursor(userId: state.myId),
      );
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
        (await _chatCase.getUnseenMessagesFor(
          userId: userId,
        )).forEach(_updateStateWithMessage);
        emit(state.copyWith(status: StateStatus.isSuccess));
      } catch (e) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  //
  //
  Future<void> _onMessagesUpdate(Iterable<ChatMessageEntity> messages) async {
    if (messages.isNotEmpty) {
      messages.forEach(_updateStateWithMessage);

      emit(state.copyWith(lastUpdate: DateTime.timestamp()));

      await _chatCase.saveMessages(messages: messages);
    }
  }

  //
  //
  void _updateStateWithMessage(ChatMessageEntity message) {
    if (message.senderId == state.myId) {
      return;
    }

    switch (message.status) {
      case ChatMessageStatus.seen:
        state.messages[message.senderId]?.removeWhere(
          (e) => e.serverId == message.serverId,
        );

      case ChatMessageStatus.sent:
        if (state.messages.containsKey(message.senderId)) {
          final messagesOfSender = state.messages[message.senderId]!;
          final index = messagesOfSender.indexWhere(
            (e) => e.serverId == message.serverId,
          );
          index < 0
              ? messagesOfSender.add(message)
              : messagesOfSender[index] = message;
        } else {
          state.messages[message.senderId] = [message];
        }

      // ignore: no_default_cases //
      default:
    }
  }
}
