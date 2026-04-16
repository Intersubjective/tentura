import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/evaluation/evaluation_visibility_rules.dart';

import 'evaluation_participant_draft.dart';

typedef EvaluationParticipantGraphBundle = ({
  String authorId,
  List<EvaluationParticipantDraft> participants,
  List<EvaluationVisibilityPair> visibility,
  Map<String, ForwardEdgeEntity> latestEdgeToCommitter,
});

@Injectable(order: 2)
final class EvaluationParticipantGraphBuilder {
  EvaluationParticipantGraphBuilder(
    this._commitmentRepository,
    this._forwardEdgeRepository,
    this._userRepository,
  );

  final CommitmentRepositoryPort _commitmentRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final UserRepositoryPort _userRepository;

  Future<EvaluationParticipantGraphBundle> build({
    required String beaconId,
    required String authorId,
    required bool preClosure,
  }) async {
    final commitments = await _commitmentRepository.fetchByBeaconId(beaconId);
    final edges = await _forwardEdgeRepository.fetchByBeaconId(beaconId);

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

    final participants = <EvaluationParticipantDraft>[
      EvaluationParticipantDraft(
        userId: authorId,
        role: EvaluationParticipantRole.author,
        contributionSummary: preClosure
            ? 'Created this beacon'
            : 'Created and closed the beacon',
        causalHint: preClosure
            ? 'Author — created this beacon'
            : 'Author — created and closed the beacon',
      ),
    ];

    for (final c in commitments) {
      final localDate = c.createdAt.toLocal();
      final d =
          '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
      participants.add(
        EvaluationParticipantDraft(
          userId: c.userId,
          role: EvaluationParticipantRole.committer,
          contributionSummary:
              'Committed on $d${c.message.isNotEmpty ? ': ${c.message}' : ''}',
          causalHint: 'Committer — committed in this beacon',
        ),
      );
      final edge = latestEdgeToCommitter[c.userId];
      if (edge != null && edge.senderId != authorId) {
        final fs = await _userRepository.getById(edge.senderId);
        participants[participants.length - 1] = EvaluationParticipantDraft(
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
        EvaluationParticipantDraft(
          userId: fid,
          role: EvaluationParticipantRole.forwarder,
          contributionSummary: 'Forwarded the beacon toward committer(s)',
          causalHint:
              'Forwarder — adjacent on the path to $namesStr, who committed',
        ),
      );
    }

    final visibility = buildEvaluationVisibility(
      authorId: authorId,
      participants: participants
          .map(
            (p) => EvaluationVisibilityParticipant(
              userId: p.userId,
              role: p.role,
            ),
          )
          .toList(),
      latestEdgeToCommitter: latestEdgeToCommitter,
    );

    return (
      authorId: authorId,
      participants: participants,
      visibility: visibility,
      latestEdgeToCommitter: latestEdgeToCommitter,
    );
  }
}
