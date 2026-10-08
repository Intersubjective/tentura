import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/meritrank_status.dart';
import 'package:tentura_server/domain/port/meritrank_status_port.dart';
import 'package:tentura_server/env.dart';

import '../database/tentura_db.dart';

/// Readers seen within this window are expected to hold a walks-cache frame.
const kMeritrankActiveReaderWindow = Duration(hours: 24);

@Injectable(
  as: MeritrankStatusPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class MeritrankStatusRepository implements MeritrankStatusPort {
  const MeritrankStatusRepository(this._env, this._database);

  final Env _env;

  final TenturaDb _database;

  /// The service reports neither its resident frames nor its snapshot bytes
  /// through pgmer2, so the cache size and snapshot budget come from the
  /// mirrored settings and the readers from recent presence; snapshot bytes
  /// stay unknown.
  @override
  Future<MeritrankStatus> status() async {
    final row = await _database
        .customSelect(
          'SELECT count(*)::int AS readers FROM user_presence '
          r'WHERE last_seen_at > now() - make_interval(secs => $1)',
          variables: [
            Variable<double>(
              kMeritrankActiveReaderWindow.inSeconds.toDouble(),
            ),
          ],
        )
        .getSingle();
    return MeritrankStatus(
      walksCacheSize: _env.meritrankWalksCacheSize,
      activeReaders: row.read<int>('readers'),
      snapshotBudgetBytes: _env.meritrankSnapshotsMb * 1024 * 1024,
    );
  }
}
