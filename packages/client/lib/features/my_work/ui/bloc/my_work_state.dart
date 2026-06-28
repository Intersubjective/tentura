import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_sort.dart';

export 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
export 'package:tentura/features/my_work/domain/entity/my_work_sort.dart';
export 'package:tentura/ui/bloc/state_base.dart';

part 'my_work_state.freezed.dart';

@freezed
abstract class MyWorkState extends StateBase with _$MyWorkState {
  const factory MyWorkState({
    @Default([]) List<MyWorkCardViewModel> nonArchivedCards,
    @Default([]) List<MyWorkCardViewModel> archivedCards,
    @Default(0) int archivedCountHint,
    @Default(false) bool archivedDataFetched,
    @Default(false) bool archivedFetchInProgress,
    @Default(MyWorkFilter.active) MyWorkFilter filter,
    @Default(MyWorkSort.recent) MyWorkSort sort,
    @Default(false) bool finishedArchiveHintDismissed,
    @Default(StateIsLoading()) StateStatus status,
    Object? loadError,
  }) = _MyWorkState;

  const MyWorkState._();

  bool get hasError => loadError != null;

  /// Visible cards for the selected [filter], ordered by tier then [sort].
  List<MyWorkCardViewModel> get visibleCards => visibleMyWorkCardsForDesk(
    filter: filter,
    sort: sort,
    nonArchivedCards: nonArchivedCards,
    archivedCards: archivedCards,
  );

  int get draftCount => countDraftMyWorkCards(nonArchivedCards);
}
