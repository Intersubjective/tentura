import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart'
    show BeaconFactCardStatusBits;

/// Active pinned facts for the operational strip, newest first.
List<BeaconFactCard> pinnedFactsForStrip(List<BeaconFactCard> factCards) {
  return factCards
      .where((f) => f.status != BeaconFactCardStatusBits.removed)
      .toList(growable: false)
    ..sort((a, b) {
      final ta = a.updatedAt ?? a.createdAt;
      final tb = b.updatedAt ?? b.createdAt;
      return tb.compareTo(ta);
    });
}
