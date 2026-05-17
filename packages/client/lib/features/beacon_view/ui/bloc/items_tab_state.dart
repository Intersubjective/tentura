import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'items_tab_state.freezed.dart';

@freezed
abstract class ItemsTabState extends StateBase with _$ItemsTabState {
  const factory ItemsTabState({
    @Default([]) List<CoordinationItem> openItems,
    @Default([]) List<CoordinationItem> closedItems,
    @Default([]) List<CoordinationItem> draftAskItems,
    @Default([]) List<CoordinationItem> draftBlockerItems,
    CoordinationItem? currentCoordinationPlan,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ItemsTabState;

  const ItemsTabState._();

  int get unreadDiscussionCount => openItems.fold(
        0,
        (sum, item) => sum + item.unreadCount,
      );

  bool get hasUnreadItems => unreadDiscussionCount > 0;
}
