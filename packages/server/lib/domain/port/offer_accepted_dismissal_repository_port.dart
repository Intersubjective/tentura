/// B077b — the helper's account-wide dismissals of the «Your help was
/// accepted» event sub-card.
abstract interface class OfferAcceptedDismissalRepositoryPort {
  /// Records that [userId] dismissed the sub-card on [beaconId], if they have
  /// a help offer there. Idempotent. Returns whether the row exists now.
  Future<bool> dismiss({required String userId, required String beaconId});

  /// The Requests on which [userId] dismissed it, oldest dismissal first.
  Future<List<String>> dismissedBeaconIds({required String userId});
}
