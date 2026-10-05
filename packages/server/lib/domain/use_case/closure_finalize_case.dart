import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/episode_settlement.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/closure/settlement_params.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/trust_ledger_port.dart';
import 'package:tentura_server/domain/trust/forward/forward_routing_settlement.dart';
import 'package:tentura_server/domain/trust/ledger_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_kind.dart';

import 'plan_attention_case.dart';
import '_use_case_base.dart';
import 'beacon_lifecycle_effects_case.dart';
import 'trust_publisher_case.dart';

/// A14: finalizes one closure epoch (Arch §5.9).
///
/// Runs inside the caller's transaction (`closeNow`, or the sweep's unit of
/// work) with the per-request lock already held.
@Singleton(as: ClosureFinalizerPort, order: 1)
final class ClosureFinalizeCase extends UseCaseBase
    implements ClosureFinalizerPort {
  ClosureFinalizeCase({
    // Callers own the transaction; kept so the wiring documents that finalize
    // is always a mutating unit of work.
    // ignore: avoid_unused_constructor_parameters
    required MutatingUnitOfWorkPort unitOfWork,
    required ClosureRepositoryPort closureRepository,
    required BeaconRepositoryPort beaconRepository,
    required TrustLedgerPort trustLedger,
    required BeaconLifecycleEffectsCase lifecycleEffects,
    required AttentionSystemSettlementPort attentionSystemSettlement,
    required TrustPublisherCase trustPublisher,
    ClosureReceiptsPort receipts = const NoopClosureReceipts(),
    this._planAttention,
    required super.env,
    required super.logger,
  }) : _repo = closureRepository,
       _beacons = beaconRepository,
       _ledger = trustLedger,
       _lifecycleEffects = lifecycleEffects,
       _settlement = attentionSystemSettlement,
       _publisher = trustPublisher,
       _receipts = receipts;

  final ClosureRepositoryPort _repo;
  final BeaconRepositoryPort _beacons;
  final TrustLedgerPort _ledger;
  final BeaconLifecycleEffectsCase _lifecycleEffects;
  final AttentionSystemSettlementPort _settlement;
  final TrustPublisherCase _publisher;
  final ClosureReceiptsPort _receipts;
  final PlanAttentionCase? _planAttention;

  static const _params = SettlementParams();

  @override
  Future<void> finalize({
    required String beaconId,
    required int epoch,
    required FinalizeReason reason,
  }) async {
    final now = DateTime.timestamp();
    final live = await _repo.liveEpoch(beaconId);
    if (live == null || live.epoch != epoch) return;
    if (reason == FinalizeReason.expired && live.closesAt.isAfter(now)) return;

    final beacon = await _beacons.getBeaconById(beaconId: beaconId);
    final authorId = beacon.author.id;
    final closedByAuthor = reason == FinalizeReason.authorCloseNow;

    await _repo.setEpochStatus(
      beaconId: beaconId,
      epoch: epoch,
      status: ClosureEpochStatus.finalized,
      finalizedAt: now,
      finalizeReason: reason.dbValue,
      settlementVersion: settlementVersion,
      settlementParams: _params.toJson(),
    );
    await _beacons.recordBeaconStatusTransition(
      beaconId: beaconId,
      fromStatus: beacon.status,
      toStatus: BeaconStatus.closed,
      reason: closedByAuthor
          ? BeaconLifecycleChangeReason.authorCloseNow
          : BeaconLifecycleChangeReason.closureExpired,
      actorId: closedByAuthor ? authorId : null,
    );
    await _lifecycleEffects.recordEligibleSourceTransition(
      sourceBeaconId: beaconId,
      fromStatus: beacon.status,
      toStatus: BeaconStatus.closed,
      occurredAt: now,
      actorUserId: closedByAuthor ? authorId : null,
      reason: closedByAuthor
          ? BeaconStatusTransitionReason.authorCloseNow
          : BeaconStatusTransitionReason.closureExpired,
    );
    await _settlement.supersedeAuthorHelpOfferObligationsOnBeaconClose(
      beaconId,
    );
    // A closed Request owes no plan step and no «Понятно» (plan P21).
    await _planAttention?.onRequestStatusChanged(beaconId: beaconId);

    final members = await _repo.members(beaconId: beaconId, epoch: epoch);
    final outcomes = {
      for (final o in await _repo.outcomes(beaconId)) o.helperId: o.outcome,
    };
    final split = await _repo.split(beaconId);
    final drafts = _targetsByVoter(
      await _repo.supports(
        beaconId: beaconId,
        version: ClosureSupportVersion.draft,
      ),
    );
    final committed = _targetsByVoter(
      await _repo.supports(
        beaconId: beaconId,
        version: ClosureSupportVersion.committed,
      ),
    );
    final committedVoters = {
      for (final c in await _repo.commits(beaconId)) c.voterId,
    };

    final settlement = EpisodeSettlement().settle(
      SettlementInput(
        members: [
          for (final m in members)
            SettlementMember(
              userId: m.userId,
              outcome: outcomes[m.userId],
              voter: _isVoter(m),
              support: committedVoters.contains(m.userId)
                  ? committed[m.userId] ?? const {}
                  : null,
            ),
        ],
        authorSplit: split.isEmpty ? null : split,
        params: _params,
      ),
    );

    await _repo.insertResults(
      beaconId: beaconId,
      epoch: epoch,
      rows: [
        for (final m in members)
          ClosureResultInsert(
            userId: m.userId,
            outcome: outcomes[m.userId] ?? ClosureOutcome.cantJudge,
            band: settlement.band[m.userId]!,
            draftFlag: _draftFlag(
              hasCommit: committedVoters.contains(m.userId),
              draft: drafts[m.userId],
              committed: committed[m.userId],
            ),
            helped: settlement.helped[m.userId]!,
          ),
      ],
    );

    final evidence = <LedgerEvidence>[
      for (final m in members)
        if (settlement.helped[m.userId]! > 0)
          LedgerEvidence(
            subjectId: authorId,
            objectId: m.userId,
            kind: TrustEvidenceKind.helped,
            count: settlement.helped[m.userId]!,
            sourceKey: 'closure:$beaconId:$epoch:helped:${m.userId}',
            beaconId: beaconId,
            epoch: epoch,
            occurredAt: now,
          ),
      ...await _routedEvidence(
        beaconId: beaconId,
        epoch: epoch,
        authorId: authorId,
        members: members,
      ),
      for (final mark in await _repo.marks(beaconId))
        if (mark.markerId != mark.targetId)
          LedgerEvidence(
            subjectId: mark.markerId,
            objectId: mark.targetId,
            kind: TrustEvidenceKind.marked,
            count: 1,
            sourceKey:
                'closure:$beaconId:$epoch:mark:${mark.markerId}:${mark.targetId}',
            beaconId: beaconId,
            epoch: epoch,
            occurredAt: now,
          ),
      ..._workedWithAuthor(
        beaconId: beaconId,
        epoch: epoch,
        authorId: authorId,
        members: members,
        occurredAt: now,
      ),
      ..._supportedColleague(
        beaconId: beaconId,
        epoch: epoch,
        members: members,
        committed: committed,
        committedVoters: committedVoters,
        occurredAt: now,
      ),
    ];
    await _ledger.record(evidence);

    await _repo.insertCloseAcknowledgements(
      beaconId: beaconId,
      authorId: authorId,
      helperIds: settlement.closeAck,
    );

    final story = await _repo.story(beaconId);
    if (story != null && story.isNotEmpty) {
      await _repo.postStoryMessage(beaconId: beaconId, body: story);
    }

    await _receipts.finalized(beaconId, epoch);
    _publisher.nudge();
  }

  Future<List<LedgerEvidence>> _routedEvidence({
    required String beaconId,
    required int epoch,
    required String authorId,
    required List<ClosureMemberRow> members,
  }) async {
    final source = await _repo.routingSource(beaconId);
    final seedOfferAt = <String, DateTime>{
      for (final m in members)
        if (m.departure != Departure.voluntary &&
            source.offerAt[m.userId] != null)
          m.userId: source.offerAt[m.userId]!,
    };
    if (seedOfferAt.isEmpty) return const [];
    return ForwardRoutingSettlement().settle(
      RoutingInput(
        beaconId: beaconId,
        epoch: epoch,
        authorId: authorId,
        seedOfferAt: seedOfferAt,
        edges: source.edges,
        attributionByBatch: source.attributionByBatch,
        budget: _params.rho * _params.B,
      ),
    );
  }

  /// U58 (Arch §5.9a): every member still present at finalize points at the
  /// author, independent of outcome and split.
  List<LedgerEvidence> _workedWithAuthor({
    required String beaconId,
    required int epoch,
    required String authorId,
    required List<ClosureMemberRow> members,
    required DateTime occurredAt,
  }) {
    final present = members.where((m) => m.departure == null).toList();
    if (present.isEmpty) return const [];
    final count = 1 / sqrt(present.length);
    return [
      for (final m in present)
        LedgerEvidence(
          subjectId: m.userId,
          objectId: authorId,
          kind: TrustEvidenceKind.workedWithAuthor,
          count: count,
          sourceKey: 'closure:$beaconId:$epoch:author_edge:${m.userId}',
          beaconId: beaconId,
          epoch: epoch,
          occurredAt: occurredAt,
        ),
    ];
  }

  /// U59 (Arch §5.9b): a voter's committed support, unless it covers every
  /// other member (stored as silence, U56).
  List<LedgerEvidence> _supportedColleague({
    required String beaconId,
    required int epoch,
    required List<ClosureMemberRow> members,
    required Map<String, Set<String>> committed,
    required Set<String> committedVoters,
    required DateTime occurredAt,
  }) {
    if (members.length < 3) return const [];
    final ids = {for (final m in members) m.userId};
    final evidence = <LedgerEvidence>[];
    for (final m in members) {
      if (!_isVoter(m) || !committedVoters.contains(m.userId)) continue;
      final others = ids.difference({m.userId});
      final u = (committed[m.userId] ?? const <String>{}).intersection(others);
      if (u.isEmpty || u.length == others.length) continue;
      final count = 1 / sqrt(u.length);
      for (final j in u.toList()..sort()) {
        evidence.add(
          LedgerEvidence(
            subjectId: m.userId,
            objectId: j,
            kind: TrustEvidenceKind.supportedColleague,
            count: count,
            sourceKey: 'closure:$beaconId:$epoch:support_edge:${m.userId}:$j',
            beaconId: beaconId,
            epoch: epoch,
            occurredAt: occurredAt,
          ),
        );
      }
    }
    return evidence;
  }

  static bool _isVoter(ClosureMemberRow m) =>
      m.activeAtOpen && m.departure != Departure.removed;

  static Map<String, Set<String>> _targetsByVoter(
    List<ClosureSupportRow> rows,
  ) {
    final out = <String, Set<String>>{};
    for (final r in rows) {
      out.putIfAbsent(r.voterId, () => {}).add(r.targetId);
    }
    return out;
  }

  static ClosureResultDraftFlag _draftFlag({
    required bool hasCommit,
    required Set<String>? draft,
    required Set<String>? committed,
  }) {
    if (!hasCommit) {
      return draft != null && draft.isNotEmpty
          ? ClosureResultDraftFlag.notCounted
          : ClosureResultDraftFlag.none;
    }
    final d = draft ?? const <String>{};
    final c = committed ?? const <String>{};
    return d.length == c.length && d.containsAll(c)
        ? ClosureResultDraftFlag.none
        : ClosureResultDraftFlag.lastEditNotCounted;
  }
}
