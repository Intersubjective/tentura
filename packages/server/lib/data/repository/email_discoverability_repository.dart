import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/email_discoverability_port.dart';
import 'package:tentura_server/domain/util/contact_match_key_ring.dart';
import 'package:tentura_server/env.dart';

import '../database/contact_match_storage.dart';
import '../database/tentura_db.dart';

@Injectable(
  as: EmailDiscoverabilityPort,
  env: [Environment.dev, Environment.prod],
)
class EmailDiscoverabilityRepository implements EmailDiscoverabilityPort {
  EmailDiscoverabilityRepository(this._database, Env env)
    : _keys = env.contactMatchKeyRing;

  static const _dailyLimit = 200;

  final TenturaDb _database;
  final ContactMatchKeyRing _keys;

  static String _enabledFor(String accountIdSql) =>
      '''
COALESCE(
  (SELECT enabled FROM public.user_privacy_setting WHERE user_id = $accountIdSql),
  true
)
''';

  @override
  Future<bool> getForAccount(String userId) async {
    final row = await _database
        .customSelect(
          'SELECT ${_enabledFor(r'$1')} AS enabled',
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

  @override
  Future<ContactCheckAnswer?> checkEmail(
    String callerId,
    String normalizedEmail,
  ) => _database.withMutatingUser(callerId, () async {
    final usage = await _database.customWriteReturning(
      r'''
INSERT INTO public.contact_check_usage AS usage (user_id, day, count)
VALUES ($1, (now() AT TIME ZONE 'UTC')::date, 1)
ON CONFLICT (user_id, day) DO UPDATE SET count = usage.count + 1
WHERE usage.count < $2
RETURNING count
''',
      variables: [
        Variable.withString(callerId),
        Variable.withInt(_dailyLimit),
      ],
    );
    if (usage.isEmpty) return null;

    final hashes = _keys
        .candidateHashesForNormalizedEmail(normalizedEmail, _keys.versions)
        .toList();
    final matches = await _database
        .customSelect(
          '''
SELECT EXISTS (
  SELECT 1
  $verifiedEmailMatchRowsSql
  WHERE ${_enabledFor('contact.account_id')}
) AS matched
''',
          variables: [
            for (final parameter in verifiedEmailMatchParameters(hashes))
              Variable(parameter),
          ],
        )
        .getSingle();
    return (
      alreadyOnTentura: matches.read<bool>('matched'),
      reachedDailyLimit: usage.single.read<int>('count') == _dailyLimit,
    );
  });
}
