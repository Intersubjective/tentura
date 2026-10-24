import 'package:tentura/consts.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

typedef ConstellationResolvedField = ({
  ConstellationPathResolution paths,
  Set<String> keptPeerIds,
  Set<String> droppedHolderIds,
  bool capped,
});

ConstellationResolvedField resolveAndCapConstellation({
  required String egoId,
  required Iterable<String> visiblePeerIds,
  required Set<String> holderIds,
  required Iterable<ConstellationEdgeRef> edges,
  required int cap,
  int maxHops = 3,
  Set<String> budgetExemptPeerIds = const {},
  bool fieldMembershipV2Enabled = kFieldMembershipV2Enabled,
  Set<String> ownTaggedPeerIds = const {},
  Set<String> directContactPeerIds = const {},
  Set<String> bondOrTemporaryPeerIds = const {},
}) {
  final paths = resolveConstellationPaths(
    egoId: egoId,
    visiblePeerIds: visiblePeerIds.toSet(),
    holderIds: holderIds,
    edges: edges,
    maxHops: maxHops,
  );

  final keptPeerIds = <String>{};
  final droppedHolderIds = <String>{};
  var remaining = cap;

  for (final exempt in budgetExemptPeerIds) {
    if (exempt == egoId) {
      continue;
    }
    if (paths.keep.contains(exempt) || paths.ring.contains(exempt)) {
      keptPeerIds.add(exempt);
    }
  }

  // With the gate on: own-tagged, direct contacts, bond/temporary people,
  // then shallower chains, then id. Gate off: id order only.
  int rank(String id) {
    if (!fieldMembershipV2Enabled) return 0;
    if (ownTaggedPeerIds.contains(id)) return 0;
    if (directContactPeerIds.contains(id)) return 1;
    if (bondOrTemporaryPeerIds.contains(id)) return 2;
    return 3;
  }

  int depth(String id) => fieldMembershipV2Enabled
      ? _ancestorChain(holder: id, parent: paths.parent, egoId: egoId).length
      : 0;

  int byPriority(String a, String b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final byDepth = depth(a).compareTo(depth(b));
    return byDepth != 0 ? byDepth : a.compareTo(b);
  }

  final attributedSorted = paths.attributed.toList()..sort(byPriority);
  for (final holder in attributedSorted) {
    final chain = _ancestorChain(
      holder: holder,
      parent: paths.parent,
      egoId: egoId,
    );
    final missing = chain.difference(keptPeerIds);
    if (missing.isEmpty) {
      continue;
    }
    final chargeable = missing.difference(budgetExemptPeerIds);
    final free = missing.intersection(budgetExemptPeerIds);
    keptPeerIds.addAll(free);
    if (chargeable.isEmpty) {
      continue;
    }
    if (chargeable.length <= remaining) {
      keptPeerIds.addAll(chargeable);
      remaining -= chargeable.length;
    } else {
      droppedHolderIds.add(holder);
    }
  }

  final ringSorted = paths.ring.toList()..sort(byPriority);
  for (final holder in ringSorted) {
    if (remaining <= 0 && !budgetExemptPeerIds.contains(holder)) {
      break;
    }
    if (!keptPeerIds.contains(holder)) {
      keptPeerIds.add(holder);
      if (!budgetExemptPeerIds.contains(holder)) {
        remaining -= 1;
      }
    }
  }

  final capped = paths.attributed
      .union(paths.ring)
      .difference(keptPeerIds)
      .isNotEmpty;

  return (
    paths: paths,
    keptPeerIds: keptPeerIds,
    droppedHolderIds: droppedHolderIds,
    capped: capped,
  );
}

Set<String> _ancestorChain({
  required String holder,
  required Map<String, String> parent,
  required String egoId,
}) {
  final chain = <String>{holder};
  var current = holder;
  while (parent.containsKey(current)) {
    final ancestor = parent[current]!;
    if (ancestor == egoId) {
      break;
    }
    chain.add(ancestor);
    current = ancestor;
  }
  return chain;
}
