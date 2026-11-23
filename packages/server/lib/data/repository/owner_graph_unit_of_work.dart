import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';

import '../database/postgres_advisory_lock.dart';
import '../database/postgres_serialization_retry.dart';
import '../database/tentura_db.dart';

@Singleton(as: OwnerGraphTransactionPort)
final class OwnerGraphUnitOfWork implements OwnerGraphTransactionPort {
  const OwnerGraphUnitOfWork(this._database);

  static final _scopeKey = Object();
  final TenturaDb _database;

  @override
  Future<T> run<T>(
    Set<String> ownerIds,
    String actorUserId,
    Future<T> Function(OwnerGraphScope scope) body, {
    void Function()? onLockWait,
  }) async {
    final owners = Set<String>.unmodifiable(ownerIds);
    final held = Zone.current[_scopeKey];
    if (held is _HeldOwnerGraph && held.isActiveOn(_database)) {
      if (!held.ownerIds.containsAll(owners)) {
        throw StateError('Nested owner-graph mutation exceeds the held scope');
      }
      // The existing mutating transaction checks the actor and joins directly.
      return _database.withMutatingUser(
        actorUserId,
        () => body(_OwnerGraphScope(owners, held)),
      );
    }

    final sortedOwners = owners.toList()..sort();
    return withPostgresBoundedRetry(
      () => _database.withMutatingUser(
        actorUserId,
        () => _runWithScope(owners, body),
        acquireLocks: () async {
          for (final owner in sortedOwners) {
            await lockAdvisoryScope(
              _database,
              _ownerKey(owner),
              onWait: onLockWait,
            );
          }
        },
      ),
    );
  }

  @override
  Future<T> runRepeatableRead<T>(
    String ownerId,
    String actorUserId,
    Future<T> Function(OwnerGraphScope scope) body, {
    int maxAttempts = 3,
  }) => _database.withMutatingRepeatableRead(
    actorUserId,
    () => _runWithScope(Set.unmodifiable({ownerId}), body),
    maxAttempts: maxAttempts,
    acquireLocks: () => lockAdvisoryScopeForSnapshot(
      _database,
      _ownerKey(ownerId),
    ),
  );

  Future<T> _runWithScope<T>(
    Set<String> owners,
    Future<T> Function(OwnerGraphScope scope) body,
  ) async {
    await _database.customStatement(
      r"SELECT set_config('tentura.owner_scopes', $1, true)",
      [jsonEncode(owners.toList())],
    );
    final held = _HeldOwnerGraph(owners, _database.mutatingTransactionIdentity);
    final scope = _OwnerGraphScope(owners, held);
    try {
      return await runZoned(() => body(scope), zoneValues: {_scopeKey: held});
    } finally {
      held.isActive = false;
    }
  }

  static String _ownerKey(String ownerId) => 'owner_graph:$ownerId';
}

/// Checks that the token covers this owner and belongs to the active
/// transaction on this database handle.
void requireOwnerGraphScope(
  TenturaDb database,
  OwnerGraphScope scope,
  String ownerId,
) {
  if (scope is! _OwnerGraphScope ||
      !scope.ownerIds.contains(ownerId) ||
      !scope._held.isActiveOn(database)) {
    throw StateError('An active owner scope is required for $ownerId');
  }
}

final class _OwnerGraphScope implements OwnerGraphScope {
  const _OwnerGraphScope(this.ownerIds, this._held);

  @override
  final Set<String> ownerIds;
  final _HeldOwnerGraph _held;
}

final class _HeldOwnerGraph {
  _HeldOwnerGraph(this.ownerIds, this.transaction);

  final Set<String> ownerIds;
  final Object? transaction;
  bool isActive = true;

  bool isActiveOn(TenturaDb database) =>
      isActive &&
      transaction != null &&
      identical(transaction, database.mutatingTransactionIdentity);
}
