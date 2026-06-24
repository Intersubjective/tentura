import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: UploadQuotaRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class UploadQuotaRepository implements UploadQuotaRepositoryPort {
  const UploadQuotaRepository(this._database);

  final TenturaDb _database;

  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async {
    if (bytes <= 0) {
      return true;
    }
    // Atomically accumulate today's usage and read back the new total.
    final row = await _database.customSelect(
      '''
INSERT INTO public.upload_daily_usage AS u (user_id, usage_date, bytes)
VALUES (\$1, (now() AT TIME ZONE 'UTC')::date, \$2)
ON CONFLICT (user_id, usage_date)
  DO UPDATE SET bytes = u.bytes + EXCLUDED.bytes
RETURNING bytes AS c
''',
      variables: [
        Variable<String>(userId),
        Variable<int>(bytes),
      ],
    ).getSingle();
    final total = row.read<int>('c');
    if (total > dailyCapBytes) {
      // Over cap: undo the speculative increment so a rejected upload keeps
      // no quota, then signal the caller to reject.
      await _database.customStatement(
        '''
UPDATE public.upload_daily_usage
SET bytes = bytes - \$2
WHERE user_id = \$1 AND usage_date = (now() AT TIME ZONE 'UTC')::date
''',
        [userId, bytes],
      );
      return false;
    }
    return true;
  }

  @override
  Future<int> usedBytesToday(String userId) async {
    final row = await _database.customSelect(
      '''
SELECT COALESCE(bytes, 0)::bigint AS c
FROM public.upload_daily_usage
WHERE user_id = \$1 AND usage_date = (now() AT TIME ZONE 'UTC')::date
''',
      variables: [Variable<String>(userId)],
    ).getSingleOrNull();
    return row?.read<int>('c') ?? 0;
  }
}
