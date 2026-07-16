import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: AttentionExpiryRepositoryPort)
class AttentionExpiryRepository implements AttentionExpiryRepositoryPort {
  const AttentionExpiryRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<String>> lockExpiredReviewWindowBeaconIds(DateTime now) =>
      _database
          .customSelect(
            r'''
SELECT beacon_id
FROM public.beacon_review_window
WHERE status = 0 AND closes_at < $1
ORDER BY beacon_id
FOR UPDATE
''',
            variables: [Variable<PgDateTime>(PgDateTime(now))],
          )
          .map((row) => row.read<String>('beacon_id'))
          .get();
}
