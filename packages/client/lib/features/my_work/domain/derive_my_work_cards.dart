import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';

import 'entity/my_work_card_view_model.dart';
import 'entity/my_work_fetch_types.dart';
import 'entity/my_work_sort.dart';

/// Sort key: higher = earlier in list. Tie-break with [Beacon.updatedAt], then id.
int myWorkCardSortTier(MyWorkCardViewModel vm) {
  if (vm.showReadyForReviewChip || vm.showReviewCta) return 400;
  if (vm.attentionChip == MyWorkAttentionChip.reviewWindowOpen) return 390;
  if (vm.showReviewCommitmentsCta) return 350;
  if (vm.attentionChip == MyWorkAttentionChip.reviewPending) return 330;
  if (vm.attentionChip == MyWorkAttentionChip.moreHelpNeeded) return 250;
  if (vm.kind == MyWorkCardKind.authoredDraft) return 50;
  if (vm.beacon.lifecycle == BeaconLifecycle.pendingReview) return 120;
  return 200;
}

int compareMyWorkCards(MyWorkCardViewModel a, MyWorkCardViewModel b) {
  return compareMyWorkCardsForSort(MyWorkSort.recent, a, b);
}

/// Applies [MyWorkSort] after the attention tier (same tier ordering as legacy list).
int compareMyWorkCardsForSort(
  MyWorkSort sort,
  MyWorkCardViewModel a,
  MyWorkCardViewModel b,
) {
  final t = myWorkCardSortTier(b).compareTo(myWorkCardSortTier(a));
  if (t != 0) return t;
  switch (sort) {
    case MyWorkSort.recent:
      final u = b.beacon.updatedAt.compareTo(a.beacon.updatedAt);
      if (u != 0) return u;
      return a.beaconId.compareTo(b.beaconId);
    case MyWorkSort.oldest:
      final u = a.beacon.updatedAt.compareTo(b.beacon.updatedAt);
      if (u != 0) return u;
      return a.beaconId.compareTo(b.beaconId);
    case MyWorkSort.alphabetical:
      final ta = a.beacon.title.trim().toLowerCase();
      final tb = b.beacon.title.trim().toLowerCase();
      final c = ta.compareTo(tb);
      if (c != 0) return c;
      return a.beaconId.compareTo(b.beaconId);
  }
}

MyWorkCardViewModel _deriveAuthored({
  required Beacon beacon,
  bool archived = false,
}) {
  final lc = beacon.lifecycle;
  if (!archived && lc == BeaconLifecycle.draft) {
    return MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredDraft,
      beacon: beacon,
    );
  }
  if (archived || lc.isClosedSection) {
    return MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredClosed,
      beacon: beacon,
      showArchiveAffordance: true,
    );
  }

  MyWorkAttentionChip? attention;
  if (lc == BeaconLifecycle.closedReviewOpen) {
    attention = MyWorkAttentionChip.reviewWindowOpen;
  } else if (beacon.coordinationStatus ==
      BeaconCoordinationStatus.commitmentsWaitingForReview) {
    attention = MyWorkAttentionChip.reviewPending;
  } else if (beacon.coordinationStatus ==
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded) {
    attention = MyWorkAttentionChip.moreHelpNeeded;
  }

  final showReviewCommitmentsCta =
      beacon.coordinationStatus ==
          BeaconCoordinationStatus.commitmentsWaitingForReview &&
      beacon.commitmentCount > 0;

  return MyWorkCardViewModel(
    beaconId: beacon.id,
    role: MyWorkCardRole.authored,
    kind: MyWorkCardKind.authoredActive,
    beacon: beacon,
    attentionChip: attention,
    showReviewCommitmentsCta: showReviewCommitmentsCta,
  );
}

MyWorkCardViewModel _deriveCommitted({
  required MyWorkCommittedRow row,
  bool archived = false,
}) {
  final beacon = row.beacon;
  final lc = beacon.lifecycle;

  if (archived || lc.isClosedSection) {
    return MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.committed,
      kind: MyWorkCardKind.committedClosed,
      beacon: beacon,
      commitMessage: row.commitMessage,
      authorResponseType: row.authorResponseType,
      forwarderSenders: row.forwarderSenders,
      showArchiveAffordance: true,
      commitmentRowUpdatedAt: row.commitmentRowUpdatedAt,
      authorCoordinationUpdatedAt: row.authorCoordinationUpdatedAt,
    );
  }

  final reviewOpen = lc == BeaconLifecycle.closedReviewOpen;

  return MyWorkCardViewModel(
    beaconId: beacon.id,
    role: MyWorkCardRole.committed,
    kind: MyWorkCardKind.committedActive,
    beacon: beacon,
    commitMessage: row.commitMessage,
    authorResponseType: row.authorResponseType,
    forwarderSenders: row.forwarderSenders,
    showReadyForReviewChip: reviewOpen,
    showReviewCta: reviewOpen,
    commitmentRowUpdatedAt: row.commitmentRowUpdatedAt,
    authorCoordinationUpdatedAt: row.authorCoordinationUpdatedAt,
  );
}

/// Non-archived cards from init fetch (authored beacons + committed rows).
List<MyWorkCardViewModel> buildNonArchivedViewModels({
  required List<Beacon> authoredNonClosed,
  required List<MyWorkCommittedRow> committedNonClosed,
}) {
  final authored = authoredNonClosed
      .map((b) => _deriveAuthored(beacon: b))
      .toList(growable: false);
  final authoredIds = authored.map((v) => v.beaconId).toSet();
  final committed = committedNonClosed
      .map((r) => _deriveCommitted(row: r))
      .where((v) => !authoredIds.contains(v.beaconId))
      .toList(growable: false);
  final merged = [...authored, ...committed]..sort(compareMyWorkCards);
  return merged;
}

/// Archived (closed lifecycle) cards from lazy closed fetch.
List<MyWorkCardViewModel> buildArchivedViewModels({
  required List<Beacon> authoredClosed,
  required List<MyWorkCommittedRow> committedClosed,
}) {
  final authored = authoredClosed
      .map((b) => _deriveAuthored(beacon: b, archived: true))
      .toList(growable: false);
  final authoredIds = authored.map((v) => v.beaconId).toSet();
  final committed = committedClosed
      .map((r) => _deriveCommitted(row: r, archived: true))
      .where((v) => !authoredIds.contains(v.beaconId))
      .toList(growable: false);
  final merged = [...authored, ...committed]..sort(compareMyWorkCards);
  return merged;
}
