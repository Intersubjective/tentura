import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/beacon_close_review_result.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_draft_row_result.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_participant_result.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_summary_result.dart';
import 'package:tentura_server/domain/entity/gql_public/review_window_status_result.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/evaluation/evaluation_reason_tags.dart';
import 'package:tentura_server/domain/evaluation/evaluation_summary_rules.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/utils/id.dart';

import 'capability_case.dart';
import 'evaluation/evaluation_draft_purger.dart';
import 'evaluation/evaluation_participant_graph_builder.dart';
import 'evaluation/evaluation_prompt_variant.dart';
import '_use_case_base.dart';

List<String> _reasonTagsFromCsv(String csv) => csv.isEmpty
    ? <String>[]
    : csv.split(',').where((s) => s.isNotEmpty).toList();

EvaluationSummaryResult _buildEvaluationSummary({
  required BeaconStatus beaconStatus,
  required int distinctEvaluatorCount,
  required List<SummaryEvaluationRowInput> rows,
  required EvaluationParticipantRole? viewerRole,
}) {
  if (beaconStatus != BeaconStatus.closed) {
    return const EvaluationSummaryResult(
      suppressed: true,
      tone: 'mixed',
      message: '',
      topReasonTags: [],
      roleSummaryLine: '',
    );
  }
  if (rows.isEmpty) {
    return const EvaluationSummaryResult(
      suppressed: true,
      tone: 'mixed',
      message: 'No feedback',
      topReasonTags: [],
      roleSummaryLine: '',
    );
  }
  final tone = evaluationToneFromValues(rows.map((r) => r.value));
  if (distinctEvaluatorCount < 3) {
    return EvaluationSummaryResult(
      suppressed: true,
      tone: tone,
      message: 'Feedback in this request (details limited for privacy)',
      topReasonTags: const [],
      roleSummaryLine: '',
    );
  }
  final agg = evaluationSummaryAggregates(rows);
  return EvaluationSummaryResult(
    suppressed: false,
    tone: tone,
    message: '',
    topReasonTags: agg.topReasonTags,
    neg2: agg.neg2,
    neg1: agg.neg1,
    zero: agg.zero,
    pos1: agg.pos1,
    pos2: agg.pos2,
    roleSummaryLine: evaluationRoleSummaryLine(viewerRole, tone),
  );
}

/// Post-beacon evaluation (Phase 1): open window, visibility, private rows, summaries.
@Singleton(order: 2)
final class EvaluationCase extends UseCaseBase {
  EvaluationCase(
    this._beaconRepository,
    this._forwardEdgeRepository,
    this._evaluationRepository,
    this._userProfileBatchLookup,
    BeaconRoomNotificationPort legacyNotificationPort,
    this._participantGraphBuilder,
    this._draftPurger,
    this._capabilityCase, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    AttentionExpirySweepCase? attentionExpirySweep,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention,
       _attentionExpirySweep = attentionExpirySweep;

  final BeaconRepositoryPort _beaconRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final EvaluationRepositoryPort _evaluationRepository;
  final UserProfileBatchLookup _userProfileBatchLookup;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;
  final AttentionExpirySweepCase? _attentionExpirySweep;
  final EvaluationParticipantGraphBuilder _participantGraphBuilder;
  final EvaluationDraftPurger _draftPurger;
  final CapabilityCase _capabilityCase;

  static const Duration _reviewWindowDuration = Duration(days: 7);

  static const int _maxReviewExtensions = 2;

  Future<void> _ensureExpiredClosed() async {
    await _attentionExpirySweep!.runDue();
  }

  Future<T> _runStatusAction<T>({
    required String actorUserId,
    required Future<T> Function(AttentionTransaction? transaction) action,
  }) {
    return _attention!.runAction(
      actorUserId: actorUserId,
      action: action,
    );
  }

  /// Author closes beacon; 0 committers → closed (6), ≥1 → wrapping up (5) + window.
  Future<BeaconCloseReviewResult> beaconClose({
    required String beaconId,
    required String userId,
    required bool expectedRequiresReviewWindow,
  }) async {
    await _ensureExpiredClosed();
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) => _beaconRepository.runInBeaconStateTransaction(
        beaconId: beaconId,
        userId: userId,
        fn: (beacon) async {
          if (!beacon.status.isOpenFamily) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.beaconNotClosable,
              description: 'Request must be open to close',
            );
          }
          if (beacon.author.id != userId) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.notEligible,
              description: 'Only the author can close',
            );
          }

          final graph = await _participantGraphBuilder.build(
            beaconId: beaconId,
            authorId: beacon.author.id,
            preClosure: false,
          );
          final committerCount = graph.participants
              .where((p) => p.role == EvaluationParticipantRole.committer)
              .length;
          final requiresReviewWindow = committerCount >= 1;

          if (expectedRequiresReviewWindow != requiresReviewWindow) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.closeBranchConflict,
              description: 'Committer count changed; refresh and retry',
            );
          }

          final targetStatus = requiresReviewWindow
              ? BeaconStatus.reviewOpen
              : BeaconStatus.closed;
          final statusIntent = await _attentionIntents!.requestStatusChanged(
            beaconId: beaconId,
            fromStatus: beacon.status.name,
            toStatus: targetStatus.name,
            actorUserId: userId,
            sourceEventKey: 'request_status:${generateId('A')}',
          );

          if (!requiresReviewWindow) {
            await _beaconRepository.recordBeaconStatusTransition(
              beaconId: beaconId,
              fromStatus: beacon.status,
              toStatus: BeaconStatus.closed,
              reason: BeaconLifecycleChangeReason.directClose,
              actorId: userId,
            );
            if (statusIntent != null) {
              await transaction.record(statusIntent);
            }
            return BeaconCloseReviewResult(
              id: beaconId,
              status: BeaconStatus.closed.smallintValue,
            );
          }

          final participants = graph.participants;
          final visibility = graph.visibility;

          final openedAt = DateTime.timestamp();
          final closesAt = openedAt.add(_reviewWindowDuration);

          await _evaluationRepository.downgradeSubmittedReviewsToDraft(
            beaconId,
          );
          await _evaluationRepository.deleteReviewScaffoldingForBeacon(
            beaconId,
          );

          await _beaconRepository.recordBeaconStatusTransition(
            beaconId: beaconId,
            fromStatus: beacon.status,
            toStatus: BeaconStatus.reviewOpen,
            reason: BeaconLifecycleChangeReason.reviewWindowOpened,
            actorId: userId,
          );
          if (statusIntent != null) {
            await transaction.record(statusIntent);
          }

          await _evaluationRepository.insertReviewWindow(
            beaconId: beaconId,
            openedAt: openedAt,
            closesAt: closesAt,
          );

          for (final p in participants) {
            await _evaluationRepository.insertParticipant(
              beaconId: beaconId,
              userId: p.userId,
              role: p.role.dbValue,
              contributionSummary: p.contributionSummary,
              causalHint: p.causalHint,
            );
          }

          final participantIds = participants.map((e) => e.userId).toSet();
          for (final uid in participantIds) {
            await _evaluationRepository.insertReviewStatus(
              beaconId: beaconId,
              userId: uid,
            );
          }

          for (final v in visibility) {
            await _evaluationRepository.insertVisibility(
              beaconId: beaconId,
              evaluatorId: v.evaluatorId,
              participantId: v.participantId,
            );
          }

          await _draftPurger.purgeDraftsOutsideVisibility(beaconId);

          await transaction.record(
            await _attentionIntents!.reviewOpened(
              beaconId: beaconId,
              beaconTitle: beacon.title,
              recipientUserIds: participantIds,
              actorUserId: userId,
              sourceEventKey: 'review_opened:${generateId('A')}',
            ),
          );

          return BeaconCloseReviewResult(
            id: beaconId,
            status: BeaconStatus.reviewOpen.smallintValue,
            closesAt: closesAt,
          );
        },
      ),
    );
  }

  /// Author adds 7 days during wrapping up (max 2 extensions).
  Future<BeaconCloseReviewResult> extendReviewWindow({
    required String beaconId,
    required String userId,
  }) async {
    await _ensureExpiredClosed();
    return _beaconRepository.runInBeaconStateTransaction(
      beaconId: beaconId,
      userId: userId,
      fn: (beacon) async {
        if (beacon.status != BeaconStatus.reviewOpen) {
          throw EvaluationException(
            evaluationCode: EvaluationExceptionCode.beaconNotClosable,
            description: 'Request must be wrapping up to extend review',
          );
        }
        if (beacon.author.id != userId) {
          throw EvaluationException(
            evaluationCode: EvaluationExceptionCode.notEligible,
          );
        }
        final w = await _evaluationRepository.getReviewWindow(beaconId);
        if (w == null || w.status != 0) {
          throw EvaluationException(
            evaluationCode: EvaluationExceptionCode.reviewWindowNotOpen,
          );
        }
        if (w.extensionsUsed >= _maxReviewExtensions) {
          throw EvaluationException(
            evaluationCode: EvaluationExceptionCode.beaconNotClosable,
            description: 'Review extension limit reached',
          );
        }
        final closesAt = await _evaluationRepository.extendReviewWindow(
          beaconId,
        );
        return BeaconCloseReviewResult(
          id: beaconId,
          status: BeaconStatus.reviewOpen.smallintValue,
          closesAt: closesAt,
        );
      },
    );
  }

  /// Author returns beacon to open; review content preserved as drafts.
  Future<BeaconCloseReviewResult> reopenFromReview({
    required String beaconId,
    required String userId,
  }) async {
    await _ensureExpiredClosed();
    return _runStatusAction(
      actorUserId: userId,
      action: (transaction) => _beaconRepository.runInBeaconStateTransaction(
        beaconId: beaconId,
        userId: userId,
        fn: (beacon) async {
          if (beacon.status != BeaconStatus.reviewOpen) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.beaconNotClosable,
              description: 'Request must be wrapping up to reopen',
            );
          }
          if (beacon.author.id != userId) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.notEligible,
            );
          }
          final w = await _evaluationRepository.getReviewWindow(beaconId);
          if (w == null || w.status != 0) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.reviewWindowNotOpen,
            );
          }
          final intent = transaction == null
              ? null
              : await _attentionIntents!.requestStatusChanged(
                  beaconId: beaconId,
                  fromStatus: beacon.status.name,
                  toStatus: BeaconStatus.open.name,
                  actorUserId: userId,
                  sourceEventKey: 'request_status:${generateId('A')}',
                );
          await _evaluationRepository.downgradeSubmittedReviewsToDraft(
            beaconId,
          );
          await _evaluationRepository.deleteReviewScaffoldingForBeacon(
            beaconId,
          );
          await _beaconRepository.recordBeaconStatusTransition(
            beaconId: beaconId,
            fromStatus: beacon.status,
            toStatus: BeaconStatus.open,
            reason: BeaconLifecycleChangeReason.reopenedFromReview,
            actorId: userId,
          );
          if (intent != null) {
            await transaction!.record(intent);
          }
          return BeaconCloseReviewResult(
            id: beaconId,
            status: BeaconStatus.open.smallintValue,
          );
        },
      ),
    );
  }

  /// Author closes early when required reviewers finished or skipped.
  Future<BeaconCloseReviewResult> closeNow({
    required String beaconId,
    required String userId,
  }) async {
    await _ensureExpiredClosed();
    return _runStatusAction(
      actorUserId: userId,
      action: (transaction) => _beaconRepository.runInBeaconStateTransaction(
        beaconId: beaconId,
        userId: userId,
        fn: (beacon) async {
          if (beacon.status != BeaconStatus.reviewOpen) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.beaconNotClosable,
              description: 'Request must be wrapping up to close now',
            );
          }
          if (beacon.author.id != userId) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.notEligible,
            );
          }
          final w = await _evaluationRepository.getReviewWindow(beaconId);
          if (w == null || w.status != 0) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.reviewWindowNotOpen,
            );
          }
          if (!await _canCloseNow(beaconId: beaconId)) {
            throw EvaluationException(
              evaluationCode: EvaluationExceptionCode.notEligible,
              description: 'Required reviewers have not finished or skipped',
            );
          }
          final intent = transaction == null
              ? null
              : await _attentionIntents!.requestStatusChanged(
                  beaconId: beaconId,
                  fromStatus: beacon.status.name,
                  toStatus: BeaconStatus.closed.name,
                  actorUserId: userId,
                  sourceEventKey: 'request_status:${generateId('A')}',
                );
          await _evaluationRepository.closeBeaconReviewWindow(
            beaconId,
            reason: BeaconLifecycleChangeReason.authorCloseNow,
            actorUserId: userId,
          );
          if (intent != null) {
            await transaction!.record(intent);
          }
          return BeaconCloseReviewResult(
            id: beaconId,
            status: BeaconStatus.closed.smallintValue,
          );
        },
      ),
    );
  }

  Future<bool> _canCloseNow({required String beaconId}) async {
    final statuses = await _evaluationRepository.listReviewStatusesForBeacon(
      beaconId,
    );
    final parts = await _evaluationRepository.listParticipants(beaconId);
    for (final p in parts) {
      if (p.role != EvaluationParticipantRole.author.dbValue &&
          p.role != EvaluationParticipantRole.committer.dbValue) {
        continue;
      }
      final st = statuses[p.userId];
      if (st != 2 && st != 3) {
        return false;
      }
    }
    return true;
  }

  Future<List<EvaluationParticipantResult>> evaluationParticipants({
    required String beaconId,
    required String evaluatorId,
  }) async {
    await _ensureExpiredClosed();
    final w = await _evaluationRepository.getReviewWindow(beaconId);
    if (w == null || w.status != 0) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reviewWindowNotOpen,
      );
    }
    final status = await _evaluationRepository.getReviewUserStatus(
      beaconId,
      evaluatorId,
    );
    if (status == null) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.notEligible,
      );
    }

    final vis = await _evaluationRepository.listVisibilityForEvaluator(
      beaconId,
      evaluatorId,
    );
    final parts = await _evaluationRepository.listParticipants(beaconId);
    final partByUser = {for (final p in parts) p.userId: p};
    final committerIds = parts
        .where((p) => p.role == EvaluationParticipantRole.committer.dbValue)
        .map((p) => p.userId)
        .toList();
    final latestEdgeToCommitter = await _latestEdgesToCommitters(
      beaconId: beaconId,
      committerIds: committerIds,
    );

    final evByTarget = await _evaluationsByTargetForEvaluator(
      beaconId: beaconId,
      evaluatorId: evaluatorId,
    );

    final visibleParticipantIds = [
      for (final v in vis)
        if (partByUser[v.participantId] != null) v.participantId,
    ];
    final usersById = await _userProfileBatchLookup.userEntitiesByIds(
      visibleParticipantIds,
    );

    final out = <EvaluationParticipantResult>[];
    for (final v in vis) {
      final pid = v.participantId;
      final row = partByUser[pid];
      if (row == null) {
        continue;
      }
      final u = usersById[pid];
      if (u == null) {
        throw IdNotFoundException(id: pid);
      }
      final ev = evByTarget[pid];
      out.add(
        EvaluationParticipantResult(
          userId: pid,
          displayName: u.displayName,
          imageId: u.image?.id ?? '',
          role: row.role,
          contributionSummary: row.contributionSummary,
          causalHint: row.causalHint,
          reasonTags: ev == null ? const [] : _reasonTagsFromCsv(ev.reasonTags),
          note: ev?.note ?? '',
          promptVariant: evaluationPromptVariantForPair(
            evaluatorId: evaluatorId,
            evaluatedRoleDb: row.role,
            evaluatedUserId: pid,
            latestEdgeToCommitter: latestEdgeToCommitter,
          ),
          value: ev?.value,
        ),
      );
    }
    return out;
  }

  Future<Map<String, ForwardEdgeEntity>> _latestEdgesToCommitters({
    required String beaconId,
    required List<String> committerIds,
  }) async {
    final edges = await _forwardEdgeRepository.fetchByBeaconId(beaconId);
    final latestEdgeToCommitter = <String, ForwardEdgeEntity>{};
    for (final c in committerIds) {
      final toC = edges.where((e) => e.recipientId == c).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (toC.isNotEmpty) {
        latestEdgeToCommitter[c] = toC.first;
      }
    }
    return latestEdgeToCommitter;
  }

  Future<Map<String, BeaconEvaluationRecord>> _evaluationsByTargetForEvaluator({
    required String beaconId,
    required String evaluatorId,
  }) async {
    final rows = await _evaluationRepository.listEvaluationsForEvaluator(
      beaconId: beaconId,
      evaluatorId: evaluatorId,
    );
    return {for (final r in rows) r.evaluatedUserId: r};
  }

  /// Open-beacon draft targets: same visibility as at closure, for current graph.
  Future<List<EvaluationParticipantResult>> evaluationDraftParticipants({
    required String beaconId,
    required String evaluatorId,
  }) async {
    await _ensureExpiredClosed();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.status.isOpenFamily) {
      return [];
    }
    final graph = await _participantGraphBuilder.build(
      beaconId: beaconId,
      authorId: beacon.author.id,
      preClosure: true,
    );
    final byId = {for (final p in graph.participants) p.userId: p};
    if (!byId.containsKey(evaluatorId)) {
      return [];
    }
    final evByTarget = await _evaluationsByTargetForEvaluator(
      beaconId: beaconId,
      evaluatorId: evaluatorId,
    );

    final visibleParticipantIds = [
      for (final v in graph.visibility)
        if (v.evaluatorId == evaluatorId && byId[v.participantId] != null)
          v.participantId,
    ];
    final usersById = await _userProfileBatchLookup.userEntitiesByIds(
      visibleParticipantIds,
    );

    final out = <EvaluationParticipantResult>[];
    for (final v in graph.visibility) {
      if (v.evaluatorId != evaluatorId) {
        continue;
      }
      final pid = v.participantId;
      final row = byId[pid];
      if (row == null) {
        continue;
      }
      final u = usersById[pid];
      if (u == null) {
        throw IdNotFoundException(id: pid);
      }
      final ev = evByTarget[pid];
      final useEv = ev != null && ev.status == BeaconEvaluationRowStatus.draft
          ? ev
          : null;
      out.add(
        EvaluationParticipantResult(
          userId: pid,
          displayName: u.displayName,
          imageId: u.image?.id ?? '',
          role: row.role.dbValue,
          contributionSummary: row.contributionSummary,
          causalHint: row.causalHint,
          reasonTags: useEv == null
              ? const []
              : _reasonTagsFromCsv(useEv.reasonTags),
          note: useEv?.note ?? '',
          promptVariant: evaluationPromptVariantForPair(
            evaluatorId: evaluatorId,
            evaluatedRoleDb: row.role.dbValue,
            evaluatedUserId: pid,
            latestEdgeToCommitter: graph.latestEdgeToCommitter,
          ),
          value: useEv?.value,
        ),
      );
    }
    return out;
  }

  Future<List<EvaluationDraftRowResult>> evaluationDrafts({
    required String beaconId,
    required String evaluatorId,
  }) async {
    await _ensureExpiredClosed();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.status.isOpenFamily) {
      return [];
    }
    final rows = await _evaluationRepository.listDraftRowsForBeacon(beaconId);
    final mine = rows.where((r) => r.evaluatorId == evaluatorId).toList();
    final out = <EvaluationDraftRowResult>[];
    for (final r in mine) {
      out.add(
        EvaluationDraftRowResult(
          evaluatedUserId: r.evaluatedUserId,
          value: r.value,
          reasonTags: _reasonTagsFromCsv(r.reasonTags),
          note: r.note,
        ),
      );
    }
    return out;
  }

  Future<bool> evaluationDraftSave({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required List<String> reasonTags,
    required String note,
  }) async {
    await _ensureExpiredClosed();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.status.isOpenFamily) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reviewWindowNotOpen,
        description: 'Drafts only while request is open',
      );
    }
    if (evaluatorId == evaluatedUserId) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.notEligible,
      );
    }
    final graph = await _participantGraphBuilder.build(
      beaconId: beaconId,
      authorId: beacon.author.id,
      preClosure: true,
    );
    final allowed = graph.visibility.any(
      (v) => v.evaluatorId == evaluatorId && v.participantId == evaluatedUserId,
    );
    if (!allowed) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.notEligible,
        description: 'Not an allowed draft target for this request',
      );
    }
    final target = graph.participants.firstWhere(
      (p) => p.userId == evaluatedUserId,
    );
    _validateEvaluation(
      value: value,
      reasonTags: reasonTags,
      evaluatedRole: target.role,
    );
    final csv = reasonTags.join(',');
    await _evaluationRepository.upsertEvaluation(
      beaconId: beaconId,
      evaluatorId: evaluatorId,
      evaluatedUserId: evaluatedUserId,
      value: value,
      reasonTagsCsv: csv,
      note: note,
      status: BeaconEvaluationRowStatus.draft,
    );
    return true;
  }

  Future<bool> evaluationDraftDelete({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async {
    await _ensureExpiredClosed();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.status.isOpenFamily) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reviewWindowNotOpen,
        description: 'Draft delete only while request is open',
      );
    }
    final ev = await _evaluationRepository.getEvaluation(
      beaconId: beaconId,
      evaluatorId: evaluatorId,
      evaluatedUserId: evaluatedUserId,
    );
    if (ev == null || ev.status != BeaconEvaluationRowStatus.draft) {
      return true;
    }
    await _evaluationRepository.deleteEvaluationRow(
      beaconId: beaconId,
      evaluatorId: evaluatorId,
      evaluatedUserId: evaluatedUserId,
    );
    return true;
  }

  Future<ReviewWindowStatusResult> reviewWindowStatus({
    required String beaconId,
    required String userId,
  }) async {
    await _ensureExpiredClosed();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    final beaconTitle = beacon.title;
    final w = await _evaluationRepository.getReviewWindow(beaconId);
    if (w == null) {
      return ReviewWindowStatusResult(
        beaconId: beaconId,
        hasWindow: false,
        beaconTitle: beaconTitle,
      );
    }
    final st = await _evaluationRepository.getReviewUserStatus(
      beaconId,
      userId,
    );
    final vis = await _evaluationRepository.listVisibilityForEvaluator(
      beaconId,
      userId,
    );
    final evByTarget = await _evaluationsByTargetForEvaluator(
      beaconId: beaconId,
      evaluatorId: userId,
    );
    var reviewed = 0;
    for (final v in vis) {
      if (evByTarget[v.participantId] != null) {
        reviewed++;
      }
    }
    final canCloseNow =
        w.status == 0 &&
        beacon.status == BeaconStatus.reviewOpen &&
        await _canCloseNow(beaconId: beaconId);
    return ReviewWindowStatusResult(
      beaconId: beaconId,
      hasWindow: true,
      beaconTitle: beaconTitle,
      openedAt: w.openedAt,
      closesAt: w.closesAt,
      windowComplete: w.status == 1,
      userReviewStatus: st ?? -1,
      reviewedCount: reviewed,
      totalCount: vis.length,
      extensionsUsed: w.extensionsUsed,
      canCloseNow: canCloseNow,
    );
  }

  Future<EvaluationSummaryResult> evaluationSummary({
    required String beaconId,
    required String userId,
  }) async {
    await _ensureExpiredClosed();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    final parts = await _evaluationRepository.listParticipants(beaconId);
    BeaconEvaluationParticipantRecord? me;
    for (final p in parts) {
      if (p.userId == userId) {
        me = p;
        break;
      }
    }
    final n = await _evaluationRepository.countDistinctEvaluatorsForEvaluated(
      beaconId: beaconId,
      evaluatedUserId: userId,
    );
    final rows = await _evaluationRepository.listEvaluationsForEvaluatedUser(
      beaconId: beaconId,
      evaluatedUserId: userId,
    );
    final rowInputs = rows
        .map(
          (r) => (
            value: r.value,
            reasonTagsCsv: r.reasonTags,
          ),
        )
        .toList();
    final viewerRole = me == null
        ? null
        : EvaluationParticipantRole.fromDb(me.role);
    return _buildEvaluationSummary(
      beaconStatus: beacon.status,
      distinctEvaluatorCount: n,
      rows: rowInputs,
      viewerRole: viewerRole,
    );
  }

  Future<bool> evaluationSubmit({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required List<String> reasonTags,
    required String note,
    List<String>? acknowledgedHelpTags,
  }) async {
    await _ensureExpiredClosed();
    final w = await _evaluationRepository.getReviewWindow(beaconId);
    if (w == null || w.status != 0) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reviewWindowExpired,
      );
    }
    if (w.closesAt.isBefore(DateTime.timestamp())) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reviewWindowExpired,
      );
    }
    final vis = await _evaluationRepository.listVisibilityForEvaluator(
      beaconId,
      evaluatorId,
    );
    final ok = vis.any((v) => v.participantId == evaluatedUserId);
    if (!ok) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.notEligible,
      );
    }
    if (evaluatorId == evaluatedUserId) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.notEligible,
      );
    }

    final parts = await _evaluationRepository.listParticipants(beaconId);
    final roleOfEvaluated = EvaluationParticipantRole.fromDb(
      parts.firstWhere((p) => p.userId == evaluatedUserId).role,
    );

    _validateEvaluation(
      value: value,
      reasonTags: reasonTags,
      evaluatedRole: roleOfEvaluated,
    );

    final csv = reasonTags.join(',');

    await _evaluationRepository.upsertEvaluation(
      beaconId: beaconId,
      evaluatorId: evaluatorId,
      evaluatedUserId: evaluatedUserId,
      value: value,
      reasonTagsCsv: csv,
      note: note,
    );

    final st = await _evaluationRepository.getReviewUserStatus(
      beaconId,
      evaluatorId,
    );
    if (st == 0) {
      await _evaluationRepository.setReviewUserStatus(
        beaconId: beaconId,
        userId: evaluatorId,
        status: 1,
      );
    }

    if (acknowledgedHelpTags != null && acknowledgedHelpTags.isNotEmpty) {
      try {
        await _capabilityCase.recordCloseAcknowledgement(
          beaconId: beaconId,
          observerId: evaluatorId,
          subjectId: evaluatedUserId,
          slugs: acknowledgedHelpTags,
        );
      } catch (e, st) {
        logger.warning('recordCloseAcknowledgement failed', e, st);
        // non-fatal: capability event failure must not block evaluation submission
      }
    }

    return true;
  }

  void _validateEvaluation({
    required int value,
    required List<String> reasonTags,
    required EvaluationParticipantRole evaluatedRole,
  }) {
    if (value < 0 || value > 5) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.invalidEvaluationValue,
      );
    }
    if (BeaconEvaluationValue.requiresReasonTag(value) && reasonTags.isEmpty) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reasonTagRequired,
      );
    }
    if (!BeaconEvaluationValue.allowsReasonTag(value) &&
        reasonTags.isNotEmpty) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.invalidReasonTags,
      );
    }
    final allowed = _allowedTagsForValue(value, evaluatedRole);
    for (final t in reasonTags) {
      if (!allowed.contains(t)) {
        throw EvaluationException(
          evaluationCode: EvaluationExceptionCode.invalidReasonTags,
          description: 'Invalid reason tag for role/value',
        );
      }
    }
  }

  static Set<String> _allowedTagsForValue(
    int value,
    EvaluationParticipantRole role,
  ) {
    if (value == BeaconEvaluationValue.noBasis) {
      return {};
    }
    if (value == BeaconEvaluationValue.neg2 ||
        value == BeaconEvaluationValue.neg1) {
      return EvaluationReasonTags.allowedForRoleAndSign(role, isNegative: true);
    }
    if (value == BeaconEvaluationValue.pos2 ||
        value == BeaconEvaluationValue.pos1) {
      return EvaluationReasonTags.allowedForRoleAndSign(
        role,
        isNegative: false,
      );
    }
    return EvaluationReasonTags.allowedUnionForRole(role);
  }

  Future<bool> evaluationFinalize({
    required String beaconId,
    required String userId,
  }) async {
    await _ensureExpiredClosed();
    final w = await _evaluationRepository.getReviewWindow(beaconId);
    if (w == null || w.status != 0) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reviewWindowExpired,
      );
    }
    final st = await _evaluationRepository.getReviewUserStatus(
      beaconId,
      userId,
    );
    if (st == null) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.notEligible,
      );
    }
    // Idempotent: double "Finish", or Finish after Skip, should succeed.
    if (st == 2 || st == 3) {
      return true;
    }
    await _evaluationRepository.setReviewUserStatus(
      beaconId: beaconId,
      userId: userId,
      status: 2,
    );
    return true;
  }

  Future<bool> evaluationSkip({
    required String beaconId,
    required String userId,
  }) async {
    await _ensureExpiredClosed();
    final w = await _evaluationRepository.getReviewWindow(beaconId);
    if (w == null || w.status != 0) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reviewWindowExpired,
      );
    }
    final st = await _evaluationRepository.getReviewUserStatus(
      beaconId,
      userId,
    );
    if (st == null) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.notEligible,
      );
    }
    await _evaluationRepository.setReviewUserStatus(
      beaconId: beaconId,
      userId: userId,
      status: 3,
    );
    return true;
  }
}
