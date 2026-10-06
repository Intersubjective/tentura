import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/commitment_consts.dart';
import 'package:tentura_server/domain/closure/author_split.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_exception.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/closure_view.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/beacon_kind_policy.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';

import '_use_case_base.dart';
import 'beacon_lifecycle_effects_case.dart';
import 'plan_attention_case.dart';

/// A12: episode-closure lock and lifecycle (Arch §5.1–§5.3, §7).
///
/// Every mutating operation runs in one transaction that takes the per-request
/// lock first (after the hierarchy scope lock, where the operation takes one).
@Singleton(order: 1)
final class ClosureCase extends UseCaseBase {
  ClosureCase({
    required MutatingUnitOfWorkPort unitOfWork,
    required ClosureRepositoryPort closureRepository,
    required BeaconRepositoryPort beaconRepository,
    required CommitmentRepositoryPort commitmentRepository,
    required HelpOfferRepositoryPort helpOfferRepository,
    required BeaconHierarchyRepositoryPort hierarchyRepository,
    required BeaconLifecycleEffectsCase lifecycleEffects,
    required AttentionSystemSettlementPort attentionSystemSettlement,
    required ClosureReceiptsPort receipts,
    required ClosureFinalizerPort finalizer,
    required super.env,
    required super.logger,
    this._planAttention,
  }) : _uow = unitOfWork,
       _repo = closureRepository,
       _beacons = beaconRepository,
       _commitments = commitmentRepository,
       _helpOffers = helpOfferRepository,
       _hierarchy = hierarchyRepository,
       _lifecycleEffects = lifecycleEffects,
       _settlement = attentionSystemSettlement,
       _receipts = receipts,
       _finalizer = finalizer;

  final MutatingUnitOfWorkPort _uow;
  final ClosureRepositoryPort _repo;
  final BeaconRepositoryPort _beacons;
  final CommitmentRepositoryPort _commitments;
  final HelpOfferRepositoryPort _helpOffers;
  final BeaconHierarchyRepositoryPort _hierarchy;
  final BeaconLifecycleEffectsCase _lifecycleEffects;
  final AttentionSystemSettlementPort _settlement;
  final ClosureReceiptsPort _receipts;
  final ClosureFinalizerPort _finalizer;
  final PlanAttentionCase? _planAttention;

  static const Duration _window = Duration(days: 7);
  static const Duration _closeNowGrace = Duration(hours: 48);
  static const int _maxExtensions = 2;
  static const int _smallEpisodeSize = 2;
  static const int _minToggleMembers = 3;
  static const int _maxStoryLength = 2000;

  /// Takes the per-request lock. Commitment-event writers call this before
  /// writing, inside their existing transaction.
  Future<void> lockRequest(String beaconId) => _repo.lockRequest(beaconId);

  Future<T> _inClosureTx<T>({
    required String actorId,
    required String beaconId,
    required int? expectedEpoch,
    required Future<T> Function(ClosureEpoch? live) body,
    bool hierarchyScope = false,
  }) => _uow.run(
    actorUserId: actorId,
    action: () async {
      if (hierarchyScope) await _hierarchy.lockMutationScope();
      await _repo.lockRequest(beaconId);
      final live = await _repo.liveEpoch(beaconId);
      if (expectedEpoch != null && live?.epoch != expectedEpoch) {
        throw const ClosureException.staleEpoch();
      }
      return body(live);
    },
  );

  Future<void> _requireAuthor(String beaconId, String authorId) async {
    final beacon = await _beacons.getBeaconById(beaconId: beaconId);
    BeaconKindPolicy.requireRequest(beacon);
    if (beacon.author.id != authorId) {
      throw const ClosureException.notAuthor();
    }
  }

  /// Author closes the Request: no member ever ⇒ closed; else opens epoch.
  Future<void> close({
    required String authorId,
    required String beaconId,
  }) => _inClosureTx<void>(
    actorId: authorId,
    beaconId: beaconId,
    expectedEpoch: null,
    hierarchyScope: true,
    body: (live) async {
      final beacon = await _beacons.getBeaconById(beaconId: beaconId);
      BeaconKindPolicy.requireRequest(beacon);
      if (beacon.author.id != authorId) {
        throw const ClosureException.notAuthor();
      }
      if (!beacon.status.isOpenFamily) {
        throw const ClosureException.wrongStatus();
      }

      final now = DateTime.timestamp();
      final eventsByUser = await _commitments.eventsByUser(beaconId);
      final states = <String, MemberState>{};
      for (final userId in eventsByUser.keys.toList()..sort()) {
        if (userId == authorId) continue;
        final state = reduce(eventsByUser[userId]!, now: now);
        if (state.member) states[userId] = state;
      }
      final opensEpoch = states.isNotEmpty;
      final target = opensEpoch ? BeaconStatus.reviewOpen : BeaconStatus.closed;

      await _beacons.recordBeaconStatusTransition(
        beaconId: beaconId,
        fromStatus: beacon.status,
        toStatus: target,
        reason: opensEpoch
            ? BeaconLifecycleChangeReason.closureOpened
            : BeaconLifecycleChangeReason.directClose,
        actorId: authorId,
      );
      await _lifecycleEffects.recordEligibleSourceTransition(
        sourceBeaconId: beaconId,
        fromStatus: beacon.status,
        toStatus: target,
        occurredAt: now,
        actorUserId: authorId,
        reason: opensEpoch
            ? BeaconStatusTransitionReason.closureOpened
            : BeaconStatusTransitionReason.directClose,
      );
      await _recordUnansweredAtCloseOffers(
        beaconId: beaconId,
        authorId: authorId,
      );
      // D04: a closed Request cannot still owe an answer to an offer.
      await _settlement.supersedeAuthorHelpOfferObligationsOnBeaconClose(
        beaconId,
      );
      // Review ends step obligations, closed ends all plan obligations (P21).
      await _planAttention?.onRequestStatusChanged(
        beaconId: beaconId,
        actorId: authorId,
      );
      if (!opensEpoch) return;

      final offers = {
        for (final o in await _helpOffers.fetchAllByBeaconId(beaconId))
          o.userId: o,
      };
      final inserts = <ClosureMemberInsert>[];
      for (final MapEntry(key: userId, value: state) in states.entries) {
        final offer = offers[userId];
        final edge = offer == null
            ? null
            : await _repo.selectArrivalEdge(
                beaconId: beaconId,
                helperId: userId,
                offerCreatedAt: offer.createdAt,
              );
        inserts.add(
          ClosureMemberInsert(
            userId: userId,
            activeAtOpen: state.active,
            arrivalEdgeId: edge?.id,
            departure: state.departure,
          ),
        );
      }

      final epochNumber = await _repo.maxEpoch(beaconId) + 1;
      await _repo.createEpoch(
        beaconId: beaconId,
        epoch: epochNumber,
        openedAt: now,
        closesAt: now.add(_window),
      );
      await _repo.insertMembers(
        beaconId: beaconId,
        epoch: epochNumber,
        members: inserts,
      );

      // New members may have joined since a reopen: keep a custom split valid.
      final split = await _repo.split(beaconId);
      if (split.isNotEmpty) {
        final notDone = {
          for (final o in await _repo.outcomes(beaconId))
            if (o.outcome == ClosureOutcome.notDone) o.helperId,
        };
        await _repo.replaceSplit(
          beaconId,
          renormalize(
            current: split,
            newA: states.keys.toSet().difference(notDone),
            beaconId: beaconId,
          ),
        );
      }
      await _receipts.opened(beaconId, epochNumber);
    },
  );

  /// Author adds 7 days (max 2 extensions).
  Future<void> extend({
    required String authorId,
    required String beaconId,
    int? expectedEpoch,
  }) => _inClosureTx<void>(
    actorId: authorId,
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    body: (live) async {
      await _requireAuthor(beaconId, authorId);
      if (live == null) throw const ClosureException.wrongStatus();
      if (live.extensionsUsed >= _maxExtensions) {
        throw const ClosureException.extendLimit();
      }
      await _repo.extendEpoch(beaconId: beaconId, epoch: live.epoch);
    },
  );

  /// Author cancels the live epoch and returns the Request to needsMoreHelp.
  /// Outcomes and drafts stay; committed supports and commit rows go.
  Future<void> reopen({
    required String authorId,
    required String beaconId,
    int? expectedEpoch,
  }) => _inClosureTx<void>(
    actorId: authorId,
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    body: (live) async {
      final beacon = await _beacons.getBeaconById(beaconId: beaconId);
      BeaconKindPolicy.requireRequest(beacon);
      if (beacon.author.id != authorId) {
        throw const ClosureException.notAuthor();
      }
      if (live == null) throw const ClosureException.wrongStatus();
      if (!canReopen(
        live: live,
        cancelledEpochs: await _repo.cancelledEpochCount(beaconId),
      )) {
        throw const ClosureException.reopenLimit();
      }
      await _repo.setEpochStatus(
        beaconId: beaconId,
        epoch: live.epoch,
        status: ClosureEpochStatus.cancelled,
      );
      await _repo.clearCommitted(beaconId);
      await _beacons.recordBeaconStatusTransition(
        beaconId: beaconId,
        fromStatus: beacon.status,
        toStatus: BeaconStatus.needsMoreHelp,
        reason: BeaconLifecycleChangeReason.reopenedFromReview,
        actorId: authorId,
      );
      // Back in the open family: the current steps are owed again (P21).
      await _planAttention?.onRequestStatusChanged(
        beaconId: beaconId,
        actorId: authorId,
      );
      await _receipts.cancelled(beaconId, live.epoch);
    },
  );

  /// Author finalizes early when [canCloseNow].
  Future<void> closeNow({
    required String authorId,
    required String beaconId,
    int? expectedEpoch,
  }) => _inClosureTx<void>(
    actorId: authorId,
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    body: (live) async {
      await _requireAuthor(beaconId, authorId);
      if (live == null) throw const ClosureException.wrongStatus();
      final ready = canCloseNow(
        epoch: live,
        members: await _repo.members(beaconId: beaconId, epoch: live.epoch),
        outcomes: await _repo.outcomes(beaconId),
        commits: await _repo.commits(beaconId),
        now: DateTime.timestamp(),
      );
      if (!ready) throw const ClosureException.notReady();
      await _finalizer.finalize(
        beaconId: beaconId,
        epoch: live.epoch,
        reason: FinalizeReason.authorCloseNow,
      );
    },
  );

  /// Every member has an outcome and (≤ 2 members, or every voter committed,
  /// or 48 h since the epoch opened).
  static bool canCloseNow({
    required ClosureEpoch epoch,
    required List<ClosureMemberRow> members,
    required List<ClosureOutcomeRow> outcomes,
    required List<ClosureCommitRow> commits,
    required DateTime now,
  }) {
    final answered = {
      for (final o in outcomes)
        if (o.outcome != null) o.helperId,
    };
    if (!members.every((m) => answered.contains(m.userId))) return false;
    if (members.length <= _smallEpisodeSize) return true;
    final committed = {for (final c in commits) c.voterId};
    final voters = members.where(isVoter).map((m) => m.userId);
    return voters.every(committed.contains) ||
        !now.isBefore(epoch.openedAt.add(_closeNowGrace));
  }

  /// `voter = active_at_open && departure != removed` (U49).
  static bool isVoter(ClosureMemberRow m) =>
      m.activeAtOpen && m.departure != Departure.removed;

  /// Evaluating and no earlier cancelled epoch.
  static bool canReopen({
    required ClosureEpoch? live,
    required int cancelledEpochs,
  }) =>
      live != null &&
      live.status == ClosureEpochStatus.evaluating &&
      cancelledEpochs < kMaxReviewReopens;

  /// Author records (or clears, with null) one member's outcome; a custom
  /// split is renormalized to the new A (E7).
  Future<void> saveOutcome({
    required String authorId,
    required String beaconId,
    required int expectedEpoch,
    required String helperId,
    ClosureOutcome? outcome,
  }) => _inClosureTx<void>(
    actorId: authorId,
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    body: (live) async {
      await _requireAuthor(beaconId, authorId);
      final members = await _repo.members(
        beaconId: beaconId,
        epoch: live!.epoch,
      );
      if (!members.any((m) => m.userId == helperId)) {
        throw const ClosureException.notMember();
      }
      await _repo.saveOutcome(
        beaconId: beaconId,
        helperId: helperId,
        outcome: outcome,
      );
      final split = await _repo.split(beaconId);
      if (split.isEmpty) return;
      await _repo.replaceSplit(
        beaconId,
        renormalize(
          current: split,
          newA: await _setA(beaconId, members),
          beaconId: beaconId,
        ),
      );
    },
  );

  /// Author replaces the custom split (null deletes it).
  Future<void> saveAuthorSplit({
    required String authorId,
    required String beaconId,
    required int expectedEpoch,
    required Map<String, int>? split,
  }) => _inClosureTx<void>(
    actorId: authorId,
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    body: (live) async {
      await _requireAuthor(beaconId, authorId);
      if (split != null) {
        final members = await _repo.members(
          beaconId: beaconId,
          epoch: live!.epoch,
        );
        switch (validate(split, await _setA(beaconId, members))) {
          case null:
            break;
          case 'splitTooLarge':
            throw const ClosureException.splitTooLarge();
          default:
            throw const ClosureException.invalidSplit();
        }
      }
      await _repo.replaceSplit(beaconId, split);
    },
  );

  /// Members whose outcome is done, can't judge or unanswered.
  Future<Set<String>> _setA(
    String beaconId,
    List<ClosureMemberRow> members,
  ) async {
    final notDone = {
      for (final o in await _repo.outcomes(beaconId))
        if (o.outcome == ClosureOutcome.notDone) o.helperId,
    };
    return {
      for (final m in members)
        if (!notDone.contains(m.userId)) m.userId,
    };
  }

  /// Voter toggles support for [targetId]. When the draft then holds every
  /// other member, the earliest other press is released and returned.
  Future<String?> toggleSupport({
    required String voterId,
    required String beaconId,
    required int expectedEpoch,
    required String targetId,
    required bool on,
  }) => _inClosureTx<String?>(
    actorId: voterId,
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    body: (live) async {
      final members = await _repo.members(
        beaconId: beaconId,
        epoch: live!.epoch,
      );
      _requireVoter(members, voterId);
      if (members.length < _minToggleMembers) {
        throw const ClosureException.wrongStatus();
      }
      if (targetId == voterId || !members.any((m) => m.userId == targetId)) {
        throw const ClosureException.notMember();
      }
      await _repo.toggleSupport(
        beaconId: beaconId,
        voterId: voterId,
        targetId: targetId,
        on: on,
      );
      if (!on) return null;

      final others = {
        for (final m in members)
          if (m.userId != voterId) m.userId,
      };
      final draft = [
        for (final r in await _repo.supports(
          beaconId: beaconId,
          version: ClosureSupportVersion.draft,
        ))
          if (r.voterId == voterId) r,
      ];
      if (!draft.map((r) => r.targetId).toSet().containsAll(others)) {
        return null;
      }
      final earliest =
          (draft.where((r) => r.targetId != targetId).toList()
                ..sort((a, b) => a.pressedAt.compareTo(b.pressedAt)))
              .first
              .targetId;
      await _repo.toggleSupport(
        beaconId: beaconId,
        voterId: voterId,
        targetId: earliest,
        on: false,
      );
      return earliest;
    },
  );

  void _requireVoter(List<ClosureMemberRow> members, String userId) {
    if (!members.any((m) => m.userId == userId && isVoter(m))) {
      throw const ClosureException.notVoter();
    }
  }

  /// Voter commits the current draft as version 1.
  Future<void> done({
    required String voterId,
    required String beaconId,
    required int expectedEpoch,
  }) => _inClosureTx<void>(
    actorId: voterId,
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    body: (live) async {
      _requireVoter(
        await _repo.members(beaconId: beaconId, epoch: live!.epoch),
        voterId,
      );
      await _repo.commitDraft(beaconId: beaconId, voterId: voterId);
    },
  );

  /// Voter commits without support.
  Future<void> skip({
    required String voterId,
    required String beaconId,
    required int expectedEpoch,
  }) => _inClosureTx<void>(
    actorId: voterId,
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    body: (live) async {
      _requireVoter(
        await _repo.members(beaconId: beaconId, epoch: live!.epoch),
        voterId,
      );
      await _repo.skip(beaconId: beaconId, voterId: voterId);
    },
  );

  /// Author or member marks [targetId] on an evaluating or the latest final
  /// epoch. After finalize the mark also lands in the evidence ledger, dated
  /// `finalized_at`.
  Future<void> setMark({
    required String userId,
    required String beaconId,
    required int expectedEpoch,
    required String targetId,
    required bool on,
  }) => _inClosureTx<void>(
    actorId: userId,
    beaconId: beaconId,
    expectedEpoch: null,
    body: (live) async {
      final epoch = live ?? await _repo.latestEpoch(beaconId);
      if (epoch == null ||
          epoch.epoch != expectedEpoch ||
          epoch.status == ClosureEpochStatus.cancelled) {
        throw const ClosureException.staleEpoch();
      }
      final beacon = await _beacons.getBeaconById(beaconId: beaconId);
      BeaconKindPolicy.requireRequest(beacon);
      final authorId = beacon.author.id;
      final memberIds = {
        for (final m in await _repo.members(
          beaconId: beaconId,
          epoch: epoch.epoch,
        ))
          m.userId,
      };
      bool participant(String id) => id == authorId || memberIds.contains(id);
      if (!participant(userId) || !participant(targetId)) {
        throw const ClosureException.notMember();
      }
      if (userId == targetId) throw const ClosureException.notMember();

      await _repo.setMark(
        beaconId: beaconId,
        markerId: userId,
        targetId: targetId,
        on: on,
      );
      if (epoch.status != ClosureEpochStatus.finalized) return;
      if (on) {
        await _repo.upsertMarkEvidence(
          beaconId: beaconId,
          epoch: epoch.epoch,
          markerId: userId,
          targetId: targetId,
          occurredAt: epoch.finalizedAt!,
        );
      } else {
        await _repo.retractMarkEvidence(
          beaconId: beaconId,
          epoch: epoch.epoch,
          markerId: userId,
          targetId: targetId,
        );
      }
    },
  );

  /// Author's closing story; empty deletes it.
  Future<void> saveStory({
    required String authorId,
    required String beaconId,
    required int expectedEpoch,
    required String body,
  }) => _inClosureTx<void>(
    actorId: authorId,
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    body: (live) async {
      await _requireAuthor(beaconId, authorId);
      final text = body.trim();
      if (text.length > _maxStoryLength) {
        throw const PayloadTooLargeException(
          description: 'Story is longer than 2000 characters',
        );
      }
      await _repo.saveStory(beaconId: beaconId, body: text);
    },
  );

  /// Members who were blocked: their last membership event is
  /// `blockedCleanup` (a later acknowledgement or readmission lifts it).
  Set<String> _blockedIds(Map<String, List<CommitmentEvent>> eventsByUser) => {
    for (final MapEntry(key: userId, value: events) in eventsByUser.entries)
      if (_isBlocked(events)) userId,
  };

  static bool _isBlocked(List<CommitmentEvent> events) {
    var blocked = false;
    for (final e in List<CommitmentEvent>.from(
      events,
    )..sort((a, b) => a.seq.compareTo(b.seq))) {
      switch (e.kind) {
        case CommitmentEventKind.blockedCleanup:
          blocked = true;
        case CommitmentEventKind.acknowledged:
        case CommitmentEventKind.readmittedToChat:
          blocked = false;
        case CommitmentEventKind.offered:
        case CommitmentEventKind.acknowledgementSoftened:
        case CommitmentEventKind.withdrawnByHelper:
        case CommitmentEventKind.releasedByAuthor:
        case CommitmentEventKind.removedFromChat:
        case CommitmentEventKind.unansweredAtClose:
          break;
      }
    }
    return blocked;
  }

  /// Role-specific closure state (Arch §7). Outsiders and blocked members get
  /// the same not-found, so the role does not leak.
  Future<ClosureStateView> state({
    required String viewerId,
    required String beaconId,
  }) async {
    final epoch =
        await _repo.liveEpoch(beaconId) ?? await _repo.latestEpoch(beaconId);
    if (epoch == null || epoch.status == ClosureEpochStatus.cancelled) {
      throw IdNotFoundException(id: beaconId);
    }
    final beacon = await _beacons.getBeaconById(beaconId: beaconId);
    BeaconKindPolicy.requireRequest(beacon);
    final authorId = beacon.author.id;
    final rows = await _repo.members(beaconId: beaconId, epoch: epoch.epoch);
    final blocked = _blockedIds(await _commitments.eventsByUser(beaconId));

    final role = viewerId == authorId
        ? ClosureRole.author
        : !rows.any((m) => m.userId == viewerId) || blocked.contains(viewerId)
        ? throw IdNotFoundException(id: beaconId)
        : rows.any(
            // A departed member (voluntary or removed) reads as a member.
            (m) =>
                m.userId == viewerId && m.activeAtOpen && m.departure == null,
          )
        ? ClosureRole.voter
        : ClosureRole.member;
    final isAuthor = role == ClosureRole.author;

    final members = [
      for (final m in rows)
        ClosureMemberView(
          id: m.userId,
          notInRequest: m.departure != null || blocked.contains(m.userId),
          departure: isAuthor
              ? (m.departure ??
                        (blocked.contains(m.userId) ? Departure.removed : null))
                    ?.name
              : null,
        ),
    ];
    final myMarks = [
      for (final r in await _repo.marks(beaconId))
        if (r.markerId == viewerId) r.targetId,
    ];
    final finalized = epoch.status == ClosureEpochStatus.finalized;
    final story = isAuthor || finalized ? await _repo.story(beaconId) : null;
    final earlyCloseAt = epoch.openedAt.add(_closeNowGrace);

    switch (role) {
      case ClosureRole.author:
        final outcomes = await _repo.outcomes(beaconId);
        return ClosureStateView(
          epoch: epoch.epoch,
          status: epoch.status,
          role: role,
          members: members,
          closesAt: epoch.closesAt,
          myMarks: myMarks,
          outcomes: {
            for (final o in outcomes)
              if (o.outcome != null) o.helperId: o.outcome!,
          },
          split: await _repo.split(beaconId),
          earlyCloseAt: earlyCloseAt,
          canCloseNow:
              !finalized &&
              canCloseNow(
                epoch: epoch,
                members: rows,
                outcomes: outcomes,
                commits: await _repo.commits(beaconId),
                now: DateTime.timestamp(),
              ),
          // Every earlier epoch of a live one was cancelled (reopen).
          canReopen: canReopen(
            live: finalized ? null : epoch,
            cancelledEpochs: epoch.epoch - 1,
          ),
          extensionsUsed: epoch.extensionsUsed,
          story: story,
        );
      case ClosureRole.voter:
        final mine = {
          for (final r in await _repo.supports(
            beaconId: beaconId,
            version: ClosureSupportVersion.draft,
          ))
            if (r.voterId == viewerId) r.targetId,
        };
        final committed = {
          for (final r in await _repo.supports(
            beaconId: beaconId,
            version: ClosureSupportVersion.committed,
          ))
            if (r.voterId == viewerId) r.targetId,
        };
        final hasCommit = (await _repo.commits(
          beaconId,
        )).any((c) => c.voterId == viewerId);
        return ClosureStateView(
          epoch: epoch.epoch,
          status: epoch.status,
          role: role,
          members: members,
          closesAt: epoch.closesAt,
          myMarks: myMarks,
          mySupport: mine.toList(),
          inCalcText: !hasCommit
              ? 'notCounted'
              : mine.length == committed.length && mine.containsAll(committed)
              ? 'counted'
              : 'differs',
          earlyCloseAt: earlyCloseAt,
          story: story,
        );
      case ClosureRole.member:
        return ClosureStateView(
          epoch: epoch.epoch,
          status: epoch.status,
          role: role,
          members: members,
          closesAt: epoch.closesAt,
          myMarks: myMarks,
          story: story,
        );
    }
  }

  /// The viewer's own result of the latest epoch; members only (blocked
  /// members included). The author is not a member.
  Future<ClosureResultView?> resultForViewer({
    required String viewerId,
    required String beaconId,
  }) async {
    final epoch = await _repo.latestEpoch(beaconId);
    if (epoch == null ||
        !(await _repo.members(
          beaconId: beaconId,
          epoch: epoch.epoch,
        )).any((m) => m.userId == viewerId)) {
      throw IdNotFoundException(id: beaconId);
    }
    if (epoch.status != ClosureEpochStatus.finalized) return null;
    final row = await _repo.resultFor(beaconId: beaconId, userId: viewerId);
    if (row == null) return null;
    return ClosureResultView(
      outcome: row.outcome,
      band: row.band,
      draftFlag: row.draftFlag,
      marks: [
        for (final r in await _repo.marks(beaconId))
          if (r.markerId == viewerId) r.targetId,
      ],
      story: await _repo.story(beaconId),
    );
  }

  /// Re-derives [helperId]'s departure after a commitment event. Callers hold
  /// the per-request lock and run in the same transaction as the write.
  Future<void> applyMembershipEvent(String beaconId, String helperId) async {
    final live = await _repo.liveEpoch(beaconId);
    if (live == null) return;
    final rows = await _repo.members(beaconId: beaconId, epoch: live.epoch);
    if (!rows.any((m) => m.userId == helperId)) return;
    final events = await _commitments.eventsForPair(
      beaconId: beaconId,
      userId: helperId,
    );
    await _repo.setDeparture(
      beaconId: beaconId,
      epoch: live.epoch,
      userId: helperId,
      departure: reduce(events, now: DateTime.timestamp()).departure,
    );
  }

  /// Stream 2 (Arch §5.7): approving an offer credits the forwarder through
  /// whom the helper arrived. Call inside the approval transaction, after the
  /// acknowledgement is stored.
  Future<void> recordApprovalEdge({
    required String beaconId,
    required String helperId,
    required String authorId,
  }) async {
    await _repo.lockRequest(beaconId);
    final offers = await _helpOffers.fetchAllByBeaconId(beaconId);
    final offer = offers.where((o) => o.userId == helperId).firstOrNull;
    if (offer == null) return;
    final edge = await _repo.selectArrivalEdge(
      beaconId: beaconId,
      helperId: helperId,
      offerCreatedAt: offer.createdAt,
    );
    if (edge == null ||
        edge.senderId == authorId ||
        edge.senderId == helperId) {
      return;
    }
    await _repo.recordApprovalEdge(
      beaconId: beaconId,
      helperId: helperId,
      senderId: edge.senderId,
      arrivalEdgeId: edge.id,
    );
  }

  /// Stream 2: voluntary withdrawal retracts the approval edge.
  Future<void> retractApprovalEdge(String beaconId, String helperId) =>
      _repo.retractApprovalEdge(beaconId: beaconId, helperId: helperId);

  Future<void> _recordUnansweredAtCloseOffers({
    required String beaconId,
    required String authorId,
  }) async {
    final offers = await _helpOffers.fetchByBeaconId(beaconId);
    for (final offer in offers) {
      if (!offer.isActive || offer.offerKind != 0) continue;
      final events = await _commitments.eventsForPair(
        beaconId: beaconId,
        userId: offer.userId,
      );
      if (everAcknowledged(events)) continue;
      await _commitments.record(
        beaconId: beaconId,
        userId: offer.userId,
        actorUserId: authorId,
        kind: CommitmentEventKind.unansweredAtClose,
      );
    }
  }
}
