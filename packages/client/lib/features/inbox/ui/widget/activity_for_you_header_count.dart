import '../bloc/activity_offers_state.dart';

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
