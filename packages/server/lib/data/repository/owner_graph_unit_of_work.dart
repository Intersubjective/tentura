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
    Future<T> Function(OwnerGraphScope scope) body,
  ) async {
    final owners = Set<String>.unmodifiable(ownerIds);
    final current = _database.mutatingTransactionIdentity;
    final held = Zone.current[_scopeKey];
    if (current != null &&
        held is _HeldOwnerGraph &&
        held.isActive &&
        identical(held.transaction, current)) {
      if (!held.scope.ownerIds.containsAll(owners)) {
        throw StateError('Nested owner-graph mutation exceeds the held scope');
      }
      // The existing mutating transaction checks the actor and joins directly.
      return _database.withMutatingUser(
        actorUserId,
        () => body(_OwnerGraphScope(owners)),
      );
    }

    final sortedOwners = owners.toList()..sort();
    return withPostgresBoundedRetry(
      () => _database.withMutatingUser(
        actorUserId,
        () => _runWithScope(owners, body),
        acquireLocks: () async {
          for (final owner in sortedOwners) {
            await lockAdvisoryScope(_database, _ownerKey(owner));
          }
        },
      ),
    );
  }

  @override
  Future<T> runRepeatableRead<T>(
    String ownerId,
    String actorUserId,
    Future<T> Function(OwnerGraphScope scope) body,
  ) => _database.withMutatingRepeatableRead(
    actorUserId,
    () => _runWithScope(Set.unmodifiable({ownerId}), body),
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
    final scope = _OwnerGraphScope(owners);
    final held = _HeldOwnerGraph(scope, _database.mutatingTransactionIdentity);
    try {
      return await runZoned(() => body(scope), zoneValues: {_scopeKey: held});
    } finally {
      held.isActive = false;
    }
  }

  static String _ownerKey(String ownerId) => 'owner_graph:$ownerId';
}

final class _OwnerGraphScope implements OwnerGraphScope {
  const _OwnerGraphScope(this.ownerIds);

  @override
  final Set<String> ownerIds;
}

final class _HeldOwnerGraph {
  _HeldOwnerGraph(this.scope, this.transaction);

  final OwnerGraphScope scope;
  final Object? transaction;
  bool isActive = true;
}
