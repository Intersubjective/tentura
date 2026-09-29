@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// A1 (m0202): trust ledger tables, wipe, `trust_fold_pair`, `trust_project_pair`,
/// and deletion enqueue — see `docs/plans/episode-closure-implementation-steps.md`.
const _alice = 'Um0202pgalice01';
const _bob = 'Um0202pgbob0001';
const _carol = 'Um0202pgcarol01';
const _allIds = [_alice, _bob, _carol];

const _kindHelped = 2;
const _kindMarked = 3;
const _kindWorkedWithAuthor = 8;

final _close1333 = closeTo(0.13333333333333333, 1e-9);
final _close3333 = closeTo(0.33333333333333333, 1e-9);
final _close02667 = closeTo(0.026666666666666668, 1e-9);

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0202_TRUST_LEDGER_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0202_trust_ledger_mig',
  );
  final ledgerTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0202_TRUST_LEDGER_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0202_trust_ledger',
  );
  final reachable = await canReachPostgresAdmin(migrationTarget);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('migration from 0201', () {
    late DisposablePgWriterSession session;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(
          target: migrationTarget,
          lastInclusiveVersion: '0201',
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });
    }

    test(
      'wipes seeded legacy trust rows and leaves cutover pending',
      () async {
        await _insertUsers(session.writer, _allIds);
        await _seedLegacyTrustEdgesAt0201(session.writer, _alice, _bob);

        final edgesBefore = await session.writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.user_trust_edge '
            'WHERE subject = @s AND object = @o',
          ),
          parameters: {'s': _alice, 'o': _bob},
        );
        expect(edgesBefore.single.single, greaterThan(0));

        await migrateDbSchema(session.writer);

        final cutover = await session.writer.execute(
          'SELECT status FROM public.trust_cutover_state WHERE id = 1',
        );
        expect(cutover.single.single, 'pending');

        final edgesAfter = await session.writer.execute(
          'SELECT count(*)::int FROM public.user_trust_edge',
        );
        expect(edgesAfter.single.single, 0);
      },
      skip: skipReason,
    );
  });

  group('trust_fold_pair', () {
    late DisposablePgWriterSession session;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: ledgerTarget);
      });

      setUp(() async {
        await _insertUsers(session.writer, _allIds);
      });

      tearDown(() async {
        await _cleanupLedgerFixture(session.writer, _allIds);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });
    }

    test(
      'helped count 1 now yields trust_w 0.5',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _alice,
          object: _bob,
          kind: _kindHelped,
          count: 1,
          sourceKey: 'm0202:helped:now',
        );
        final fold = await _foldPair(session.writer, _alice, _bob);
        expect(fold.trustW, closeTo(0.5, 1e-9));
      },
      skip: skipReason,
    );

    test(
      'helped plus vouch yields trust_w 1.0',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _alice,
          object: _bob,
          kind: _kindHelped,
          count: 1,
          sourceKey: 'm0202:helped:vouch',
        );
        await _insertVote(session.writer, _alice, _bob, amount: 1);
        final fold = await _foldPair(session.writer, _alice, _bob);
        expect(fold.trustW, closeTo(1.0, 1e-9));
      },
      skip: skipReason,
    );

    test(
      'marked count 1 yields trust_w 0.1333…',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _alice,
          object: _bob,
          kind: _kindMarked,
          count: 1,
          sourceKey: 'm0202:marked:1',
        );
        final fold = await _foldPair(session.writer, _alice, _bob);
        expect(fold.trustW, _close1333);
      },
      skip: skipReason,
    );

    test(
      'helped one year old yields trust_w 0.3333…',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _alice,
          object: _bob,
          kind: _kindHelped,
          count: 1,
          sourceKey: 'm0202:helped:old',
          occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 365)),
        );
        final fold = await _foldPair(session.writer, _alice, _bob);
        expect(fold.trustW, _close3333);
      },
      skip: skipReason,
    );

    test(
      'worked_with_author now yields trust_w 0.04 and trust_recent 0',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _bob,
          object: _alice,
          kind: _kindWorkedWithAuthor,
          count: 1,
          sourceKey: 'm0202:wwa:now',
        );
        final fold = await _foldPair(session.writer, _bob, _alice);
        expect(fold.trustW, closeTo(0.04, 1e-9));
        expect(fold.trustRecent, closeTo(0, 1e-9));
      },
      skip: skipReason,
    );

    test(
      'worked_with_author 90 days old yields trust_w 0.02667',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _bob,
          object: _alice,
          kind: _kindWorkedWithAuthor,
          count: 1,
          sourceKey: 'm0202:wwa:90d',
          occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 90)),
        );
        final fold = await _foldPair(session.writer, _bob, _alice);
        expect(fold.trustW, _close02667);
      },
      skip: skipReason,
    );

    test(
      'worked_with_author 181 days old yields trust_w 0',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _bob,
          object: _alice,
          kind: _kindWorkedWithAuthor,
          count: 1,
          sourceKey: 'm0202:wwa:181d',
          occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 181)),
        );
        final fold = await _foldPair(session.writer, _bob, _alice);
        expect(fold.trustW, closeTo(0, 1e-9));
      },
      skip: skipReason,
    );

    test(
      'worked_with_author count 0.5 now yields trust_w 0.02667',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _bob,
          object: _alice,
          kind: _kindWorkedWithAuthor,
          count: 0.5,
          sourceKey: 'm0202:wwa:half',
        );
        final fold = await _foldPair(session.writer, _bob, _alice);
        expect(fold.trustW, _close02667);
      },
      skip: skipReason,
    );

    test(
      'retracted evidence is ignored',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _alice,
          object: _bob,
          kind: _kindHelped,
          count: 1,
          sourceKey: 'm0202:helped:live',
        );
        await _insertEvidence(
          session.writer,
          subject: _alice,
          object: _bob,
          kind: _kindHelped,
          count: 1,
          sourceKey: 'm0202:helped:retracted',
          retractedAt: DateTime.now().toUtc(),
        );
        final fold = await _foldPair(session.writer, _alice, _bob);
        expect(fold.trustW, closeTo(0.5, 1e-9));
      },
      skip: skipReason,
    );
  });

  group('trust_project_pair and delete enqueue', () {
    late DisposablePgWriterSession session;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: ledgerTarget);
      });

      setUp(() async {
        await _insertUsers(session.writer, _allIds);
      });

      tearDown(() async {
        await _cleanupLedgerFixture(session.writer, _allIds);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });
    }

    test(
      'target 0 to 0.5 enqueues publication',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _alice,
          object: _bob,
          kind: _kindHelped,
          count: 1,
          sourceKey: 'm0202:proj:0-05',
        );
        await _projectPair(session.writer, _alice, _bob);
        expect(
          await _queueDepth(session.writer, _alice, _bob),
          1,
        );
      },
      skip: skipReason,
    );

    test(
      'target 0.5 to 0.55 within epsilon does not enqueue',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _alice,
          object: _bob,
          kind: _kindHelped,
          count: 1,
          sourceKey: 'm0202:proj:eps',
        );
        await _projectPair(session.writer, _alice, _bob);
        await session.writer.execute(
          Sql.named(
            'UPDATE public.user_trust_edge '
            'SET prev_sent_weight = 0.5, target_w = 0.5 '
            'WHERE subject = @s AND object = @o',
          ),
          parameters: {'s': _alice, 'o': _bob},
        );
        await session.writer.execute(
          'DELETE FROM public.trust_publish_queue',
        );
        await session.writer.execute(
          Sql.named(
            'UPDATE public.trust_evidence SET count = 1.222222222222222 '
            'WHERE source_key = @key',
          ),
          parameters: {'key': 'm0202:proj:eps'},
        );
        await _projectPair(session.writer, _alice, _bob);
        expect(
          await _queueDepth(session.writer, _alice, _bob),
          0,
        );
      },
      skip: skipReason,
    );

    test(
      'target 0 to 0.05 enqueues on sign change',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _alice,
          object: _bob,
          kind: _kindMarked,
          count: 0.16666666666666666,
          sourceKey: 'm0202:proj:sign',
        );
        await _projectPair(session.writer, _alice, _bob);
        expect(
          await _queueDepth(session.writer, _alice, _bob),
          1,
        );
      },
      skip: skipReason,
    );

    test(
      'target 0.5 to 0 keeps row and enqueues',
      () async {
        await _insertEvidence(
          session.writer,
          subject: _alice,
          object: _bob,
          kind: _kindHelped,
          count: 1,
          sourceKey: 'm0202:proj:to-zero',
        );
        await _projectPair(session.writer, _alice, _bob);
        await session.writer.execute(
          Sql.named(
            'UPDATE public.user_trust_edge '
            'SET prev_sent_weight = 0.5, target_w = 0.5 '
            'WHERE subject = @s AND object = @o',
          ),
          parameters: {'s': _alice, 'o': _bob},
        );
        await session.writer.execute(
          'DELETE FROM public.trust_publish_queue',
        );
        await session.writer.execute(
          Sql.named(
            'UPDATE public.trust_evidence SET retracted_at = now() '
            'WHERE source_key = @key',
          ),
          parameters: {'key': 'm0202:proj:to-zero'},
        );
        await _projectPair(session.writer, _alice, _bob);
        final row = await session.writer.execute(
          Sql.named(
            'SELECT target_w::float8 FROM public.user_trust_edge '
            'WHERE subject = @s AND object = @o',
          ),
          parameters: {'s': _alice, 'o': _bob},
        );
        expect((row.single.single as num).toDouble(), closeTo(0, 1e-9));
        expect(
          await _queueDepth(session.writer, _alice, _bob),
          1,
        );
      },
      skip: skipReason,
    );

    test(
      'deleting edge with prev_sent_weight 0.5 enqueues',
      () async {
        await session.writer.execute(
          Sql.named(
            '''
INSERT INTO public.user_trust_edge (
  subject, object, prev_sent_weight, trust_w, wall_d, target_w
) VALUES (@s, @o, 0.5, 0.5, 0, 0.5)
''',
          ),
          parameters: {'s': _alice, 'o': _bob},
        );
        await session.writer.execute(
          Sql.named(
            'DELETE FROM public.user_trust_edge '
            'WHERE subject = @s AND object = @o',
          ),
          parameters: {'s': _alice, 'o': _bob},
        );
        expect(
          await _queueDepth(session.writer, _alice, _bob),
          1,
        );
      },
      skip: skipReason,
    );

    test(
      'deleting edge with prev_sent_weight 0 does not enqueue',
      () async {
        await session.writer.execute(
          Sql.named(
            '''
INSERT INTO public.user_trust_edge (
  subject, object, prev_sent_weight, trust_w, wall_d, target_w
) VALUES (@s, @o, 0, 0, 0, 0)
''',
          ),
          parameters: {'s': _alice, 'o': _bob},
        );
        await session.writer.execute(
          Sql.named(
            'DELETE FROM public.user_trust_edge '
            'WHERE subject = @s AND object = @o',
          ),
          parameters: {'s': _alice, 'o': _bob},
        );
        expect(
          await _queueDepth(session.writer, _alice, _bob),
          0,
        );
      },
      skip: skipReason,
    );

    test(
      'deleting user cascades edge delete and enqueues',
      () async {
        await session.writer.execute(
          Sql.named(
            '''
INSERT INTO public.user_trust_edge (
  subject, object, prev_sent_weight, trust_w, wall_d, target_w
) VALUES (@s, @o, 0.5, 0.5, 0, 0.5)
''',
          ),
          parameters: {'s': _alice, 'o': _bob},
        );
        await session.writer.execute(
          Sql.named('DELETE FROM public."user" WHERE id = @id'),
          parameters: {'id': _alice},
        );
        expect(
          await _queueDepth(session.writer, _alice, _bob),
          1,
        );
      },
      skip: skipReason,
    );
  });
}

typedef _FoldRow = ({double trustW, double trustRecent, double nNoisy});

Future<void> _insertUsers(Connection writer, List<String> ids) async {
  for (final id in ids) {
    await writer.execute(
      Sql.named(
        '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @pk, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      ),
      parameters: {'id': id, 'pk': 'pk-$id'},
    );
  }
}

Future<void> _seedLegacyTrustEdgesAt0201(
  Connection writer,
  String subject,
  String object,
) async {
  await writer.execute(
    Sql.named(
      r"SELECT trust_apply_source_evidence('personal', @s, @o, 'very_good', 2)",
    ),
    parameters: {'s': subject, 'o': object},
  );
  await writer.execute(
    Sql.named(
      'SELECT trust_rebuild_effective_edge(@s, @o, -1)',
    ),
    parameters: {'s': subject, 'o': object},
  );
}

Future<_FoldRow> _foldPair(Connection writer, String subject, String object) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT trust_w, trust_recent, n_noisy '
      'FROM trust_fold_pair(@s, @o)',
    ),
    parameters: {'s': subject, 'o': object},
  );
  final row = rows.single;
  return (
    trustW: (row[0]! as num).toDouble(),
    trustRecent: (row[1]! as num).toDouble(),
    nNoisy: (row[2]! as num).toDouble(),
  );
}

Future<void> _projectPair(
  Connection writer,
  String subject,
  String object,
) async {
  await writer.execute(
    Sql.named('SELECT trust_project_pair(@s, @o)'),
    parameters: {'s': subject, 'o': object},
  );
}

Future<int> _queueDepth(
  Connection writer,
  String subject,
  String object,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT count(*)::int FROM public.trust_publish_queue '
      'WHERE subject_user_id = @s AND object_user_id = @o',
    ),
    parameters: {'s': subject, 'o': object},
  );
  return rows.single.single! as int;
}

Future<void> _insertEvidence(
  Connection writer, {
  required String subject,
  required String object,
  required int kind,
  required double count,
  required String sourceKey,
  DateTime? occurredAt,
  DateTime? retractedAt,
}) async {
  await writer.execute(
    Sql.named(
      '''
INSERT INTO public.trust_evidence (
  id, subject_user_id, object_user_id, kind, count, source_key,
  occurred_at, retracted_at
) VALUES (
  @id, @subject, @object, @kind, @count, @source_key,
  coalesce(@occurred_at, now()), @retracted_at
)
''',
    ),
    parameters: {
      'id': 'T${sourceKey.hashCode.abs().toRadixString(16).padLeft(12, '0')}',
      'subject': subject,
      'object': object,
      'kind': kind,
      'count': count,
      'source_key': sourceKey,
      'occurred_at': occurredAt,
      'retracted_at': retractedAt,
    },
  );
}

Future<void> _insertVote(
  Connection writer,
  String subject,
  String object, {
  required int amount,
}) async {
  await writer.execute(
    Sql.named(
      '''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@s, @o, @amount)
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''',
    ),
    parameters: {'s': subject, 'o': object, 'amount': amount},
  );
}

Future<void> _cleanupLedgerFixture(Connection writer, List<String> ids) async {
  final idList = ids.map((id) => "'$id'").join(', ');
  await _deleteIfRelationExists(
    writer,
    'DELETE FROM public.trust_publish_queue '
    'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
  );
  await _deleteIfRelationExists(
    writer,
    'DELETE FROM public.trust_evidence '
    'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
  );
  await writer.execute(
    'DELETE FROM public.vote_user '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await writer.execute(
    'DELETE FROM public.user_trust_edge '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await writer.execute(
    'DELETE FROM public."user" WHERE id IN ($idList)',
  );
}

Future<void> _deleteIfRelationExists(Connection writer, String sql) async {
  try {
    await writer.execute(sql);
  } on ServerException catch (error) {
    if (error.code != '42P01') {
      rethrow;
    }
  }
}
