import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_item_message.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'item_discussion_state.freezed.dart';

@freezed
abstract class ItemDiscussionState extends StateBase
    with _$ItemDiscussionState {
  const factory ItemDiscussionState({
    required CoordinationItem item,
    @Default([]) List<CoordinationItemMessage> messages,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ItemDiscussionState;

  const ItemDiscussionState._();
}
