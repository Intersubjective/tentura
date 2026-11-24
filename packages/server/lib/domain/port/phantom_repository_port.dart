import 'owner_graph_transaction_port.dart';

abstract interface class PhantomRepositoryPort {
  Future<int> countActive(OwnerGraphScope scope, String ownerId);

  Future<void> insert(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
    required String name,
    required String? emoji,
  });

  /// Returns false when the caller has no matching person.
  Future<bool> update(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
    required String name,
    required String? emoji,
  });

  Future<bool> delete(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
  });

  /// Records the pair once and returns whether the entry belongs to the owner.
  Future<bool> dismissLinkHint(
    OwnerGraphScope scope, {
    required String ownerId,
    required String phantomId,
    required String userId,
  });
}
