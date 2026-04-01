import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/data/repository/fcm_remote_repository.dart';
import 'package:tentura_server/data/repository/fcm_token_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/evaluation/evaluation_reason_tags.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

/// Post-beacon evaluation (Phase 1): open window, visibility, private rows, summaries.
@Singleton(order: 2)
class EvaluationCase {
  EvaluationCase(
    this._beaconRepository,
    this._commitmentRepository,
    this._forwardEdgeRepository,
    this._evaluationRepository,
    this._userRepository,
    this._fcmRemoteRepository,
    this._fcmTokenRepository,
  );

  final BeaconRepository _beaconRepository;
  final CommitmentRepository _commitmentRepository;
  final ForwardEdgeRepository _forwardEdgeRepository;
  final EvaluationRepository _evaluationRepository;
  final UserRepository _userRepository;
  final FcmRemoteRepository _fcmRemoteRepository;
  final FcmTokenRepository _fcmTokenRepository;

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

    final commitments = await _commitmentRepository.fetchByBeaconId(beaconId);
    final edges = await _forwardEdgeRepository.fetchByBeaconId(beaconId);

    final authorId = beacon.author.id;
    final committerIds = commitments.map((c) => c.userId).toList();

    final latestEdgeToCommitter = <String, ForwardEdgeEntity>{};
    for (final c in committerIds) {
      final toC = edges.where((e) => e.recipientId == c).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (toC.isNotEmpty) {
        latestEdgeToCommitter[c] = toC.first;
      }
    }

    final forwarderIds = <String>{};
    for (final entry in latestEdgeToCommitter.entries) {
      final sender = entry.value.senderId;
      if (sender != authorId) {
        forwarderIds.add(sender);
      }
    }

    final participants = <_ParticipantDraft>[];

    participants.add(
      _ParticipantDraft(
        userId: authorId,
        role: EvaluationParticipantRole.author,
        contributionSummary: 'Created and closed the beacon',
        causalHint: 'Author — created and closed the beacon',
      ),
    );

    for (final c in commitments) {
      final localDate = c.createdAt.toLocal();
      final d =
          '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
      participants.add(
        _ParticipantDraft(
          userId: c.userId,
          role: EvaluationParticipantRole.committer,
          contributionSummary:
              'Committed on $d${c.message.isNotEmpty ? ': ${c.message}' : ''}',
          causalHint: 'Committer — committed in this beacon',
        ),
      );
      // enrich causal hint with forwarder name if any
      final edge = latestEdgeToCommitter[c.userId];
      if (edge != null && edge.senderId != authorId) {
        final fs = await _userRepository.getById(edge.senderId);
        participants[participants.length - 1] = _ParticipantDraft(
          userId: c.userId,
          role: EvaluationParticipantRole.committer,
          contributionSummary:
              'Committed on $d${c.message.isNotEmpty ? ': ${c.message}' : ''}',
          causalHint:
              'Committer — received via forward from ${fs.title}; committed in this beacon',
        );
      }
    }

    for (final fid in forwarderIds) {
      final linkedCommitters = latestEdgeToCommitter.entries
          .where((e) => e.value.senderId == fid && e.key != authorId)
          .map((e) => e.key)
          .toList();
      final names = <String>[];
      for (final cid in linkedCommitters) {
        names.add((await _userRepository.getById(cid)).title);
      }
      final namesStr = names.join(', ');
      participants.add(
        _ParticipantDraft(
          userId: fid,
          role: EvaluationParticipantRole.forwarder,
          contributionSummary: 'Forwarded the beacon toward committer(s)',
          causalHint:
              'Forwarder — adjacent on the path to $namesStr, who committed',
        ),
      );
    }

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

    final visibility = _buildVisibility(
      authorId: authorId,
      participants: participants,
      latestEdgeToCommitter: latestEdgeToCommitter,
    );

    for (final v in visibility) {
      await _evaluationRepository.insertVisibility(
        beaconId: beaconId,
        evaluatorId: v.evaluatorId,
        participantId: v.participantId,
      );
    }

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

  static List<_Vis> _buildVisibility({
    required String authorId,
    required List<_ParticipantDraft> participants,
    required Map<String, ForwardEdgeEntity> latestEdgeToCommitter,
  }) {
    final byId = {for (final p in participants) p.userId: p};
    final out = <_Vis>[];

    void add(String a, String b) {
      if (a != b) {
        out.add(_Vis(evaluatorId: a, participantId: b));
      }
    }

    for (final e in participants) {
      final eid = e.userId;
      if (e.role == EvaluationParticipantRole.author) {
        for (final p in participants) {
          if (p.userId == authorId) {
            continue;
          }
          add(eid, p.userId);
        }
        continue;
      }
      if (e.role == EvaluationParticipantRole.committer) {
        add(eid, authorId);
        final edge = latestEdgeToCommitter[e.userId];
        if (edge != null) {
          final fwd = edge.senderId;
          if (fwd != authorId && byId.containsKey(fwd)) {
            add(eid, fwd);
          }
        }
        continue;
      }
      if (e.role == EvaluationParticipantRole.forwarder) {
        for (final entry in latestEdgeToCommitter.entries) {
          if (entry.value.senderId == eid) {
            add(eid, entry.key);
          }
        }
      }
    }

    return out;
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

    final out = <Map<String, dynamic>>[];
    for (final v in vis) {
      final pid = v.participantId;
      final row = partByUser[pid];
      if (row == null) {
        continue;
      }
      final u = await _userRepository.getById(pid);
      final ev = await _evaluationRepository.getEvaluation(
        beaconId: beaconId,
        evaluatorId: evaluatorId,
        evaluatedUserId: pid,
      );
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
            : ev.reasonTags.split(',').where((s) => s.isNotEmpty).toList(),
        'note': ev?.note ?? '',
      });
    }
    return out;
  }

  Future<Map<String, dynamic>> reviewWindowStatus({
    required String beaconId,
    required String userId,
  }) async {
    await _ensureExpiredClosed();
    final w = await _evaluationRepository.getReviewWindow(beaconId);
    if (w == null) {
      return {'beaconId': beaconId, 'hasWindow': false};
    }
    final st = await _evaluationRepository.getReviewUserStatus(beaconId, userId);
    final vis = await _evaluationRepository.listVisibilityForEvaluator(
      beaconId,
      userId,
    );
    var reviewed = 0;
    for (final v in vis) {
      final ev = await _evaluationRepository.getEvaluation(
        beaconId: beaconId,
        evaluatorId: userId,
        evaluatedUserId: v.participantId,
      );
      if (ev != null) {
        reviewed++;
      }
    }
    return {
      'beaconId': beaconId,
      'hasWindow': true,
      'openedAt': w.openedAt.dateTime.toUtc().toIso8601String(),
      'closesAt': w.closesAt.dateTime.toUtc().toIso8601String(),
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
    if (beacon.state != 6) {
      return {
        'suppressed': true,
        'tone': 'mixed',
        'message': '',
        'topReasonTags': <String>[],
      };
    }
    final n = await _evaluationRepository.countDistinctEvaluatorsForEvaluated(
      beaconId: beaconId,
      evaluatedUserId: userId,
    );
    final rows = await _evaluationRepository.listEvaluationsForEvaluatedUser(
      beaconId: beaconId,
      evaluatedUserId: userId,
    );
    if (rows.isEmpty) {
      return {
        'suppressed': true,
        'tone': 'mixed',
        'message': 'No feedback',
        'topReasonTags': <String>[],
      };
    }
    if (n < 3) {
      return {
        'suppressed': true,
        'tone': _toneFromRows(rows),
        'message': 'Feedback in this beacon (details limited for privacy)',
        'topReasonTags': <String>[],
      };
    }
    var neg2 = 0;
    var neg1 = 0;
    var zero = 0;
    var pos1 = 0;
    var pos2 = 0;
    final tagCounts = <String, int>{};
    for (final r in rows) {
      switch (r.value) {
        case BeaconEvaluationValue.neg2:
          neg2++;
        case BeaconEvaluationValue.neg1:
          neg1++;
        case BeaconEvaluationValue.zero:
          zero++;
        case BeaconEvaluationValue.pos1:
          pos1++;
        case BeaconEvaluationValue.pos2:
          pos2++;
        default:
          break;
      }
      for (final t in r.reasonTags.split(',')) {
        if (t.isEmpty) {
          continue;
        }
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }
    final topTags = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {
      'suppressed': false,
      'tone': _toneFromRows(rows),
      'message': '',
      'topReasonTags': topTags.take(5).map((e) => e.key).toList(),
      'neg2': neg2,
      'neg1': neg1,
      'zero': zero,
      'pos1': pos1,
      'pos2': pos2,
    };
  }

  static String _toneFromRows(List<BeaconEvaluation> rows) {
    var score = 0;
    for (final r in rows) {
      score += switch (r.value) {
        BeaconEvaluationValue.neg2 => -2,
        BeaconEvaluationValue.neg1 => -1,
        BeaconEvaluationValue.zero => 0,
        BeaconEvaluationValue.pos1 => 1,
        BeaconEvaluationValue.pos2 => 2,
        _ => 0,
      };
    }
    if (score > 0) {
      return 'positive';
    }
    if (score < 0) {
      return 'negative';
    }
    return 'mixed';
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
    if (w.closesAt.dateTime.isBefore(DateTime.timestamp())) {
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
    if (st == 2 || st == 3) {
      throw EvaluationException(
        evaluationCode: EvaluationExceptionCode.evaluationAlreadySubmitted,
      );
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
    await _evaluationRepository.setReviewUserStatus(
      beaconId: beaconId,
      userId: userId,
      status: 3,
    );
    return true;
  }
}

class _ParticipantDraft {
  _ParticipantDraft({
    required this.userId,
    required this.role,
    required this.contributionSummary,
    required this.causalHint,
  });

  final String userId;
  final EvaluationParticipantRole role;
  final String contributionSummary;
  final String causalHint;
}

class _Vis {
  _Vis({required this.evaluatorId, required this.participantId});

  final String evaluatorId;
  final String participantId;
}
