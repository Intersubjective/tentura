import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'item_actions_state.freezed.dart';

@freezed
abstract class ItemActionsState extends StateBase with _$ItemActionsState {
  const factory ItemActionsState({
    required CoordinationItem item,
    @Default(StateIsSuccess()) StateStatus status,
    CoordinationItem? pendingResolution,
  }) = _ItemActionsState;

  const ItemActionsState._();
}
