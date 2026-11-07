import '../bloc/activity_offers_state.dart';

/// Whether Activity should render the «For you» section header above the
/// pinned zone (#1068, same rule as #1047).
bool activityForYouPinnedZoneHasRows({
  required ActivityOffersState offersState,
  required int visiblePinnedCount,
  required bool pinnedPromptRows,
  required bool collapsedInvitePrompt,
}) {
  if (offersState.pageLoadFailed) return true;
  if (visiblePinnedCount > 0) return true;
  if (pinnedPromptRows || collapsedInvitePrompt) return true;
  if (offersState.hasMore) {
    final aggregate = offersState.totalCount;
    if (aggregate != null && aggregate > 0) return true;
  }
  return false;
}

/// Count beside «FOR YOU» in Activity: pinned decisions waiting on the viewer.
///
/// While another page of offers is still off-screen, the header keeps the
/// server aggregate. Once everything loaded is on screen, the count tracks
/// visible pinned cards (including exit motion).
int? activityForYouHeaderCount({
  required ActivityOffersState offersState,
  required int visiblePinnedCount,
}) {
  if (offersState.countLoadFailed) return null;
  if (offersState.hasMore) {
    final aggregate = offersState.totalCount;
    if (aggregate == null || aggregate <= 0) return null;
    return aggregate;
  }
  if (visiblePinnedCount <= 0) return null;
  return visiblePinnedCount;
}
