import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart'
    show BeaconFactCardStatusBits;

/// Active pinned facts, newest first.
List<BeaconFactCard> activePinnedFacts(List<BeaconFactCard> factCards) {
  return factCards
      .where((f) => f.status != BeaconFactCardStatusBits.removed)
      .toList(growable: false)
    ..sort((a, b) {
      final ta = a.updatedAt ?? a.createdAt;
      final tb = b.updatedAt ?? b.createdAt;
      return tb.compareTo(ta);
    });
}

DateTime factTimestamp(BeaconFactCard fact) => fact.updatedAt ?? fact.createdAt;

DateTime? activePinnedFactsMaxTimestamp(List<BeaconFactCard> factCards) {
  DateTime? maxTs;
  for (final fact in activePinnedFacts(factCards)) {
    final ts = factTimestamp(fact);
    if (maxTs == null || ts.isAfter(maxTs)) {
      maxTs = ts;
    }
  }
  return maxTs;
}

/// Facts newer than [seenAt] that the viewer did not pin.
///
/// A null [seenAt] means the cursor is not baselined yet — show total only.
int pinnedFactsNewCount({
  required List<BeaconFactCard> facts,
  required DateTime? seenAt,
  required String viewerUserId,
}) {
  if (seenAt == null) return 0;
  var n = 0;
  for (final fact in activePinnedFacts(facts)) {
    if (fact.pinnedBy == viewerUserId) continue;
    if (factTimestamp(fact).isAfter(seenAt)) n++;
  }
  return n;
}

bool pinnedFactIsNew({
  required BeaconFactCard fact,
  required DateTime? seenAt,
  required String viewerUserId,
}) {
  if (seenAt == null) return false;
  if (fact.pinnedBy == viewerUserId) return false;
  if (fact.status == BeaconFactCardStatusBits.removed) return false;
  return factTimestamp(fact).isAfter(seenAt);
}

/// Text stored on a pinned fact. Empty body with zero attachments is `''`
/// so the discussion pin path can refuse an empty message.
String pinFactTextForPin({
  required String body,
  required int attachmentCount,
  required List<String> attachmentFileNames,
  required String attachmentFallback,
}) {
  final trimmed = body.trim();
  if (trimmed.isNotEmpty) return trimmed;
  if (attachmentCount == 0) return '';
  final names = [
    for (final n in attachmentFileNames)
      if (n.trim().isNotEmpty) n.trim(),
  ];
  if (names.isEmpty) return attachmentFallback;
  const maxNames = 3;
  if (names.length <= maxNames) return names.join(', ');
  return '${names.take(maxNames).join(', ')}…';
}
