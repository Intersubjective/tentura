import 'dart:math' show max;

import '../exception.dart';
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

  Future<void> saveImportedContactPoints(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
    required ({String normalized, bool keep})? email,
    required String? keptPhone,
  });

  Future<List<String>?> findImportedChunk(
    OwnerGraphScope scope,
    String ownerId,
    String clientOpId,
    int chunkIndex,
  );

  Future<void> recordImportedChunk(
    OwnerGraphScope scope,
    String ownerId,
    String clientOpId,
    int chunkIndex,
    List<String> createdIds,
  );

  /// Returns false when the caller has no matching person.
  Future<bool> update(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
    required String name,
    required String? emoji,
  });

  /// Reads the committed join status for an owned entry without waiting on
  /// the worker's owner scope.
  Future<String?> findJoiningName({
    required String ownerId,
    required String id,
  });

  /// Locks the owned person's invites and returns their name during a queued
  /// join. The locks remain held until the owner-graph transaction ends.
  Future<String?> lockInvitesAndFindJoiningName(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
  });

  /// Ensures a live invite for an owned, active person. Rotation also requires
  /// a live invite to remove. Returns null if the prerequisites are unmet.
  Future<String?> saveInvite(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
    required bool rotate,
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

extension PhantomActivation on PhantomRepositoryPort {
  Future<int> remainingActiveCapacity(
    OwnerGraphScope scope,
    String ownerId,
  ) async => max(0, 200 - await countActive(scope, ownerId));

  Future<void> requireActiveCapacity(
    OwnerGraphScope scope,
    String ownerId,
  ) async {
    if (await remainingActiveCapacity(scope, ownerId) == 0) {
      throw const PhantomCapReachedException();
    }
  }
}
