import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/evaluation/evaluation_visibility_rules.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

import 'evaluation_participant_draft.dart';

typedef EvaluationParticipantGraphBundle = ({
  String authorId,
  List<EvaluationParticipantDraft> participants,
  List<EvaluationVisibilityPair> visibility,
  Map<String, ForwardEdgeEntity> latestEdgeToCommitter,
});

const _participationEndedSuffix = ' — participation ended';

@Injectable(order: 2)
final class EvaluationParticipantGraphBuilder {
  EvaluationParticipantGraphBuilder(
    this._commitmentRepository,
    this._helpOfferRepository,
    this._forwardEdgeRepository,
    this._userRepository,
  );

  final CommitmentRepositoryPort _commitmentRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;
  final ForwardEdgeRepositoryPort _forwardEdgeRepository;
  final UserRepositoryPort _userRepository;

  Future<EvaluationParticipantGraphBundle> build({
    required String beaconId,
    required String authorId,
    required bool preClosure,
  }) async {
    final eventsByUser = await _commitmentRepository.eventsByUser(beaconId);
    final helpOffers = await _helpOfferRepository.fetchAllByBeaconId(beaconId);
    final offerByUser = {for (final offer in helpOffers) offer.userId: offer};
    final activeByUser = {
      for (final offer in helpOffers)
        if (offer.isActive) offer.userId: true,
    };

    final everAck = <String>{
      for (final entry in eventsByUser.entries)
        if (everAcknowledged(entry.value)) entry.key,
    };
    final current = <String>{
      for (final entry in eventsByUser.entries)
        if (hasCurrentStake(
          entry.value,
          hasActiveOffer: activeByUser[entry.key] ?? false,
        ))
          entry.key,
    };

    final edges = await _forwardEdgeRepository.fetchByBeaconId(beaconId);

    final latestEdgeToCommitter = <String, ForwardEdgeEntity>{};
    for (final userId in everAck) {
      final toC = edges.where((e) => e.recipientId == userId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (toC.isNotEmpty) {
        latestEdgeToCommitter[userId] = toC.first;
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
            ? 'Created this request'
            : 'Created and closed the request',
        causalHint: preClosure
            ? 'Author — created this request'
            : 'Author — created and closed the request',
      ),
    ];

    final sortedEverAck = everAck.toList()
      ..sort((a, b) {
        final aOffer = offerByUser[a];
        final bOffer = offerByUser[b];
        if (aOffer == null && bOffer == null) return a.compareTo(b);
        if (aOffer == null) return 1;
        if (bOffer == null) return -1;
        return aOffer.createdAt.compareTo(bOffer.createdAt);
      });

    for (final userId in sortedEverAck) {
      final offer = offerByUser[userId];
      if (offer == null) continue;

      final role = current.contains(userId)
          ? EvaluationParticipantRole.committer
          : EvaluationParticipantRole.formerCommitter;
      final edge = latestEdgeToCommitter[userId];
      String? forwarderName;
      if (edge != null && edge.senderId != authorId) {
        forwarderName = (await _userRepository.getById(edge.senderId)).displayName;
      }
      participants.add(
        _committerParticipant(
          userId: userId,
          offer: offer,
          role: role,
          forwarderDisplayName: forwarderName,
        ),
      );
    }

    for (final fid in forwarderIds) {
      final linkedCommitters = latestEdgeToCommitter.entries
          .where((e) => e.value.senderId == fid && e.key != authorId)
          .map((e) => e.key)
          .toList();
      final names = <String>[];
      for (final cid in linkedCommitters) {
        names.add((await _userRepository.getById(cid)).displayName);
      }
      final namesStr = names.join(', ');
      participants.add(
        EvaluationParticipantDraft(
          userId: fid,
          role: EvaluationParticipantRole.forwarder,
          contributionSummary: 'Forwarded the request toward committer(s)',
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

EvaluationParticipantDraft _committerParticipant({
  required String userId,
  required HelpOfferEntity offer,
  required EvaluationParticipantRole role,
  required String? forwarderDisplayName,
}) {
  final localDate = offer.createdAt.toLocal();
  final d =
      '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
  final baseSummary =
      'Committed on $d${offer.message.isNotEmpty ? ': ${offer.message}' : ''}';
  final baseHint = forwarderDisplayName != null
      ? 'Committer — received via forward from $forwarderDisplayName; committed in this request'
      : 'Committer — committed in this request';
  final isFormer = role == EvaluationParticipantRole.formerCommitter;
  return EvaluationParticipantDraft(
    userId: userId,
    role: role,
    contributionSummary: isFormer
        ? '$baseSummary$_participationEndedSuffix'
        : baseSummary,
    causalHint:
        isFormer ? '$baseHint$_participationEndedSuffix' : baseHint,
  );
}
