// ignore_for_file: use_raw_strings //

import 'package:injectable/injectable.dart';

import '../database/tentura_db.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class MeritrankRepository {
  const MeritrankRepository(this._database);

  final TenturaDb _database;

  Future<int> init() async {
    final result = await _database
        .customSelect('SELECT meritrank_init()')
        .getSingle();
    print(result.data);
    return result.data.entries.first.value as int;
  }

  Future<void> reset() =>
      _database.customSelect('SELECT mr_reset()').getSingle();

  Future<void> calculate({
    bool isBlocking = true,
    Duration timeout = const Duration(minutes: 10),
  }) => _database
      .customSelect(
        'SELECT mr_recalculate_clustering(\$1, \$2)',
        variables: [
          Variable<bool>(isBlocking),
          Variable<int>(timeout.inMilliseconds),
        ],
      )
      .getSingle();

  Future<void> putEdge({
    required String nodeA,
    required String nodeB,
    double weight = 1.0,
    String context = '',
    int ticker = 0,
  }) => _database
      .customSelect(
        'SELECT mr_put_edge(\$1, \$2, \$3, \$4, \$5)',
        variables: [
          Variable<String>(nodeA),
          Variable<String>(nodeB),
          Variable<double>(weight),
          Variable<String>(context),
          Variable<int>(ticker),
        ],
      )
      .getSingle();

  Future<void> deleteEdge({
    required String nodeA,
    required String nodeB,
    String context = '',
  }) => _database
      .customSelect(
        'SELECT mr_delete_edge(\$1, \$2, \$3)',
        variables: [
          Variable<String>(nodeA),
          Variable<String>(nodeB),
          Variable<String>(context),
        ],
      )
      .getSingle();
}
