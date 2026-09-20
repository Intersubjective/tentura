import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';

import 'entity/my_work_card_view_model.dart';
import 'entity/my_work_filter.dart';

/// U17d / D18 — is My Desk **attention-clear while its work remains**?
///
/// D18's My Desk sentence is a boundary before it is a feature: a desk with
/// nothing left demanding a response is not a desk with nothing on it, and
/// the two must never be said with the same words. So this is deliberately
/// **false for an empty desk** — that surface already has its own three
/// voices in `MyWorkEmptyBody`, and "you're caught up" over an empty screen
/// is the fabricated success D18 forbids.
///
/// [attentionLoaded] is an input rather than an inference because an empty
/// `attentionByBeacon` is exactly the shape of "not fetched yet": celebrating
/// off it would be the "never while loading" rule broken by a map literal.
bool myDeskIsCaughtUp({
  required MyWorkFilter filter,
  required Iterable<MyWorkCardViewModel> cards,
  required Map<String, MyWorkBeaconAttention> attentionByBeacon,
  required bool attentionLoaded,
  required bool hasError,
}) {
  if (!attentionLoaded || hasError) return false;
  if (cards.isEmpty) return false;
  if (!_filterShowsResponsibilities(filter)) return false;
  for (final card in cards) {
    final attention = attentionByBeacon[card.beaconId];
    if (attention == null) continue;
    if (attention.liveObligations.isNotEmpty) return false;
    if (attention.unseenCount > 0) return false;
  }
  return true;
}

/// Drafts and the archive are not responsibilities: a draft asks nothing of
/// anybody and an archived Request is over.
bool _filterShowsResponsibilities(MyWorkFilter filter) => switch (filter) {
  MyWorkFilter.active ||
  MyWorkFilter.all ||
  MyWorkFilter.authored ||
  MyWorkFilter.helpOffered => true,
  MyWorkFilter.drafts || MyWorkFilter.archived => false,
};
