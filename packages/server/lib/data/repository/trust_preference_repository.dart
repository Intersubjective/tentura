import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_preference_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: TrustPreferencePort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class TrustPreferenceRepository implements TrustPreferencePort {
  const TrustPreferenceRepository(this._database);

  final TenturaDb _database;

  @override
  Future<bool> noisyWallEnabled(String userId) async {
    final row = await _database
        .customSelect(
          r'''
SELECT coalesce(p.noisy_wall_enabled, (c.value)::text::boolean, false)
         AS enabled
FROM (SELECT 1) one
LEFT JOIN public.trust_config c ON c.key = 'noisy_wall_enabled'
LEFT JOIN public.user_trust_preference p ON p.user_id = $1
''',
          variables: [Variable<String>(userId)],
        )
        .getSingle();
    return row.read<bool>('enabled');
  }

  @override
  Future<bool> setNoisyWallEnabled({
    required String userId,
    required bool enabled,
  }) async {
    // The row trigger re-projects the user's pairs in this statement.
    await _database.customStatement(
      r'''
INSERT INTO public.user_trust_preference (user_id, noisy_wall_enabled)
VALUES ($1, $2)
ON CONFLICT (user_id) DO UPDATE
  SET noisy_wall_enabled = EXCLUDED.noisy_wall_enabled, updated_at = now()
''',
      [userId, enabled],
    );
    return enabled;
  }
}
