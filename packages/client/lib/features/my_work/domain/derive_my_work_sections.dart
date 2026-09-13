import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';

import 'entity/my_work_card_view_model.dart';
import 'entity/my_work_filter.dart';

/// Responsibility sections for the redesigned My Work desk (UNIT 13).
enum MyWorkDeskSection {
  needsYou,
  inProgress,
  finished,

  /// Drafts / archived filters: one list, no section headers.
  unlabeled,
}

class MyWorkDeskSectionGroup {
  const MyWorkDeskSectionGroup({
    required this.section,
    required this.cards,
  });

  final MyWorkDeskSection section;
  final List<MyWorkCardViewModel> cards;
}

bool myWorkCardHasLiveObligation(
  MyWorkCardViewModel card,
  Map<String, MyWorkBeaconAttention> attentionByBeacon,
) =>
    attentionByBeacon[card.beaconId]?.liveObligations.isNotEmpty == true;

/// Live obligation receipt count for cards in the Needs you section (D4).
int myWorkNeedsYouObligationReceiptCount(
  Iterable<MyWorkCardViewModel> cards,
  Map<String, MyWorkBeaconAttention> attentionByBeacon,
) {
  var count = 0;
  for (final card in cards) {
    count += attentionByBeacon[card.beaconId]?.liveObligations.length ?? 0;
  }
  return count;
}

bool _filterUsesResponsibilitySections(MyWorkFilter filter) =>
    switch (filter) {
      MyWorkFilter.active ||
      MyWorkFilter.all ||
      MyWorkFilter.authored ||
      MyWorkFilter.helpOffered => true,
      MyWorkFilter.drafts || MyWorkFilter.archived => false,
    };

/// Priority: live obligation → Needs you; else finished → Finished; else In progress.
///
/// [cards] must already be ordered for the desk (e.g. [visibleMyWorkCardsForDesk]);
/// order within each section is preserved from that list.
List<MyWorkDeskSectionGroup> deriveMyWorkSections({
  required List<MyWorkCardViewModel> cards,
  required Map<String, MyWorkBeaconAttention> attentionByBeacon,
  required MyWorkFilter filter,
}) {
  if (!_filterUsesResponsibilitySections(filter)) {
    if (cards.isEmpty) {
      return const [];
    }
    return [
      MyWorkDeskSectionGroup(
        section: MyWorkDeskSection.unlabeled,
        cards: List<MyWorkCardViewModel>.from(cards),
      ),
    ];
  }

  final needsYou = <MyWorkCardViewModel>[];
  final inProgress = <MyWorkCardViewModel>[];
  final finished = <MyWorkCardViewModel>[];

  for (final card in cards) {
    if (myWorkCardHasLiveObligation(card, attentionByBeacon)) {
      needsYou.add(card);
    } else if (card.isFinishedCard) {
      finished.add(card);
    } else {
      inProgress.add(card);
    }
  }

  final groups = <MyWorkDeskSectionGroup>[];
  if (needsYou.isNotEmpty) {
    groups.add(
      MyWorkDeskSectionGroup(
        section: MyWorkDeskSection.needsYou,
        cards: needsYou,
      ),
    );
  }
  if (inProgress.isNotEmpty) {
    groups.add(
      MyWorkDeskSectionGroup(
        section: MyWorkDeskSection.inProgress,
        cards: inProgress,
      ),
    );
  }
  if (finished.isNotEmpty) {
    groups.add(
      MyWorkDeskSectionGroup(
        section: MyWorkDeskSection.finished,
        cards: finished,
      ),
    );
  }
  return groups;
}
