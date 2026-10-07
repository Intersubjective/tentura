/// Generates identifiers for independently retryable operations.
// ignore: one_member_abstracts -- injectable boundary with a test replacement
abstract interface class OpIdPort {
  String newOpId();
}
