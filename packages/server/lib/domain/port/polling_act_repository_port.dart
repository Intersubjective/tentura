// ignore: one_member_abstracts -- injectable port with a single repository entry point
abstract class PollingActRepositoryPort {
  /// Record or update a vote.
  ///
  /// Behaviour depends on [pollType] and [allowRevote]:
  /// - single + revote: replace any existing vote for this poll
  /// - single + no-revote: no-op if already voted
  /// - multiple + revote: toggle (remove if already selected, add if not)
  /// - multiple + no-revote: add only if not already selected
  /// - range: upsert score on (author_id, polling_variant_id); honours allowRevote same as multiple
  Future<void> upsert({
    required String authorId,
    required String pollingId,
    required List<String> variantIds,
    required String pollType,
    required bool allowRevote,
    int? score,
  });
}
