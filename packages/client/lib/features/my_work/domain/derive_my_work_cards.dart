import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/coordination/beacon_has_unreviewed_offers.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/review_package_state.dart';

import 'entity/my_work_card_view_model.dart';
import 'entity/my_work_fetch_types.dart';
import 'entity/my_work_filter.dart';
import 'entity/my_work_sort.dart';

/// Sort key: higher = earlier in list. Tie-break with [Beacon.updatedAt], then id.
int myWorkCardSortTier(MyWorkCardViewModel vm) {
  if (vm.showReviewCta) return 400;
  if (vm.attentionChip == MyWorkAttentionChip.reviewWindowOpen) return 390;
  if (vm.showReviewHelpOffersCta) return 350;
  if (vm.attentionChip == MyWorkAttentionChip.moreHelpNeeded) return 250;
  if (vm.kind == MyWorkCardKind.authoredDraft) return 50;
  if (vm.kind == MyWorkCardKind.authoredFinished ||
      vm.kind == MyWorkCardKind.helpOfferedFinished) {
    return 10;
  }
  return 200;
}

/// Viewer package state for a My Work card, from the lifecycle and the batch
/// window row. Same inputs as the beacon HUD/banner inference; a missing row
/// means the viewer has no window.
ReviewPackageState deriveMyWorkReviewPackageState({
  required BeaconStatus beaconStatus,
  required ReviewWindowInfo? review,
}) => deriveReviewPackageState(
  beaconIsInReview:
      beaconStatus == BeaconStatus.reviewOpen &&
      !(review?.windowComplete ?? false),
  beaconIsClosed:
      beaconStatus == BeaconStatus.closed || (review?.windowComplete ?? false),
  hasWindow: review?.hasWindow ?? false,
  windowComplete: review?.windowComplete ?? false,
  userReviewStatus: review?.userReviewStatus,
  sentAt: review?.sentAt,
  requiredTotal: review?.requiredTotal ?? 0,
  requiredAnswered: review?.requiredReviewed ?? 0,
  totalTargets: review?.totalCount ?? 0,
);

/// Whether [state] still asks the viewer to act on their review package.
bool myWorkReviewPackageNeedsAction(ReviewPackageState? state) =>
    state == ReviewPackageState.inProgress ||
    state == ReviewPackageState.readyToSend ||
    state == ReviewPackageState.changedNotSent;

/// The server's ordering keys for one Request (U10c).
///
/// `needsYouAt` is the latest live-obligation creation time — the Needs-you
/// zone's key — and `firstEntryAt` is when the Request entered the surface,
/// which is what establishes its place and never moves afterwards. Neither is
/// touched by an optional event; `Beacon.updatedAt`, which the desk used to
/// sort by, is (D08).
typedef MyWorkOrderingKeys = ({DateTime? needsYouAt, DateTime? firstEntryAt});

const MyWorkOrderingKeys kMyWorkNoOrderingKeys = (
  needsYouAt: null,
  firstEntryAt: null,
);

typedef MyWorkOrderingKeysLookup = MyWorkOrderingKeys Function(String beaconId);

MyWorkOrderingKeysLookup myWorkOrderingKeysFrom(
  Map<String, MyWorkBeaconAttention> attentionByBeacon,
) => (beaconId) {
  final row = attentionByBeacon[beaconId];
  if (row == null) return kMyWorkNoOrderingKeys;
  return (needsYouAt: row.needsYouAt, firstEntryAt: row.firstEntryAt);
};

int compareMyWorkCards(MyWorkCardViewModel a, MyWorkCardViewModel b) {
  return compareMyWorkCardsForSort(MyWorkSort.recent, a, b);
}

/// Applies [MyWorkSort] after the Needs-you zone and the attention tier.
int compareMyWorkCardsForSort(
  MyWorkSort sort,
  MyWorkCardViewModel a,
  MyWorkCardViewModel b, {
  MyWorkOrderingKeysLookup? orderingKeys,
}) {
  final ka = orderingKeys?.call(a.beaconId) ?? kMyWorkNoOrderingKeys;
  final kb = orderingKeys?.call(b.beaconId) ?? kMyWorkNoOrderingKeys;

  // Needs you first: a new obligation promotes, its resolution demotes. This
  // is a zone, not a sort, so it holds under every user-selected sort.
  final na = ka.needsYouAt;
  final nb = kb.needsYouAt;
  if ((na == null) != (nb == null)) return na != null ? -1 : 1;
  if (na != null && nb != null) {
    final c = nb.compareTo(na);
    if (c != 0) return c;
    return a.beaconId.compareTo(b.beaconId);
  }

  final t = myWorkCardSortTier(b).compareTo(myWorkCardSortTier(a));
  if (t != 0) return t;
  // Stable entry/creation order, never the mutable `Beacon.updatedAt` an
  // optional event moves.
  final ea = ka.firstEntryAt ?? a.beacon.createdAt;
  final eb = kb.firstEntryAt ?? b.beacon.createdAt;
  switch (sort) {
    case MyWorkSort.recent:
      final u = eb.compareTo(ea);
      if (u != 0) return u;
      return a.beaconId.compareTo(b.beaconId);
    case MyWorkSort.oldest:
      final u = ea.compareTo(eb);
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
  final lc = beacon.status;
  if (!archived && lc == BeaconStatus.draft) {
  return MyWorkCardViewModel(
    beaconId: beacon.id,
    role: MyWorkCardRole.authored,
    kind: MyWorkCardKind.authoredDraft,
    beacon: beacon,
    sources: {MyWorkMembershipSource.authored},
  );
  }
  if (archived) {
    return MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredArchived,
      beacon: beacon,
      showArchiveAffordance: true,
      sources: {MyWorkMembershipSource.authored},
      viewerArchived: true,
    );
  }
  if (lc.isFinished) {
    return MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredFinished,
      beacon: beacon,
      showArchiveAffordance: true,
      sources: {MyWorkMembershipSource.authored},
    );
  }

  MyWorkAttentionChip? attention;
  if (lc == BeaconStatus.reviewOpen) {
    attention = MyWorkAttentionChip.reviewWindowOpen;
  } else if (beacon.status == BeaconStatus.needsMoreHelp) {
    attention = MyWorkAttentionChip.moreHelpNeeded;
  }

  final showReviewHelpOffersCta = beaconHasUnreviewedOffers(beacon);

  return MyWorkCardViewModel(
    beaconId: beacon.id,
    role: MyWorkCardRole.authored,
    kind: MyWorkCardKind.authoredActive,
    beacon: beacon,
    attentionChip: attention,
    showReviewHelpOffersCta: showReviewHelpOffersCta,
    sources: {MyWorkMembershipSource.authored},
  );
}

MyWorkCardViewModel _deriveObligation({
  required Beacon beacon,
  required bool viewerArchived,
}) {
  return MyWorkCardViewModel(
    beaconId: beacon.id,
    role: MyWorkCardRole.obligation,
    kind: viewerArchived
        ? MyWorkCardKind.obligationArchived
        : MyWorkCardKind.obligationActive,
    beacon: beacon,
    sources: {MyWorkMembershipSource.obligation},
    viewerArchived: viewerArchived,
  );
}

MyWorkCardViewModel _deriveHelpOffered({
  required MyWorkHelpOfferedRow row,
  bool archived = false,
}) {
  final beacon = row.beacon;
  final lc = beacon.status;

  if (archived) {
    return MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.helpOffered,
      kind: MyWorkCardKind.helpOfferedArchived,
      beacon: beacon,
      offerHelpMessage: row.offerHelpMessage,
      authorResponseType: row.authorResponseType,
      stakeState: row.stakeState,
      forwarderSenders: row.forwarderSenders,
      showArchiveAffordance: true,
      helpOfferRowUpdatedAt: row.helpOfferRowUpdatedAt,
      authorCoordinationUpdatedAt: row.authorCoordinationUpdatedAt,
      sources: {MyWorkMembershipSource.helpOffered},
      viewerArchived: true,
    );
  }

  if (lc.isFinished) {
    return MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.helpOffered,
      kind: MyWorkCardKind.helpOfferedFinished,
      beacon: beacon,
      offerHelpMessage: row.offerHelpMessage,
      authorResponseType: row.authorResponseType,
      stakeState: row.stakeState,
      forwarderSenders: row.forwarderSenders,
      showArchiveAffordance: true,
      helpOfferRowUpdatedAt: row.helpOfferRowUpdatedAt,
      authorCoordinationUpdatedAt: row.authorCoordinationUpdatedAt,
      sources: {MyWorkMembershipSource.helpOffered},
    );
  }

  return MyWorkCardViewModel(
    beaconId: beacon.id,
    role: MyWorkCardRole.helpOffered,
    kind: MyWorkCardKind.helpOfferedActive,
    beacon: beacon,
    offerHelpMessage: row.offerHelpMessage,
    authorResponseType: row.authorResponseType,
    stakeState: row.stakeState,
    forwarderSenders: row.forwarderSenders,
    helpOfferRowUpdatedAt: row.helpOfferRowUpdatedAt,
    authorCoordinationUpdatedAt: row.authorCoordinationUpdatedAt,
    sources: {MyWorkMembershipSource.helpOffered},
  );
}

/// Inserts or replaces an authored card for [beacon] in [cards].
List<MyWorkCardViewModel> upsertAuthoredMyWorkCard(
  List<MyWorkCardViewModel> cards,
  Beacon beacon,
) {
  final card = _deriveAuthored(beacon: beacon);
  final without = cards.where((c) => c.beaconId != beacon.id).toList();
  return [...without, card]..sort(compareMyWorkCards);
}

/// Merges [serverCards] with local cards for [preferIds] missing from the server.
List<MyWorkCardViewModel> mergeMyWorkDeskCards({
  required List<MyWorkCardViewModel> serverCards,
  required List<MyWorkCardViewModel> localCards,
  required Set<String> preferIds,
}) {
  if (preferIds.isEmpty) {
    return serverCards;
  }
  final serverIds = serverCards.map((c) => c.beaconId).toSet();
  final localById = {for (final c in localCards) c.beaconId: c};
  final preserved = [
    for (final id in preferIds)
      if (!serverIds.contains(id) && localById.containsKey(id)) localById[id]!,
  ];
  if (preserved.isEmpty) {
    return serverCards;
  }
  return [...serverCards, ...preserved]..sort(compareMyWorkCards);
}

/// Non-archived cards from init fetch (authored, help-offered, and obligations).
List<MyWorkCardViewModel> buildNonArchivedViewModels({
  required List<Beacon> authoredNonArchived,
  required List<MyWorkHelpOfferedRow> helpOfferedNonArchived,
  List<MyWorkObligationRow> obligationBeacons = const [],
}) {
  final byId = <String, MyWorkCardViewModel>{};

  for (final beacon in authoredNonArchived) {
    byId[beacon.id] = _deriveAuthored(beacon: beacon);
  }

  for (final row in helpOfferedNonArchived) {
    final id = row.beacon.id;
    if (byId.containsKey(id)) {
      continue;
    }
    byId[id] = _deriveHelpOffered(row: row);
  }

  for (final row in obligationBeacons) {
    final id = row.beacon.id;
    final existing = byId[id];
    if (existing != null) {
      final viewerArchived = row.viewerArchived || existing.viewerArchived;
      var merged = existing.copyWith(
        sources: {
          ...existing.sources,
          MyWorkMembershipSource.obligation,
        },
        viewerArchived: viewerArchived,
      );
      if (viewerArchived) {
        merged =
            myWorkCardAfterArchiveRevocation(
              merged.copyWith(viewerArchived: false),
            ) ??
            merged;
      }
      byId[id] = merged;
    } else {
      byId[id] = _deriveObligation(
        beacon: row.beacon,
        viewerArchived: row.viewerArchived,
      );
    }
  }

  return byId.values.toList()..sort(compareMyWorkCards);
}

List<MyWorkCardViewModel> filterMyWorkCardsForDesk({
  required MyWorkFilter filter,
  required List<MyWorkCardViewModel> nonArchivedCards,
  required List<MyWorkCardViewModel> archivedCards,
}) {
  return switch (filter) {
    MyWorkFilter.archived => archivedCards,
    MyWorkFilter.all => nonArchivedCards,
    MyWorkFilter.active =>
      nonArchivedCards
          .where(
            (c) =>
                c.kind == MyWorkCardKind.authoredActive ||
                c.kind == MyWorkCardKind.helpOfferedActive ||
                c.kind == MyWorkCardKind.authoredFinished ||
                c.kind == MyWorkCardKind.helpOfferedFinished ||
                c.kind == MyWorkCardKind.obligationActive ||
                c.kind == MyWorkCardKind.obligationArchived,
          )
          .toList(),
    MyWorkFilter.drafts =>
      nonArchivedCards
          .where((c) => c.kind == MyWorkCardKind.authoredDraft)
          .toList(),
    MyWorkFilter.authored =>
      nonArchivedCards
          .where(
            (c) =>
                c.role == MyWorkCardRole.authored &&
                c.kind != MyWorkCardKind.authoredDraft,
          )
          .toList(),
    MyWorkFilter.helpOffered =>
      nonArchivedCards
          .where((c) => c.role == MyWorkCardRole.helpOffered)
          .toList(),
  };
}

List<MyWorkCardViewModel> visibleMyWorkCardsForDesk({
  required MyWorkFilter filter,
  required MyWorkSort sort,
  required List<MyWorkCardViewModel> nonArchivedCards,
  required List<MyWorkCardViewModel> archivedCards,
  Map<String, MyWorkBeaconAttention> attentionByBeacon = const {},
}) {
  final base = filterMyWorkCardsForDesk(
    filter: filter,
    nonArchivedCards: nonArchivedCards,
    archivedCards: archivedCards,
  );
  final keys = myWorkOrderingKeysFrom(attentionByBeacon);
  final list = List<MyWorkCardViewModel>.from(base)
    ..sort(
      (a, b) => compareMyWorkCardsForSort(sort, a, b, orderingKeys: keys),
    );
  return list;
}

int countDraftMyWorkCards(List<MyWorkCardViewModel> nonArchivedCards) =>
    nonArchivedCards
        .where((c) => c.kind == MyWorkCardKind.authoredDraft)
        .length;

/// Revokes authored / help-offered membership after the viewer archives.
///
/// Returns `null` when no membership source remains (card leaves the desk).
/// When [card] is already archived, returns it unchanged (idempotent).
MyWorkCardViewModel? myWorkCardAfterArchiveRevocation(
  MyWorkCardViewModel card,
) {
  if (card.viewerArchived) {
    return card;
  }
  final nextSources = card.sources.difference({
    MyWorkMembershipSource.authored,
    MyWorkMembershipSource.helpOffered,
  });
  if (nextSources.isEmpty) {
    return null;
  }
  if (nextSources.length == 1 &&
      nextSources.single == MyWorkMembershipSource.obligation) {
    return card.copyWith(
      role: MyWorkCardRole.obligation,
      kind: MyWorkCardKind.obligationArchived,
      sources: nextSources,
      viewerArchived: true,
      showArchiveAffordance: false,
      showReviewCta: false,
      showCloseNowCta: false,
      showReviewHelpOffersCta: false,
      attentionChip: null,
    );
  }
  return card.copyWith(
    sources: nextSources,
    viewerArchived: true,
    showArchiveAffordance: false,
    showReviewCta: false,
    showCloseNowCta: false,
    showReviewHelpOffersCta: false,
    attentionChip: null,
  );
}

/// Archived cards from lazy archived fetch.
List<MyWorkCardViewModel> buildArchivedViewModels({
  required List<Beacon> authoredArchived,
  required List<MyWorkHelpOfferedRow> helpOfferedArchived,
}) {
  final authored = authoredArchived
      .map((b) => _deriveAuthored(beacon: b, archived: true))
      .toList(growable: false);
  final authoredIds = authored.map((v) => v.beaconId).toSet();
  final helpOffered = helpOfferedArchived
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
    final row = (
      beacon: beacon,
      offerHelpMessage: myOfferHelpMessage,
      helpType: null,
      authorResponseType: myAuthorResponseType,
      stakeState: CommitmentStakeState.none,
      forwarderSenders: <Profile>[],
      helpOfferRowUpdatedAt: myHelpOfferUpdatedAt ?? beacon.updatedAt,
      authorCoordinationUpdatedAt: null,
    );
    return _deriveHelpOffered(row: row);
  }
  return _deriveAuthored(beacon: beacon);
}
