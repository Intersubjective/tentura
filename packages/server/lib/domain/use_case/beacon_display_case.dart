import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/coordination/derive_beacon_display_status.dart';
import 'package:tentura_server/domain/entity/beacon_display_status.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/pair_block_query_port.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class BeaconDisplayCase extends UseCaseBase {
  BeaconDisplayCase(
    this._helpOfferRepository,
    this._coordinationRepository,
    this._closureRepository,
    this._beaconRoomRepository,
    this._guard,
    this._commitmentQueryCase,
    this._blocks, {
    required super.env,
    required super.logger,
  });

  final HelpOfferRepositoryPort _helpOfferRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final ClosureRepositoryPort _closureRepository;
  final BeaconRoomRepositoryPort _beaconRoomRepository;
  final BeaconAccessGuard _guard;
  final CommitmentQueryCase _commitmentQueryCase;
  final PairBlockQueryPort _blocks;

  Future<List<BeaconDisplayStatus>> displayStatuses({
    required List<String> beaconIds,
    required String viewerId,
  }) async {
    if (beaconIds.isEmpty) return const [];

    // #747 — every per-Request fact is one batched read for the whole list,
    // never a read per card.
    final readable = await _guard.readableContentIds(
      beaconIds: beaconIds,
      viewerId: viewerId,
    );
    final facts = await _beaconRoomRepository.roomViewerFacts(
      readable,
      viewerUserId: viewerId,
    );
    final requests = [
      for (final beaconId in beaconIds)
        if (facts[beaconId] case final request?
            when readable.contains(beaconId) &&
                request.kind == BeaconKind.request)
          request,
    ];
    if (requests.isEmpty) return const [];
    final requestIds = {for (final r in requests) r.beaconId};

    final offersByBeacon = await _helpOfferRepository.fetchByBeaconIds(
      requestIds,
    );
    final coordsByBeacon = await _coordinationRepository
        .coordinationResponseTypesByBeaconIds(requestIds);
    final liveEpochs = await _closureRepository.liveEpochsByBeaconIds({
      for (final r in requests)
        if (r.status == BeaconStatus.reviewOpen) r.beaconId,
    });

    // Same rule as the `beacon_admitted_helper` view the client counts
    // (m0210): admitted, not the author, not a Post addressee kept after a
    // conversion — an addressee is not a helper (B075) — and not hidden
    // from the author by a block either way (`block_hides`).
    final participantsByBeacon = await _beaconRoomRepository
        .listParticipantsByBeaconIds(requestIds);
    final admittedHelpersByBeacon = {
      for (final r in requests)
        r.beaconId: {
          for (final p
              in participantsByBeacon[r.beaconId] ??
                  const <BeaconParticipantRecord>[])
            if (p.roomAccess == RoomAccessBits.admitted &&
                p.role != BeaconParticipantRoleBits.addressee &&
                p.userId != r.authorId)
              p.userId,
        },
    };
    final blockUsers = {
      for (final r in requests)
        if (admittedHelpersByBeacon[r.beaconId]!.isNotEmpty) ...{
          ?r.authorId,
          ...admittedHelpersByBeacon[r.beaconId]!,
        },
    };
    final blocked = blockUsers.isEmpty
        ? const <(String, String)>{}
        : await _blocks.blockedPairsAmong(userIds: blockUsers);

    final authorCoordinationIds = {
      for (final r in requests)
        if (r.authorId == viewerId) r.beaconId,
    };
    final everAckByBeacon = await _commitmentQueryCase
        .everAcknowledgedUserIdsByBeaconIds(authorCoordinationIds);

    final out = <BeaconDisplayStatus>[];
    for (final beacon in requests) {
      final beaconId = beacon.beaconId;
      final authorId = beacon.authorId;
      final tier =
          authorId == viewerId || beacon.isSteward || beacon.isParticipant
          ? BeaconDisplayTier.coordination
          : BeaconDisplayTier.public;

      final offers = offersByBeacon[beaconId] ?? const <HelpOfferEntity>[];
      final activeOffers = offers.where((o) => o.status == 0).length;
      final coords = coordsByBeacon[beaconId] ?? const <String, int>{};

      final hasUnreviewed =
          beacon.status.isOpenFamily &&
          offers.any(
            (o) =>
                o.status == 0 && o.offerKind == 0 && coords[o.userId] == null,
          );

      final admittedHelpers = admittedHelpersByBeacon[beaconId]!
        ..removeWhere(
          (helperId) =>
              blocked.contains((authorId, helperId)) ||
              blocked.contains((helperId, authorId)),
        );
      final admittedHelperCount = admittedHelpers.length;

      final derived = deriveBeaconDisplayStatus(
        BeaconDisplayStatusInput(
          status: beacon.status,
          tier: tier,
          helpOfferCount: activeOffers,
          admittedHelperCount: admittedHelperCount,
          hasUnreviewedOffers: hasUnreviewed,
          reviewClosesAt: liveEpochs[beaconId]?.closesAt,
          updatedAt: beacon.updatedAt,
        ),
      );

      var canCancel = false;
      var canDelete = false;
      var everAcknowledgedCommitterCount = 0;
      if (authorCoordinationIds.contains(beaconId)) {
        final everAck = everAckByBeacon[beaconId] ?? const <String>{};
        canCancel = beacon.status.isOpenFamily && everAck.isEmpty;
        canDelete = beacon.status == BeaconStatus.draft || everAck.isEmpty;
        everAcknowledgedCommitterCount = everAck.length;
      }

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
          canCancel: canCancel,
          canDelete: canDelete,
          everAcknowledgedCommitterCount: everAcknowledgedCommitterCount,
        ),
      );
    }
    return out;
  }
}
