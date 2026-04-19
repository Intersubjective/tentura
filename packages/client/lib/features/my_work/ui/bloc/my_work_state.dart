import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_sort.dart';

export 'package:tentura/features/my_work/domain/entity/my_work_sort.dart';
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
    @Default(MyWorkSort.recent) MyWorkSort sort,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _MyWorkState;

  const MyWorkState._();

  /// Visible cards for the selected [filter], ordered by tier then [sort].
  List<MyWorkCardViewModel> get visibleCards {
    final base = switch (filter) {
      MyWorkFilter.archived => archivedCards,
      MyWorkFilter.all => nonArchivedCards,
      MyWorkFilter.authored =>
        nonArchivedCards
            .where((c) => c.role == MyWorkCardRole.authored)
            .toList(),
      MyWorkFilter.committed =>
        nonArchivedCards
            .where((c) => c.role == MyWorkCardRole.committed)
            .toList(),
    };
    final list = List<MyWorkCardViewModel>.from(base)
      ..sort((a, b) => compareMyWorkCardsForSort(sort, a, b));
    return list;
  }

  /// Closed-tab style count before lazy fetch completes (deduped beacon ids).
  int get archivedCountHint =>
      authoredClosedIdHints.length +
      committedClosedIdHints
          .where((id) => !authoredClosedIdHints.contains(id))
          .length;
}
