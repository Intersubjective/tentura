import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/chat_message_entity.dart';

part 'chat_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class ChatState extends StateBase with _$ChatState {
  const factory ChatState({
    required DateTime lastUpdate,
    @Default(Profile()) Profile me,
    @Default(Profile()) Profile friend,
    @Default([]) List<ChatMessageEntity> messages,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ChatState;

  const ChatState._();
}
