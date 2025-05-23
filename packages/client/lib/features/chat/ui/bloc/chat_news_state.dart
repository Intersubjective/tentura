import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/chat_message.dart';

part 'chat_news_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class ChatNewsState extends StateBase with _$ChatNewsState {
  const factory ChatNewsState({
    required String myId,
    required DateTime cursor,
    required Map<String, List<ChatMessage>> messages,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ChatNewsState;

  const ChatNewsState._();

  int get countNewTotal => messages.values.fold(0, (v, e) => v + e.length);
}
