import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'my_work_state.freezed.dart';

enum MyWorkFilter { all, authored, committed, archived }

@freezed
abstract class MyWorkState extends StateBase with _$MyWorkState {
  const factory MyWorkState({
    @Default([]) List<MyWorkCardViewModel> nonArchivedCards,
    @Default([]) List<MyWorkCardViewModel> archivedCards,
    @Default([]) List<String> authoredClosedIdHints,
    @Default([]) List<String> committedClosedIdHints,
    @Default(false) bool closedDataFetched,
    @Default(false) bool closedFetchInProgress,
    @Default(MyWorkFilter.all) MyWorkFilter filter,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _MyWorkState;

  const MyWorkState._();

  /// Visible cards for the selected [filter] (pre-sorted in cubit).
  List<MyWorkCardViewModel> get visibleCards {
    switch (filter) {
      case MyWorkFilter.archived:
        return archivedCards;
      case MyWorkFilter.all:
        return nonArchivedCards;
      case MyWorkFilter.authored:
        return nonArchivedCards
            .where((c) => c.role == MyWorkCardRole.authored)
            .toList();
      case MyWorkFilter.committed:
        return nonArchivedCards
            .where((c) => c.role == MyWorkCardRole.committed)
            .toList();
    }
  }

  /// Closed-tab style count before lazy fetch completes (deduped beacon ids).
  int get archivedCountHint =>
      authoredClosedIdHints.length +
      committedClosedIdHints
          .where((id) => !authoredClosedIdHints.contains(id))
          .length;
}
