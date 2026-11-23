import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';

import '../database/postgres_serialization_retry.dart';
import '../database/tentura_db.dart';

@Singleton(as: MutatingUnitOfWorkPort)
class MutatingUnitOfWork
    implements MutatingUnitOfWorkPort, RetryingMutatingUnitOfWorkPort {
  const MutatingUnitOfWork(this._database);

  final TenturaDb _database;

  @override
  Future<T> retryOnConflict<T>(Future<T> Function() runTransaction) {
    // When joining an open unit of work, only its owner can retry it.
    if (_database.isInAmbientMutatingTransaction) return runTransaction();
    return withPostgresDeadlockOrSerializationRetry(runTransaction);
  }

  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) {
    final actor = actorUserId?.trim();
    if (actor == null || actor.isEmpty) {
      return _database.withMutatingSystem(action);
    }
    return _database.withMutatingUser(actor, action);
  }
}
