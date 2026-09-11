import 'constellation_path_resolution.dart';

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

  final attributedSorted = paths.attributed.toList()..sort();
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

  final ringSorted = paths.ring.toList()..sort();
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
