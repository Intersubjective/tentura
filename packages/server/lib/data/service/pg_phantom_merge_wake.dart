import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/port/phantom_merge_wake_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: PhantomMergeWakePort)
final class PgPhantomMergeWake implements PhantomMergeWakePort {
  const PgPhantomMergeWake(this._database, this._logger);

  static const channel = 'phantom_merge_jobs';

  final TenturaDb _database;
  final Logger _logger;

  @override
  Future<void> wake(String invitationId) async {
    try {
      await _database.withConnectionScope(
        () => _database.customStatement(
          r'SELECT pg_notify($1, $2)',
          [channel, invitationId],
        ),
      );
    } on Exception catch (error, stackTrace) {
      // The durable job is already committed and the worker can sweep it.
      _logger.warning(
        'Could not wake the phantom merge worker',
        error,
        stackTrace,
      );
    }
  }
}
