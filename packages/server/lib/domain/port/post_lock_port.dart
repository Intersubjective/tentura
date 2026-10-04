/// Serializes every mutation of a Post behind one lock sequence
/// (plan §4.10): global hierarchy lock → per-request advisory lock → beacon
/// row lock. Callers re-check everything mutable after acquiring it.
abstract interface class PostLockPort {
  Future<void> lockForPostMutation(String beaconId);
}
