import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/coordination/derive_beacon_display_status.dart';
import 'package:tentura_server/domain/entity/beacon_display_status.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class BeaconDisplayCase extends UseCaseBase {
  BeaconDisplayCase(
    this._beaconRepository,
    this._helpOfferRepository,
    this._coordinationRepository,
    this._evaluationRepository,
    this._beaconRoomRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final EvaluationRepositoryPort _evaluationRepository;
  final BeaconRoomRepositoryPort _beaconRoomRepository;

  Future<List<BeaconDisplayStatus>> displayStatuses({
    required List<String> beaconIds,
    required String viewerId,
  }) async {
    if (beaconIds.isEmpty) return const [];

    final out = <BeaconDisplayStatus>[];
    for (final beaconId in beaconIds) {
      final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
      final tier = await _resolveTier(
        beaconId: beaconId,
        viewerId: viewerId,
        authorId: beacon.author.id,
      );

      final offers = await _helpOfferRepository.fetchByBeaconId(beaconId);
      final activeOffers = offers.where((o) => o.status == 0).length;
      final coords = await _coordinationRepository
          .coordinationResponseTypeByOfferUserId(beaconId);

      final hasUnreviewed = beacon.status == BeaconStatus.open &&
          activeOffers > 0 &&
          offers.any((o) => o.status == 0 && coords[o.userId] == null);

      DateTime? reviewClosesAt;
      int? reviewWindowStatus;
      if (beacon.status == BeaconStatus.reviewOpen) {
        final w = await _evaluationRepository.getReviewWindow(beaconId);
        reviewClosesAt = w?.closesAt;
        reviewWindowStatus = w?.status;
      }

      final derived = deriveBeaconDisplayStatus(
        BeaconDisplayStatusInput(
          status: beacon.status,
          tier: tier,
          helpOfferCount: activeOffers,
          hasUnreviewedOffers: hasUnreviewed,
          reviewClosesAt: reviewClosesAt,
          reviewWindowStatus: reviewWindowStatus,
          updatedAt: beacon.updatedAt,
        ),
      );

      out.add(
        BeaconDisplayStatus(
          beaconId: beaconId,
          status: beacon.status,
          phase: derived.phase,
          suggestedAction: derived.suggestedAction,
          slot2Kind: derived.slot2Kind,
          tier: tier,
          reviewClosesAt: derived.reviewClosesAt,
          lastActivityAt: derived.lastActivityAt,
          lifecycleEndedAt: derived.lifecycleEndedAt,
        ),
      );
    }
    return out;
  }

  Future<BeaconDisplayTier> _resolveTier({
    required String beaconId,
    required String viewerId,
    required String authorId,
  }) async {
    if (viewerId == authorId) return BeaconDisplayTier.coordination;
    final steward = await _beaconRoomRepository.isBeaconSteward(
      beaconId: beaconId,
      userId: viewerId,
    );
    if (steward) return BeaconDisplayTier.coordination;
    final participant = await _beaconRoomRepository.findParticipant(
      beaconId: beaconId,
      userId: viewerId,
    );
    return participant != null
        ? BeaconDisplayTier.coordination
        : BeaconDisplayTier.public;
  }
}
