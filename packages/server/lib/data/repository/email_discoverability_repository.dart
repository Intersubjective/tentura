import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/email_discoverability_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: EmailDiscoverabilityPort,
  env: [Environment.dev, Environment.prod],
)
class EmailDiscoverabilityRepository implements EmailDiscoverabilityPort {
  const EmailDiscoverabilityRepository(this._database);

  final TenturaDb _database;

  @override
  Future<bool> getForAccount(String userId) async {
    final row = await _database
        .customSelect(
          r'''
SELECT COALESCE(
  (SELECT enabled FROM public.user_privacy_setting WHERE user_id = $1),
  true
) AS enabled
''',
          variables: [Variable.withString(userId)],
        )
        .getSingle();
    return row.read<bool>('enabled');
  }

  @override
  Future<bool> setForAccount({
    required String userId,
    required bool enabled,
  }) async {
    final rows = await _database.customWriteReturning(
      r'''
INSERT INTO public.user_privacy_setting (user_id, enabled)
VALUES ($1, $2)
ON CONFLICT (user_id) DO UPDATE SET enabled = EXCLUDED.enabled
RETURNING enabled
''',
      variables: [Variable.withString(userId), Variable.withBool(enabled)],
    );
    return rows.single.read<bool>('enabled');
  }
}
