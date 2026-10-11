import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/entity/author_invite.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

/// Arch §5.3: the one implementation of "admit with both confirmations".
///
/// The helper's confirmation is their active offer; the author's is
/// [admitWithConfirmations]'s `confirmingAuthorId` (the author or a steward
/// accepting the offer, or the inviter of an accepted invite). Two entry
/// points share it: `CoordinationCase.acceptHelpOffer` (the confirming author
/// is the actor) and invite accept (the helper is the actor).
///
/// It runs inside the caller's single mutating unit for `actorId`. The
/// confirming author is recorded as data only; no step opens a nested mutating
/// unit for another actor. Callers own pre-checks, locks before step (c), and
/// idempotency: the admission event is append-only, so a second call appends a
/// second `accept`.
@Singleton(order: 2)
final class AdmissionOperation {
  AdmissionOperation(
    this._helpOfferRepository,
    this._coordinationRepository,
    this._commitmentRepository, [
    this._closureCase,
    this._attentionSystemSettlement,
  ]);

  /// DI registration. Non-null dependencies let injectable order this
  /// singleton after them (it does not order on nullable parameters).
  @factoryMethod
  factory AdmissionOperation.inject(
    HelpOfferRepositoryPort helpOfferRepository,
    CoordinationRepositoryPort coordinationRepository,
    CommitmentRepositoryPort commitmentRepository,
    ClosureCase closureCase,
    AttentionSystemSettlementPort attentionSystemSettlement,
  ) => AdmissionOperation(
    helpOfferRepository,
    coordinationRepository,
    commitmentRepository,
    closureCase,
    attentionSystemSettlement,
  );

  final HelpOfferRepositoryPort _helpOfferRepository;
  final CoordinationRepositoryPort _coordinationRepository;
  final CommitmentRepositoryPort _commitmentRepository;
  final ClosureCase? _closureCase;
  final AttentionSystemSettlementPort? _attentionSystemSettlement;

  /// Admits [helperId] into [beacon] with [confirmingAuthorId] as the author
  /// confirmation, and returns the beacon status after admission.
  ///
  /// [attention] builds the intent the caller emits (`offerAccepted` for an
  /// accepted offer); it is recorded on [transaction].
  ///
  /// [invite] is the author invite being accepted, when the admission is an
  /// invite accept; its recorded Post arrival drives the approval credit
  /// (budding C7). An ordinary offer accept passes none.
  Future<({BeaconStatus status, DateTime? statusChangedAt})>
  admitWithConfirmations({
    required BeaconEntity beacon,
    required String helperId,
    required String confirmingAuthorId,
    required String actorId,
    required AttentionTransaction transaction,
    required Future<AttentionDispatchIntent> Function() attention,
    AuthorInvite? invite,
  }) async {
    final beaconId = beacon.id;

    // (a) The helper's confirmation: an active offer and its `offered` event.
    final active = await _helpOfferRepository.fetchByBeaconId(beaconId);
    if (!active.any((o) => o.userId == helperId)) {
      await _helpOfferRepository.upsert(
        beaconId: beaconId,
        userId: helperId,
        offerKind: beacon.status == BeaconStatus.enoughHelp ? 1 : 0,
      );
      await _commitmentRepository.record(
        beaconId: beaconId,
        userId: helperId,
        actorUserId: helperId,
        kind: CommitmentEventKind.offered,
        mutatingUserId: actorId,
      );
    }

    // (b) coordination `useful`, (c) room admission, (d) admission event.
    final snapshot = await _coordinationRepository.acceptHelpOffer(
      beaconId: beaconId,
      offerUserId: helperId,
      confirmingAuthorId: confirmingAuthorId,
      actorUserId: actorId,
    );

    // (e) `acknowledged` on transition, then the closure membership.
    final events = await _commitmentRepository.eventsForPair(
      beaconId: beaconId,
      userId: helperId,
    );
    if (currentStakeState(events) != CommitmentStakeState.acknowledged) {
      await _closureCase?.lockRequest(beaconId);
      await _commitmentRepository.record(
        beaconId: beaconId,
        userId: helperId,
        actorUserId: confirmingAuthorId,
        kind: CommitmentEventKind.acknowledged,
        mutatingUserId: actorId,
      );
      await _closureCase?.applyMembershipEvent(beaconId, helperId);
    }

    // (f) Approval credit; the approver is the Request author, not a steward.
    await _closureCase?.recordApprovalEdge(
      beaconId: beaconId,
      helperId: helperId,
      authorId: beacon.author.id,
      invite: invite,
    );

    // (h) The caller's attention intent, then (g) the author's obligation.
    // This order is the pre-A2 `acceptHelpOffer` order, kept unchanged.
    await transaction.record(await attention());
    await _attentionSystemSettlement?.settleAuthorHelpOfferSubmitted(
      beaconId: beaconId,
      authorAccountId: beacon.author.id,
      helpOffererUserId: helperId,
    );
    return snapshot;
  }
}
