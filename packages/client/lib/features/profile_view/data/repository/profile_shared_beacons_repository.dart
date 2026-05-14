import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';

import '../gql/_g/profile_shared_beacons_fetch.req.gql.dart';

enum TargetBeaconReaction { helpOffered, onward, watching, rejected, none }

typedef ProfileForwardedBeaconEntry = ({
  String edgeId,
  Beacon beacon,
  String note,
  bool recipientRejected,
  String recipientRejectionMessage,
  TargetBeaconReaction reaction,
});

typedef ProfileCoHelpOfferedEntry = ({
  Beacon beacon,
  String targetOfferHelpMessage,
  String? targetHelpType,
});

typedef ProfileSharedBeaconsData = ({
  List<ProfileForwardedBeaconEntry> forwarded,
  List<ProfileCoHelpOfferedEntry> coHelpOffered,
});

@Singleton(env: [Environment.dev, Environment.prod])
class ProfileSharedBeaconsRepository {
  ProfileSharedBeaconsRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'ProfileSharedBeacons';

  Future<ProfileSharedBeaconsData> fetch({
    required String meId,
    required String targetId,
  }) async {
    final results = await Future.wait([
      _fetchForwarded(meId: meId, targetId: targetId),
      _fetchCoHelpOffered(meId: meId, targetId: targetId),
    ]);
    return (
      forwarded: results[0] as List<ProfileForwardedBeaconEntry>,
      coHelpOffered: results[1] as List<ProfileCoHelpOfferedEntry>,
    );
  }

  Future<List<ProfileForwardedBeaconEntry>> _fetchForwarded({
    required String meId,
    required String targetId,
  }) =>
      _remoteApiService
          .request(
            GProfileForwardedToUserReq(
              (b) => b.vars
                ..meId = meId
                ..targetId = targetId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .beacon_forward_edge
                .map(
                  (e) => (
                    edgeId: e.id,
                    beacon: BeaconModel(e.beacon).toEntity(),
                    note: e.note,
                    recipientRejected: e.recipient_rejected,
                    recipientRejectionMessage: e.recipient_rejection_message,
                    reaction: _deriveForwardedReaction(
                      recipientRejected: e.recipient_rejected,
                      hasTargetHelpOffer: e.beacon.help_offers.isNotEmpty,
                      hasTargetOnwardEdge: e.beacon.forward_edges.isNotEmpty,
                    ),
                  ),
                )
                .toList(),
          );

  Future<List<ProfileCoHelpOfferedEntry>> _fetchCoHelpOffered({
    required String meId,
    required String targetId,
  }) =>
      _remoteApiService
          .request(
            GProfileCoCommittedReq(
              (b) => b.vars
                ..meId = meId
                ..targetId = targetId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .beacon
                .map(
                  (e) => (
                    beacon: BeaconModel(e).toEntity(),
                    targetOfferHelpMessage: e.help_offers.firstOrNull?.message ?? '',
                    targetHelpType: e.help_offers.firstOrNull?.help_type,
                  ),
                )
                .toList(),
          );

  static TargetBeaconReaction _deriveForwardedReaction({
    required bool recipientRejected,
    required bool hasTargetHelpOffer,
    required bool hasTargetOnwardEdge,
  }) {
    if (recipientRejected) return TargetBeaconReaction.rejected;
    if (hasTargetHelpOffer) return TargetBeaconReaction.helpOffered;
    if (hasTargetOnwardEdge) return TargetBeaconReaction.onward;
    return TargetBeaconReaction.none;
  }
}
