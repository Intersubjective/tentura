import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_publish_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: TrustPublishPort,
  env: [Environment.dev, Environment.prod, Environment.test],
  order: 1,
)
class TrustPublishRepository implements TrustPublishPort {
  const TrustPublishRepository(this._database);

  final TenturaDb _database;

  @override
  Future<int?> acquireLease(String owner) async {
    final rows = await _database
        .customSelect(
          r'''
UPDATE public.trust_publisher_lease
SET owner = $1, token = token + 1, lease_until = now() + interval '2 minutes'
WHERE id = 1 AND (lease_until < now() OR owner = $1)
RETURNING token
''',
          variables: [Variable<String>(owner)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<BigInt>('token').toInt();
  }

  @override
  Future<bool> leaseValid(int token) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT 1 FROM public.trust_publisher_lease
WHERE id = 1 AND token = $1 AND lease_until > now()
''',
          variables: [Variable<int>(token)],
        )
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<List<PublishRow>> readBatch(int limit) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT q.subject_user_id, q.object_user_id, coalesce(e.target_w, 0) AS target_w
FROM public.trust_publish_queue q
LEFT JOIN public.user_trust_edge e
  ON e.subject = q.subject_user_id AND e.object = q.object_user_id
WHERE q.next_attempt_at <= now()
ORDER BY q.enqueued_at
LIMIT $1
''',
          variables: [Variable<int>(limit)],
        )
        .get();
    return [
      for (final r in rows)
        PublishRow(
          r.read<String>('subject_user_id'),
          r.read<String>('object_user_id'),
          r.read<double>('target_w'),
        ),
    ];
  }

  @override
  Future<void> publish(PublishRow row) => row.target == 0
      ? _database
            .customSelect(
              r'SELECT public.mr_delete_edge($1, $2)',
              variables: [
                Variable<String>(row.subject),
                Variable<String>(row.object),
              ],
            )
            .get()
      : _database
            .customSelect(
              r"SELECT public.mr_put_edge($1, $2, $3, '', 0)",
              variables: [
                Variable<String>(row.subject),
                Variable<String>(row.object),
                Variable<double>(row.target),
              ],
            )
            .get();

  @override
  Future<void> sync() => _database.customStatement('SELECT public.mr_sync()');

  @override
  Future<void> ack(int token, List<PublishRow> rows) =>
      _database.transaction(() async {
        final lease = await _database
            .customSelect(
              r'''
SELECT 1 FROM public.trust_publisher_lease
WHERE id = 1 AND token = $1 AND lease_until > now()
FOR UPDATE
''',
              variables: [Variable<int>(token)],
            )
            .get();
        if (lease.isEmpty) return;
        for (final row in rows) {
          final current = await _database
              .customSelect(
                r'''
SELECT target_w FROM public.user_trust_edge
WHERE subject = $1 AND object = $2
''',
                variables: [
                  Variable<String>(row.subject),
                  Variable<String>(row.object),
                ],
              )
              .get();
          final target = current.isEmpty
              ? 0.0
              : current.single.read<double>('target_w');
          if (target != row.target) continue;
          final args = [
            Variable<String>(row.subject),
            Variable<String>(row.object),
          ];
          await _database.customUpdate(
            r'''
UPDATE public.user_trust_edge SET prev_sent_weight = target_w
WHERE subject = $1 AND object = $2
''',
            variables: args,
          );
          await _database.customUpdate(
            r'''
DELETE FROM public.user_trust_edge
WHERE subject = $1 AND object = $2 AND target_w = 0 AND prev_sent_weight = 0
''',
            variables: args,
          );
          await _database.customUpdate(
            r'''
DELETE FROM public.trust_publish_queue
WHERE subject_user_id = $1 AND object_user_id = $2
''',
            variables: args,
          );
        }
        // Same as WitnessWindowPort.bumpMrEpoch.
        await _database.customStatement('SELECT public.mr_sync()');
        await _database.customStatement(
          r'''
UPDATE public.mr_publish_epoch SET epoch = epoch + 1 WHERE id = true
''',
        );
      });

  @override
  Future<void> fail(List<PublishRow> rows, String error) async {
    for (final row in rows) {
      await _database.customUpdate(
        r'''
UPDATE public.trust_publish_queue
SET attempts = attempts + 1,
    next_attempt_at = now() + least(3600, 10 * power(2, attempts + 1)) * interval '1 second',
    last_error = $3
WHERE subject_user_id = $1 AND object_user_id = $2
''',
        variables: [
          Variable<String>(row.subject),
          Variable<String>(row.object),
          Variable<String>(error),
        ],
      );
    }
  }

  @override
  Future<bool> cutoverPending() async {
    final rows = await _database
        .customSelect(
          r"SELECT 1 FROM public.trust_cutover_state WHERE id = 1 AND status = 'pending'",
        )
        .get();
    return rows.isNotEmpty;
  }
}
