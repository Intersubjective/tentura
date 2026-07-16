// The domain owns one transaction operation without importing the database.
// ignore: one_member_abstracts
abstract interface class MutatingUnitOfWorkPort {
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  });
}
