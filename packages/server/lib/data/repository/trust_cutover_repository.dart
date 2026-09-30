import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_cutover_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: TrustCutoverPort,
  env: [Environment.dev, Environment.prod, Environment.test],
  order: 1,
)
class TrustCutoverRepository implements TrustCutoverPort {
  const TrustCutoverRepository(this._database);

  final TenturaDb _database;

  @override
  Future<bool> isDone() async {
    final rows = await _database
        .customSelect(
          "SELECT 1 FROM public.trust_cutover_state WHERE id = 1 AND status = 'done'",
        )
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<int?> acquire(String owner) async {
    final rows = await _database
        .customSelect(
          r'''
UPDATE public.trust_cutover_state
SET owner = $1, token = token + 1, lease_until = now() + interval '10 minutes',
    updated_at = now()
WHERE id = 1 AND status = 'pending' AND (lease_until < now() OR owner = $1)
RETURNING token
''',
          variables: [Variable<String>(owner)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<BigInt>('token').toInt();
  }

  @override
  Future<bool> renew(int token) async {
    final rows = await _database
        .customSelect(
          r'''
UPDATE public.trust_cutover_state
SET lease_until = now() + interval '10 minutes', updated_at = now()
WHERE id = 1 AND status = 'pending' AND token = $1 AND lease_until > now()
RETURNING token
''',
          variables: [Variable<int>(token)],
        )
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<List<(String, String)>> votePairs() async {
    final rows = await _database
        .customSelect(
          'SELECT subject, object FROM public.vote_user WHERE amount > 0 '
          'ORDER BY subject, object',
        )
        .get();
    return [
      for (final r in rows) (r.read<String>('subject'), r.read<String>('object')),
    ];
  }

  @override
  Future<void> projectPairs(int token, List<(String, String)> pairs) async {
    await _requireLease(token);
    for (final (subject, object) in pairs) {
      await _database
          .customSelect(
            r'SELECT public.trust_project_pair($1, $2)',
            variables: [Variable<String>(subject), Variable<String>(object)],
          )
          .get();
    }
  }

  @override
  Future<void> reset(int token) async {
    await _requireLease(token);
    await _database.customStatement('SELECT public.mr_reset()');
  }

  @override
  Future<void> init(int token) async {
    await _requireLease(token);
    await _database.customStatement('SELECT public.meritrank_init()');
  }

  @override
  Future<void> sync(int token) async {
    await _requireLease(token);
    await _database.customStatement('SELECT public.mr_sync()');
  }

  @override
  Future<void> finish(int token) => _database.transaction(() async {
    final lease = await _database
        .customSelect(
          r'''
SELECT 1 FROM public.trust_cutover_state
WHERE id = 1 AND status = 'pending' AND token = $1
FOR UPDATE
''',
          variables: [Variable<int>(token)],
        )
        .get();
    if (lease.isEmpty) return;
    await _database.customUpdate(
      'UPDATE public.user_trust_edge SET prev_sent_weight = target_w',
    );
    await _database.customUpdate('DELETE FROM public.trust_publish_queue');
    await _database.customUpdate(
      '''
UPDATE public.trust_cutover_state
SET status = 'done', owner = NULL, updated_at = now() WHERE id = 1
''',
    );
  });

  Future<void> _requireLease(int token) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT 1 FROM public.trust_cutover_state
WHERE id = 1 AND status = 'pending' AND token = $1 AND lease_until > now()
''',
          variables: [Variable<int>(token)],
        )
        .get();
    if (rows.isEmpty) throw StateError('Trust cutover lease lost');
  }
}
