import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/evaluation/evaluation_reason_tags.dart';
import 'package:tentura_server/domain/evaluation/evaluation_summary_rules.dart';
import 'package:tentura_server/domain/evaluation/evaluation_visibility_rules.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

import 'evaluation/evaluation_draft_purger.dart';
import 'evaluation/evaluation_participant_graph_builder.dart';
import 'evaluation/evaluation_prompt_variant.dart';
import '_use_case_base.dart';

/// Post-beacon evaluation (Phase 1): open window, visibility, private rows, summaries.
@Singleton(order: 2)
final class EvaluationCase extends UseCaseBase {
  EvaluationCase(
    this._beaconRepository,
    this._forwardEdgeRepository,
    this._evaluationRepository,
    this._userRepository,
    this._fcmRemoteRepository,
    this._fcmTokenRepository,
    this._participantGraphBuilder,
    this._draftPurger, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final EvaluationRepositoryPort _evaluationRepository;
  final UserRepositoryPort _userRepository;
  final FcmRemoteRepositoryPort _fcmRemoteRepository;
  final FcmTokenRepositoryPort _fcmTokenRepository;
  final EvaluationParticipantGraphBuilder _participantGraphBuilder;
  final EvaluationDraftPurger _draftPurger;

  static const Duration _reviewWindowDuration = Duration(days: 7);

  Future<void> _ensureExpiredClosed() => _evaluationRepository.closeExpiredWindows();

  /// Author closes beacon and opens the Phase 1 review window (state 5).
  Future<Map<String, dynamic>> beaconCloseWithReview({
    required String beaconId,
    required String userId,
  }) async {
    await _ensureExpiredClosed();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.state != 0) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.beaconNotClosable,
        description: 'Beacon must be open to close with review',
      );
    }
    if (beacon.author.id != userId) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.notEligible,
        description: 'Only the author can close with review',
      );
    }

    final existing = await _evaluationRepository.getReviewWindow(beaconId);
    if (existing != null) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.beaconNotClosable,
        description: 'Review already exists for this beacon',
      );
    }

    final graph = await _participantGraphBuilder.build(
      beaconId: beaconId,
      authorId: beacon.author.id,
      preClosure: false,
    );
    final participants = graph.participants;
    final visibility = graph.visibility;

    final openedAt = DateTime.timestamp();
    final closesAt = openedAt.add(_reviewWindowDuration);

    await _beaconRepository.updateBeaconState(beaconId: beaconId, state: 5);

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

    await _notifyReviewOpened(
      beaconId: beaconId,
      beaconTitle: beacon.title,
      recipientUserIds: participantIds,
    );

    return {
      'id': beaconId,
      'state': 5,
      'closesAt': closesAt.toUtc().toIso8601String(),
    };
  }

  Future<void> _notifyReviewOpened({
    required String beaconId,
    required String beaconTitle,
    required Set<String> recipientUserIds,
  }) async {
    for (final uid in recipientUserIds) {
      final tokens = await _fcmTokenRepository.getTokensByUserId(uid);
      final tokenStrings = tokens.map((t) => t.token).toList();
      if (tokenStrings.isEmpty) {
        continue;
      }
      await _fcmRemoteRepository.sendChatNotification(
        fcmTokens: tokenStrings,
        message: FcmNotificationEntity(
          title: 'Beacon closed — review contributions',
          body: beaconTitle.isNotEmpty ? beaconTitle : 'Private feedback window',
          actionUrl: '/beacon/$beaconId',
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> evaluationParticipants({
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
    final latestEdgeToCommitter =
        await _latestEdgesToCommitters(beaconId: beaconId, committerIds: committerIds);

    final evByTarget = await _evaluationsByTargetForEvaluator(
      beaconId: beaconId,
      evaluatorId: evaluatorId,
    );

    final out = <Map<String, dynamic>>[];
    for (final v in vis) {
      final pid = v.participantId;
      final row = partByUser[pid];
      if (row == null) {
        continue;
      }
      final u = await _userRepository.getById(pid);
      final ev = evByTarget[pid];
      out.add({
        'userId': pid,
        'title': u.title,
        'imageId': u.image?.id ?? '',
        'role': row.role,
        'contributionSummary': row.contributionSummary,
        'causalHint': row.causalHint,
        'value': ev?.value,
        'reasonTags': ev == null || ev.reasonTags.isEmpty
            ? <String>[]
            : ev.reasonTags
                  .split(',')
                  .where((String s) => s.isNotEmpty)
                  .toList(),
        'note': ev?.note ?? '',
        'promptVariant': evaluationPromptVariantForPair(
          evaluatorId: evaluatorId,
          evaluatedRoleDb: row.role,
          evaluatedUserId: pid,
          latestEdgeToCommitter: latestEdgeToCommitter,
        ),
      });
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
  Future<List<Map<String, dynamic>>> evaluationDraftParticipants({
    required String beaconId,
    required String evaluatorId,
  }) async {
    await _ensureExpiredClosed();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.state != 0) {
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
    final out = <Map<String, dynamic>>[];
    for (final v in graph.visibility) {
      if (v.evaluatorId != evaluatorId) {
        continue;
      }
      final pid = v.participantId;
      final row = byId[pid];
      if (row == null) {
        continue;
      }
      final u = await _userRepository.getById(pid);
      final ev = evByTarget[pid];
      final useEv =
          ev != null && ev.status == BeaconEvaluationRowStatus.draft ? ev : null;
      out.add({
        'userId': pid,
        'title': u.title,
        'imageId': u.image?.id ?? '',
        'role': row.role.dbValue,
        'contributionSummary': row.contributionSummary,
        'causalHint': row.causalHint,
        'value': useEv?.value,
        'reasonTags': useEv == null || useEv.reasonTags.isEmpty
            ? <String>[]
            : useEv.reasonTags
                  .split(',')
                  .where((String s) => s.isNotEmpty)
                  .toList(),
        'note': useEv?.note ?? '',
        'promptVariant': evaluationPromptVariantForPair(
          evaluatorId: evaluatorId,
          evaluatedRoleDb: row.role.dbValue,
          evaluatedUserId: pid,
          latestEdgeToCommitter: graph.latestEdgeToCommitter,
        ),
      });
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> evaluationDrafts({
    required String beaconId,
    required String evaluatorId,
  }) async {
    await _ensureExpiredClosed();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.state != 0) {
      return [];
    }
    final rows = await _evaluationRepository.listDraftRowsForBeacon(beaconId);
    final mine = rows.where((r) => r.evaluatorId == evaluatorId).toList();
    final out = <Map<String, dynamic>>[];
    for (final r in mine) {
      out.add({
        'evaluatedUserId': r.evaluatedUserId,
        'value': r.value,
        'reasonTags': r.reasonTags.isEmpty
            ? <String>[]
            : r.reasonTags
                  .split(',')
                  .where((String s) => s.isNotEmpty)
                  .toList(),
        'note': r.note,
      });
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
    if (beacon.state != 0) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reviewWindowNotOpen,
        description: 'Drafts only while beacon is open',
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
        description: 'Not an allowed draft target for this beacon',
      );
    }
    final target = graph.participants.firstWhere((p) => p.userId == evaluatedUserId);
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
    if (beacon.state != 0) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reviewWindowNotOpen,
        description: 'Draft delete only while beacon is open',
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

  Future<Map<String, dynamic>> reviewWindowStatus({
    required String beaconId,
    required String userId,
  }) async {
    await _ensureExpiredClosed();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    final beaconTitle = beacon.title;
    final w = await _evaluationRepository.getReviewWindow(beaconId);
    if (w == null) {
      return {
        'beaconId': beaconId,
        'hasWindow': false,
        'beaconTitle': beaconTitle,
      };
    }
    final st = await _evaluationRepository.getReviewUserStatus(beaconId, userId);
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
    return {
      'beaconId': beaconId,
      'hasWindow': true,
      'beaconTitle': beaconTitle,
      'openedAt': w.openedAt.toUtc().toIso8601String(),
      'closesAt': w.closesAt.toUtc().toIso8601String(),
      'windowComplete': w.status == 1,
      'userReviewStatus': st ?? -1,
      'reviewedCount': reviewed,
      'totalCount': vis.length,
    };
  }

  Future<Map<String, dynamic>> evaluationSummary({
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
    final viewerRole =
        me == null ? null : EvaluationParticipantRole.fromDb(me.role);
    return buildEvaluationSummaryGraphqlPayload(
      beaconState: beacon.state,
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
    if (BeaconEvaluationValue.requiresReasonTag(value) &&
        reasonTags.isEmpty) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.reasonTagRequired,
      );
    }
    if (!BeaconEvaluationValue.allowsReasonTag(value) && reasonTags.isNotEmpty) {
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
    if (value == BeaconEvaluationValue.neg2 || value == BeaconEvaluationValue.neg1) {
      return EvaluationReasonTags.allowedForRoleAndSign(role, isNegative: true);
    }
    if (value == BeaconEvaluationValue.pos2 || value == BeaconEvaluationValue.pos1) {
      return EvaluationReasonTags.allowedForRoleAndSign(role, isNegative: false);
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
    final st = await _evaluationRepository.getReviewUserStatus(beaconId, userId);
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
    final st = await _evaluationRepository.getReviewUserStatus(beaconId, userId);
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
