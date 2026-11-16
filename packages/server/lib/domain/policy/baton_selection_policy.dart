import 'dart:math';

import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';

/// Who takes it: [takerId] and, for a pair, the partner [coTakerId].
class BatonPick {
  const BatonPick({required this.takerId, this.coTakerId});

  final String takerId;
  final String? coTakerId;

  String get userId => takerId;
}

/// «Who'll take it?» (baton) selection rule — plan §1.3/B2
/// (`docs/plans/baton-who-takes-it-plan.md`).
abstract final class BatonSelectionPolicy {
  BatonSelectionPolicy._();

  static const minCandidates = 1;
  static const maxCandidates = 12;
  static const minTier = 1;
  static const maxTier = 3;

  /// Auto pick: the lowest tier number among the eligible entries (a solo
  /// «can help» candidate, or an accepted pair counted as one entry), then a
  /// uniform-random pick among that tier.
  ///
  /// Throws [BatonTakerNotAvailableException] when no entry is eligible.
  static BatonPick pick(
    List<RoomBatonCandidate> candidates, {
    Random? random,
  }) {
    final eligible = _entries(candidates);
    if (eligible.isEmpty) {
      throw const BatonTakerNotAvailableException();
    }
    final lowestTier = eligible
        .map((e) => e.tier)
        .reduce((a, b) => a < b ? a : b);
    final atLowestTier = eligible
        .where((e) => e.tier == lowestTier)
        .toList(growable: false);
    final rnd = random ?? Random.secure();
    return atLowestTier[rnd.nextInt(atLowestTier.length)].pick;
  }

  /// Validates a manual pick: [userId] must belong to an eligible entry (said
  /// «can help» alone, or is either member of an accepted pair), otherwise
  /// [BatonTakerNotAvailableException].
  static BatonPick pickManual(
    List<RoomBatonCandidate> candidates,
    String userId,
  ) {
    final entries = _entries(candidates);
    for (final e in entries) {
      if (e.pick.takerId == userId) {
        return e.pick;
      }
    }
    for (final e in entries) {
      if (e.pick.coTakerId == userId) {
        return e.pick;
      }
    }
    throw const BatonTakerNotAvailableException();
  }

  /// Solo «can help» rows and accepted pairs; a mutual pair is one entry at
  /// the lower tier, taken by the earlier answer. A pending pair is skipped.
  static List<({int tier, BatonPick pick})> _entries(
    List<RoomBatonCandidate> candidates,
  ) {
    final byUser = {for (final c in candidates) c.userId: c};
    final entries = <({int tier, BatonPick pick})>[];
    final seen = <String>{};
    for (final c in candidates) {
      if (c.response != BatonResponse.canHelp || !seen.add(c.userId)) {
        continue;
      }
      final partnerId = c.partnerUserId;
      switch (c.partnerResponse) {
        case null || BatonPartnerResponse.declined:
          entries.add((tier: c.tier, pick: BatonPick(takerId: c.userId)));
        case BatonPartnerResponse.pending:
          break;
        case BatonPartnerResponse.accepted when partnerId != null:
          final other = byUser[partnerId];
          final mutual =
              other != null &&
              other.partnerUserId == c.userId &&
              other.partnerResponse == BatonPartnerResponse.accepted;
          if (!mutual) {
            entries.add((
              tier: c.tier,
              pick: BatonPick(takerId: c.userId, coTakerId: partnerId),
            ));
            break;
          }
          seen.add(partnerId);
          final otherFirst =
              other.respondedAt != null &&
              (c.respondedAt == null ||
                  other.respondedAt!.isBefore(c.respondedAt!));
          entries.add((
            tier: c.tier < other.tier ? c.tier : other.tier,
            pick: otherFirst
                ? BatonPick(takerId: other.userId, coTakerId: c.userId)
                : BatonPick(takerId: c.userId, coTakerId: other.userId),
          ));
        case BatonPartnerResponse.accepted:
          break;
      }
    }
    return entries;
  }

  /// Validates a baton's candidate list at creation time (D7):
  /// 1–12 candidates, each an admitted room member, never the author, no
  /// duplicates, each tier in 1–3.
  static void validateCandidates({
    required String authorId,
    required List<({String userId, int tier})> candidates,
    required Set<String> admittedIds,
  }) {
    if (candidates.length < minCandidates ||
        candidates.length > maxCandidates) {
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
