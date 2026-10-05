import 'dart:math';

import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';

/// «Who'll take it?» (baton) selection rule — plan §1.3/B2
/// (`docs/plans/baton-who-takes-it-plan.md`).
abstract final class BatonSelectionPolicy {
  BatonSelectionPolicy._();

  static const minCandidates = 1;
  static const maxCandidates = 12;
  static const minTier = 1;
  static const maxTier = 3;

  /// Auto pick: the lowest tier number among the people who said «can help»
  /// (and are still eligible to be considered — callers pass only admitted
  /// candidates), then a uniform-random pick among that tier.
  ///
  /// Throws [BatonTakerNotAvailableException] when no candidate is eligible.
  static RoomBatonCandidate pick(
    List<RoomBatonCandidate> candidates, {
    Random? random,
  }) {
    final eligible = candidates
        .where((c) => c.response == BatonResponse.canHelp)
        .toList(growable: false);
    if (eligible.isEmpty) {
      throw const BatonTakerNotAvailableException();
    }
    final lowestTier = eligible
        .map((c) => c.tier)
        .reduce((a, b) => a < b ? a : b);
    final atLowestTier = eligible
        .where((c) => c.tier == lowestTier)
        .toList(growable: false);
    final rnd = random ?? Random.secure();
    return atLowestTier[rnd.nextInt(atLowestTier.length)];
  }

  /// Validates a manual pick: [userId] must be eligible (said «can help» and
  /// is among [candidates]), otherwise [BatonTakerNotAvailableException].
  static RoomBatonCandidate pickManual(
    List<RoomBatonCandidate> candidates,
    String userId,
  ) {
    final match = candidates
        .where((c) => c.userId == userId && c.response == BatonResponse.canHelp)
        .toList(growable: false);
    if (match.isEmpty) {
      throw const BatonTakerNotAvailableException();
    }
    return match.single;
  }

  /// Validates a baton's candidate list at creation time (D7):
  /// 1–12 candidates, each an admitted room member, never the author, no
  /// duplicates, each tier in 1–3.
  static void validateCandidates({
    required String authorId,
    required List<({String userId, int tier})> candidates,
    required Set<String> admittedIds,
  }) {
    if (candidates.length < minCandidates || candidates.length > maxCandidates) {
      throw const BatonInvalidCandidatesException(
        description:
            'Candidate count must be between $minCandidates and $maxCandidates',
      );
    }
    final seen = <String>{};
    for (final candidate in candidates) {
      if (candidate.userId == authorId) {
        throw const BatonInvalidCandidatesException(
          description: 'The author cannot be a candidate',
        );
      }
      if (!seen.add(candidate.userId)) {
        throw const BatonInvalidCandidatesException(
          description: 'Duplicate candidate',
        );
      }
      if (!admittedIds.contains(candidate.userId)) {
        throw const BatonInvalidCandidatesException(
          description: 'Candidate is not admitted to the room',
        );
      }
      if (candidate.tier < minTier || candidate.tier > maxTier) {
        throw const BatonInvalidCandidatesException(
          description: 'Tier must be between $minTier and $maxTier',
        );
      }
    }
  }
}
