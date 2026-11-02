import '../entity/forward_edge_entity.dart';
import '../entity/help_offer_entity.dart';
import '../entity/help_offer_admission_event.dart';

/// The source records used by the shared involvement projection.
typedef BeaconInvolvementRecords = ({
  List<ForwardEdgeEntity> edges,
  List<HelpOfferEntity> helpOffers,
  Map<String, HelpOfferAdmissionEvent> latestAdmissions,
  List<String> rejectedIds,
  List<String> watchingIds,
  List<String> onwardForwarderIds,
});

abstract interface class BeaconInvolvementReadPort {
  int get maxBatchSize;

  /// One admitted snapshot; unknown and unreadable ids are omitted.
  Future<Map<String, BeaconInvolvementRecords>> fetchReadableBatch({
    required List<String> beaconIds,
    required String viewerId,
  });
}
