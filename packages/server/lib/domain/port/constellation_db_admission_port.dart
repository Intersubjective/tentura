/// Kind of constellation DB transaction asking for admission.
enum ConstellationDbWorkKind {
  /// Interactive write (apply batch).
  apply,

  /// Refresh of anchors only.
  anchors,

  /// Full constellation refresh.
  full,
}

/// Worker-wide admission for constellation DB transactions.
// ignore: one_member_abstracts -- injectable port with a single admission call
abstract interface class ConstellationDbAdmissionPort {
  /// Runs [body] once admitted; throws a typed RETRY_LATER
  /// `ConstellationException` when over the limit or past the queue deadline.
  Future<T> run<T>(ConstellationDbWorkKind kind, Future<T> Function() body);
}
