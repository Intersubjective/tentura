import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';

import 'derive_my_work_card_attention.dart';
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
    this.nestingDepth = const {},
  });

  final MyWorkDeskSection section;
  final List<MyWorkCardViewModel> cards;

  /// #487 — how deep each card sits under a parent Request listed in the
  /// same section (1 = child, 2 = grandchild, …); absent = top level.
  final Map<String, int> nestingDepth;

  int depthOf(String beaconId) => nestingDepth[beaconId] ?? 0;
}

/// #487 — lists each child Request right under its parent when both are in
/// [ordered] (one section), so a child no longer reads as an unrelated
/// sibling. A family keeps the place of its highest-ranked member, so a busy
/// child still lifts its family up the "Recent" order (#525); inside a family,
/// siblings keep the order of their own highest-ranked descendant. A child
/// whose parent is not in [ordered] stays where the sort put it (its card
/// still says "Part of: …").
MyWorkDeskSectionGroup nestMyWorkChildCards({
  required MyWorkDeskSection section,
  required List<MyWorkCardViewModel> ordered,
}) {
  final indexById = <String, int>{
    for (var i = 0; i < ordered.length; i++) ordered[i].beaconId: i,
  };
  String? listedParent(MyWorkCardViewModel card) {
    final p = card.parentBeaconId;
    return p.isNotEmpty && p != card.beaconId && indexById.containsKey(p)
        ? p
        : null;
  }

  final byId = {for (final c in ordered) c.beaconId: c};
  // Parentage never changes after creation, so a cycle cannot happen; if one
  // ever did, its members are treated as top level instead of vanishing.
  final parentOf = <String, String?>{};
  for (final card in ordered) {
    final seen = <String>{card.beaconId};
    var cursor = listedParent(card);
    var cyclic = false;
    while (cursor != null) {
      if (!seen.add(cursor)) {
        cyclic = true;
        break;
      }
      cursor = listedParent(byId[cursor]!);
    }
    parentOf[card.beaconId] = cyclic ? null : listedParent(card);
  }
  if (parentOf.values.every((p) => p == null)) {
    return MyWorkDeskSectionGroup(section: section, cards: ordered);
  }

  final children = <String, List<String>>{};
  for (final card in ordered) {
    final p = parentOf[card.beaconId];
    if (p != null) (children[p] ??= []).add(card.beaconId);
  }
  final rank = <String, int>{};
  int subtreeRank(String id) => rank[id] ??= [
    indexById[id]!,
    for (final c in children[id] ?? const <String>[]) subtreeRank(c),
  ].reduce((a, b) => a < b ? a : b);
  int byRank(String a, String b) => subtreeRank(a).compareTo(subtreeRank(b));

  final out = <MyWorkCardViewModel>[];
  final depth = <String, int>{};
  void emit(String id, int level) {
    out.add(byId[id]!);
    if (level > 0) depth[id] = level;
    final kids = [...?children[id]]..sort(byRank);
    for (final kid in kids) {
      emit(kid, level + 1);
    }
  }

  final roots = [
    for (final card in ordered)
      if (parentOf[card.beaconId] == null) card.beaconId,
  ]..sort(byRank);
  for (final root in roots) {
    emit(root, 0);
  }
  return MyWorkDeskSectionGroup(
    section: section,
    cards: out,
    nestingDepth: depth,
  );
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
/// order within each section is preserved from that list, except that child
/// Requests are listed under their parent ([nestMyWorkChildCards], #487).
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
      nestMyWorkChildCards(
        section: MyWorkDeskSection.unlabeled,
        ordered: List<MyWorkCardViewModel>.from(cards),
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
      nestMyWorkChildCards(
        section: MyWorkDeskSection.needsYou,
        ordered: needsYou,
      ),
    );
  }
  if (inProgress.isNotEmpty) {
    groups.add(
      nestMyWorkChildCards(
        section: MyWorkDeskSection.inProgress,
        ordered: inProgress,
      ),
    );
  }
  if (finished.isNotEmpty) {
    groups.add(
      nestMyWorkChildCards(
        section: MyWorkDeskSection.finished,
        ordered: finished,
      ),
    );
  }
  return groups;
}

/// The first card, in the order [sections] list them, that carries a live
/// obligation or a dot (`docs/features/request-attention.md` §6) — the same
/// facts the card's indicators show. Null when no card needs the viewer.
MyWorkCardViewModel? firstMyWorkCardNeedingAttention({
  required List<MyWorkDeskSectionGroup> sections,
  required Map<String, MyWorkBeaconAttention> attentionByBeacon,
}) {
  for (final group in sections) {
    for (final card in group.cards) {
      final view = myWorkCardAttentionView(
        beaconId: card.beaconId,
        attention: attentionByBeacon[card.beaconId],
        viewerArchived: card.viewerArchived,
      );
      if (requestHasMyDeskAttention(view.facts)) return card;
    }
  }
  return null;
}
