import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'entity/my_work_card_view_model.dart';
import 'entity/my_work_fetch_types.dart';
import 'entity/my_work_filter.dart';
import 'entity/my_work_sort.dart';

/// Sort key: higher = earlier in list. Tie-break with [Beacon.updatedAt], then id.
int myWorkCardSortTier(MyWorkCardViewModel vm) {
  if (vm.showReadyForReviewChip || vm.showReviewCta) return 400;
  if (vm.attentionChip == MyWorkAttentionChip.reviewWindowOpen) return 390;
  if (vm.showReviewHelpOffersCta) return 350;
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
      BeaconCoordinationStatus.helpOffersWaitingForReview) {
    attention = MyWorkAttentionChip.reviewPending;
  } else if (beacon.coordinationStatus ==
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded) {
    attention = MyWorkAttentionChip.moreHelpNeeded;
  }

  final showReviewHelpOffersCta =
      beacon.coordinationStatus ==
          BeaconCoordinationStatus.helpOffersWaitingForReview &&
      beacon.helpOfferCount > 0;

  return MyWorkCardViewModel(
    beaconId: beacon.id,
    role: MyWorkCardRole.authored,
    kind: MyWorkCardKind.authoredActive,
    beacon: beacon,
    attentionChip: attention,
    showReviewHelpOffersCta: showReviewHelpOffersCta,
  );
}

MyWorkCardViewModel _deriveHelpOffered({
  required MyWorkHelpOfferedRow row,
  bool archived = false,
}) {
  final beacon = row.beacon;
  final lc = beacon.lifecycle;

  if (archived || lc.isClosedSection) {
    return MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.helpOffered,
      kind: MyWorkCardKind.helpOfferedClosed,
      beacon: beacon,
      offerHelpMessage: row.offerHelpMessage,
      authorResponseType: row.authorResponseType,
      forwarderSenders: row.forwarderSenders,
      showArchiveAffordance: true,
      helpOfferRowUpdatedAt: row.helpOfferRowUpdatedAt,
      authorCoordinationUpdatedAt: row.authorCoordinationUpdatedAt,
    );
  }

  final reviewOpen = lc == BeaconLifecycle.closedReviewOpen;

  return MyWorkCardViewModel(
    beaconId: beacon.id,
    role: MyWorkCardRole.helpOffered,
    kind: MyWorkCardKind.helpOfferedActive,
    beacon: beacon,
    offerHelpMessage: row.offerHelpMessage,
    authorResponseType: row.authorResponseType,
    forwarderSenders: row.forwarderSenders,
    showReadyForReviewChip: reviewOpen,
    showReviewCta: reviewOpen,
    helpOfferRowUpdatedAt: row.helpOfferRowUpdatedAt,
    authorCoordinationUpdatedAt: row.authorCoordinationUpdatedAt,
  );
}

/// Non-archived cards from init fetch (authored beacons + help-offered rows).
List<MyWorkCardViewModel> buildNonArchivedViewModels({
  required List<Beacon> authoredNonClosed,
  required List<MyWorkHelpOfferedRow> helpOfferedNonClosed,
}) {
  final authored = authoredNonClosed
      .map((b) => _deriveAuthored(beacon: b))
      .toList(growable: false);
  final authoredIds = authored.map((v) => v.beaconId).toSet();
  final helpOffered = helpOfferedNonClosed
      .map((r) => _deriveHelpOffered(row: r))
      .where((v) => !authoredIds.contains(v.beaconId))
      .toList(growable: false);
  final merged = [...authored, ...helpOffered]..sort(compareMyWorkCards);
  return merged;
}

List<MyWorkCardViewModel> filterMyWorkCardsForDesk({
  required MyWorkFilter filter,
  required List<MyWorkCardViewModel> nonArchivedCards,
  required List<MyWorkCardViewModel> archivedCards,
}) {
  return switch (filter) {
    MyWorkFilter.archived => archivedCards,
    MyWorkFilter.all => nonArchivedCards,
    MyWorkFilter.active => nonArchivedCards
        .where(
          (c) =>
              c.kind == MyWorkCardKind.authoredActive ||
              c.kind == MyWorkCardKind.helpOfferedActive,
        )
        .toList(),
    MyWorkFilter.drafts => nonArchivedCards
        .where((c) => c.kind == MyWorkCardKind.authoredDraft)
        .toList(),
    MyWorkFilter.authored => nonArchivedCards
        .where(
          (c) =>
              c.role == MyWorkCardRole.authored &&
              c.kind != MyWorkCardKind.authoredDraft,
        )
        .toList(),
    MyWorkFilter.helpOffered => nonArchivedCards
        .where((c) => c.role == MyWorkCardRole.helpOffered)
        .toList(),
  };
}

List<MyWorkCardViewModel> visibleMyWorkCardsForDesk({
  required MyWorkFilter filter,
  required MyWorkSort sort,
  required List<MyWorkCardViewModel> nonArchivedCards,
  required List<MyWorkCardViewModel> archivedCards,
}) {
  final base = filterMyWorkCardsForDesk(
    filter: filter,
    nonArchivedCards: nonArchivedCards,
    archivedCards: archivedCards,
  );
  final list = List<MyWorkCardViewModel>.from(base)
    ..sort((a, b) => compareMyWorkCardsForSort(sort, a, b));
  return list;
}

int countDraftMyWorkCards(List<MyWorkCardViewModel> nonArchivedCards) =>
    nonArchivedCards
        .where((c) => c.kind == MyWorkCardKind.authoredDraft)
        .length;

int archivedCountHintFromIds({
  required List<String> authoredClosedIdHints,
  required List<String> helpOfferedClosedIdHints,
}) =>
    authoredClosedIdHints.length +
    helpOfferedClosedIdHints
        .where((id) => !authoredClosedIdHints.contains(id))
        .length;

int? maxMyWorkDeskActivityEpochMs({
  required List<MyWorkCardViewModel> nonArchivedCards,
  required List<MyWorkCardViewModel> archivedCards,
}) {
  int? maxMs;
  for (final c in nonArchivedCards) {
    final m = c.newStuffActivityEpochMs;
    if (maxMs == null || m > maxMs) maxMs = m;
  }
  for (final c in archivedCards) {
    final m = c.newStuffActivityEpochMs;
    if (maxMs == null || m > maxMs) maxMs = m;
  }
  return maxMs;
}

/// Archived (closed lifecycle) cards from lazy closed fetch.
List<MyWorkCardViewModel> buildArchivedViewModels({
  required List<Beacon> authoredClosed,
  required List<MyWorkHelpOfferedRow> helpOfferedClosed,
}) {
  final authored = authoredClosed
      .map((b) => _deriveAuthored(beacon: b, archived: true))
      .toList(growable: false);
  final authoredIds = authored.map((v) => v.beaconId).toSet();
  final helpOffered = helpOfferedClosed
      .map((r) => _deriveHelpOffered(row: r, archived: true))
      .where((v) => !authoredIds.contains(v.beaconId))
      .toList(growable: false);
  final merged = [...authored, ...helpOffered]..sort(compareMyWorkCards);
  return merged;
}

/// View model for beacon view, aligned with My Work card derivation (`myWorkStatusLine`).
MyWorkCardViewModel myWorkCardViewModelForBeaconView({
  required Beacon beacon,
  required bool isBeaconMine,
  required bool isHelpOffered,
  required String myOfferHelpMessage,
  CoordinationResponseType? myAuthorResponseType,
  DateTime? myHelpOfferUpdatedAt,
}) {
  if (isBeaconMine) {
    return _deriveAuthored(beacon: beacon);
  }
  if (isHelpOffered) {
    final archived = beacon.lifecycle.isClosedSection;
    final row = (
      beacon: beacon,
      offerHelpMessage: myOfferHelpMessage,
      helpType: null,
      authorResponseType: myAuthorResponseType,
      forwarderSenders: <Profile>[],
      helpOfferRowUpdatedAt: myHelpOfferUpdatedAt ?? beacon.updatedAt,
      authorCoordinationUpdatedAt: null,
    );
    return _deriveHelpOffered(row: row, archived: archived);
  }
  return _deriveAuthored(beacon: beacon);
}
