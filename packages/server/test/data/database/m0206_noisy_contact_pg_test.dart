@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';

import '../../support/disposable_pg_target.dart';

/// B2 (m0206): noisy-contact wall — forward-edge contact columns, evidence
/// kinds 6/7, deadline jitter, decay and wall levels in the projection.
/// See `docs/plans/episode-closure-implementation-steps.md` § B2 and
/// `docs/plans/episode-closure-architecture.md` § 6.
const _author = 'Um0206author01';
const _sender = 'Um0206sender01';
const _recipient = 'Um0206recip001';
const _beaconId = 'Bm0206beacon1';

const _kindHelped = 2;
const _kindNoisy = 7;

const _day = Duration(days: 1);

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0206_NOISY_CONTACT_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0206_noisy_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0206_NOISY_CONTACT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0206_noisy',
  );
  final reachable = await canReachPostgresAdmin(migrationTarget);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('migration from 0205', () {
    late DisposablePgWriterSession session;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(
          target: migrationTarget,
          lastInclusiveVersion: '0205',
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });
    }

    test(
      'edges created before the migration get no deadline (no backfill)',
      () async {
        await _seedFixture(session.writer);
        await session.writer.execute('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, created_at)
VALUES ('Fm0206old0001', '$_beaconId', '$_sender', '$_recipient',
        now() - interval '30 days')
''');

        await migrateDbSchema(session.writer);

        final rows = await session.writer.execute('''
SELECT contact_outcome, contact_resolved_at, contact_deadline_at
FROM public.beacon_forward_edge WHERE id = 'Fm0206old0001'
''');
        expect(rows.single[0], isNull);
        expect(rows.single[1], isNull);
        expect(rows.single[2], isNull);
      },
      skip: skipReason,
    );
  });

  group('noisy contact', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late ForwardEdgeRepository forwardEdges;
    late InboxRepository inbox;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        // m0209 ships the noisy wall off; this suite tests the wall itself.
        await session.writer.execute(
          "UPDATE public.trust_config SET value = 'true' "
          "WHERE key = 'noisy_wall_enabled'",
        );
        database = openDisposablePgDatabase(target);
        forwardEdges = ForwardEdgeRepository(database);
        inbox = InboxRepository(database);
      });

      setUp(() async {
        await _seedFixture(session.writer);
      });

      tearDown(() async {
        await _cleanup(session.writer);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: database);
      });
    }

    group('schema and kinds', () {
      test(
        'beacon_forward_edge has the contact columns and the partial index',
        () async {
          final cols = await session.writer.execute('''
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'beacon_forward_edge'
  AND column_name IN
    ('contact_outcome', 'contact_resolved_at', 'contact_deadline_at')
ORDER BY column_name
''');
          expect(
            cols.map((r) => '${r[0]}:${r[1]}').toList(),
            [
              'contact_deadline_at:timestamp with time zone',
              'contact_outcome:smallint',
              'contact_resolved_at:timestamp with time zone',
            ],
          );

          final idx = await session.writer.execute('''
SELECT indexdef FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'beacon_forward_edge'
  AND indexdef ILIKE '%contact_deadline_at%'
''');
          expect(idx, isNotEmpty);
          expect(
            idx.single.single.toString().toLowerCase(),
            contains('contact_resolved_at is null'),
          );
        },
        skip: skipReason,
      );

      test(
        'kinds 6 engaged and 7 noisy are seeded with the wall levels',
        () async {
          final rows = await session.writer.execute('''
SELECT kind, slug, polarity, half_life_s, wall_levels::text
FROM public.trust_kind_config WHERE kind IN (6, 7) ORDER BY kind
''');
          expect(rows, hasLength(2));
          expect(rows[0][1], 'engaged');
          expect(rows[1][1], 'noisy');
          expect(rows[1][2], 1);
          expect(rows[1][3], closeTo(14 * 86400, 1e-6));
          expect(
            jsonDecode(rows[1][4]! as String),
            [
              {'min_n': 3, 'level': 0.1},
              {'min_n': 6, 'level': 0.3},
              {'min_n': 10, 'level': 0.6},
            ],
          );
        },
        skip: skipReason,
      );
    });

    group('deadline', () {
      test(
        'new edge: created_at + 7 d + jitter from md5(edge_id), within ±1 d',
        () async {
          await forwardEdges.create(
            beaconId: _beaconId,
            senderId: _sender,
            recipientId: _recipient,
            note: '',
          );
          final row = (await session.writer.execute('''
SELECT id,
       extract(epoch FROM (contact_deadline_at - created_at))::float8,
       ((('x' || substr(md5(id), 1, 8))::bit(32)::bigint % 172801) - 86400)
         ::float8,
       contact_outcome, contact_resolved_at,
       contact_deadline_at = created_at + interval '7 days'
         + ((('x' || substr(md5(id), 1, 8))::bit(32)::bigint % 172801)
            - 86400) * interval '1 second'
FROM public.beacon_forward_edge WHERE beacon_id = '$_beaconId'
''')).single;
          expect(row[5], isTrue, reason: 'full deadline formula');

          final offsetSeconds = row[1]! as double;
          final jitter = row[2]! as double;
          expect(jitter, inInclusiveRange(-86400, 86400));
          expect(offsetSeconds, closeTo(7 * 86400 + jitter, 1e-3));
          expect(row[3], isNull);
          expect(row[4], isNull);
        },
        skip: skipReason,
      );

      test(
        'edge to the request author has no deadline and no outcome',
        () async {
          await forwardEdges.create(
            beaconId: _beaconId,
            senderId: _sender,
            recipientId: _author,
            note: '',
          );
          final row = (await session.writer.execute('''
SELECT contact_outcome, contact_deadline_at, contact_resolved_at
FROM public.beacon_forward_edge
WHERE beacon_id = '$_beaconId' AND recipient_id = '$_author'
''')).single;
          expect(row[0], isNull);
          expect(row[1], isNull);
          expect(row[2], isNull);
        },
        skip: skipReason,
      );
    });

    test(
      'edge with sender equal to recipient has no deadline and no outcome',
      () async {
        await forwardEdges.create(
          beaconId: _beaconId,
          senderId: _sender,
          recipientId: _sender,
          note: '',
        );
        final row = (await session.writer.execute('''
SELECT contact_outcome, contact_deadline_at, contact_resolved_at
FROM public.beacon_forward_edge
WHERE beacon_id = '$_beaconId' AND sender_id = '$_sender'
  AND recipient_id = '$_sender'
''')).single;
        expect(row[0], isNull);
        expect(row[1], isNull);
        expect(row[2], isNull);
      },
      skip: skipReason,
    );

    group('transition: recipient declines', () {
      test(
        'rejecting in the inbox resolves as declined without evidence',
        () async {
          final edgeId = await _createEdge(forwardEdges, session.writer);
          await inbox.setStatus(
            userId: _recipient,
            beaconId: _beaconId,
            status: 2,
            rejectionMessage: 'no',
          );

          final row = await _edgeContact(session.writer, edgeId);
          expect(row.outcome, 2);
          expect(row.resolvedAt, isNotNull);
          expect(await _contactEvidenceKeys(session.writer), isEmpty);
        },
        skip: skipReason,
      );
    });

    group('fold: decayed n_noisy', () {
      test(
        'three count-1 observations at the same instant give n_noisy 3 '
        'and target -0.1',
        () async {
          final at = await _dbNow(session.writer);
          for (var i = 0; i < 3; i++) {
            await _insertEvidence(
              session.writer,
              kind: _kindNoisy,
              count: 1,
              sourceKey: 'm0206:same:$i',
              occurredAt: at,
            );
            if (i < 2) {
              expect(
                await _projectedTarget(session.writer),
                closeTo(0, 1e-9),
                reason: '${i + 1} observation(s) are below the wall threshold',
              );
            }
          }
          final fold = await _fold(session.writer);
          expect(fold.nNoisy, closeTo(3, 1e-4));
          expect(await _projectedTarget(session.writer), closeTo(-0.1, 1e-9));
        },
        skip: skipReason,
      );

      test(
        'observations aged 0 / 7 / 14 days give n_noisy 2.2071 and no wall',
        () async {
          final now = await _dbNow(session.writer);
          var i = 0;
          for (final age in [0, 7, 14]) {
            await _insertEvidence(
              session.writer,
              kind: _kindNoisy,
              count: 1,
              sourceKey: 'm0206:aged:${i++}',
              occurredAt: now.subtract(_day * age),
            );
          }
          final fold = await _fold(session.writer);
          expect(fold.nNoisy, closeTo(1 + 0.7071 + 0.5, 1e-3));
          expect(fold.trustRecent, lessThan(0.05));
          expect(
            await _projectedTarget(session.writer),
            closeTo(0, 1e-9),
            reason: 'n_noisy 2.2071 < 3: no wall and no trust, so target 0',
          );
        },
        skip: skipReason,
      );

      for (final (n, level) in [
        (2.0, 0.0),
        (3.0, -0.1),
        (5.0, -0.1),
        (6.0, -0.3),
        (9.0, -0.3),
        (10.0, -0.6),
        (25.0, -0.6),
      ]) {
        test(
          'n_noisy $n projects target $level',
          () async {
            await _insertEvidence(
              session.writer,
              kind: _kindNoisy,
              count: n,
              sourceKey: 'm0206:level:$n',
            );
            expect(
              await _projectedTarget(session.writer),
              closeTo(level, 1e-3),
            );
          },
          skip: skipReason,
        );
      }
    });

    group('immunity (T_recent >= 0.05)', () {
      Future<void> threeNoisy() async {
        final at = await _dbNow(session.writer);
        for (var i = 0; i < 3; i++) {
          await _insertEvidence(
            session.writer,
            kind: _kindNoisy,
            count: 1,
            sourceKey: 'm0206:imm:$i',
            occurredAt: at,
          );
        }
      }

      test(
        'a helped row 179 days old keeps the wall off',
        () async {
          await threeNoisy();
          await _insertEvidence(
            session.writer,
            kind: _kindHelped,
            count: 1,
            sourceKey: 'm0206:imm:helped',
            occurredAt: (await _dbNow(session.writer)).subtract(_day * 179),
          );
          final fold = await _fold(session.writer);
          expect(fold.nNoisy, closeTo(3, 1e-3));
          expect(fold.trustRecent, greaterThanOrEqualTo(0.05));
          expect(
            await _projectedTarget(session.writer),
            allOf(closeTo(fold.trustW, 1e-9), closeTo(0.4157, 1e-2)),
            reason: 'immunized: target is the positive helped trust '
                '(0.712 / 1.712), not the -0.1 wall',
          );
        },
        skip: skipReason,
      );

      test(
        'the same row 181 days old no longer immunizes: wall applies',
        () async {
          await threeNoisy();
          await _insertEvidence(
            session.writer,
            kind: _kindHelped,
            count: 1,
            sourceKey: 'm0206:imm:helped',
            occurredAt: (await _dbNow(session.writer)).subtract(_day * 181),
          );
          final fold = await _fold(session.writer);
          expect(fold.trustW, greaterThan(0));
          expect(fold.trustRecent, lessThan(0.05));
          expect(await _projectedTarget(session.writer), closeTo(-0.1, 1e-9));
        },
        skip: skipReason,
      );
    });
  });
}

typedef _FoldRow = ({double trustW, double trustRecent, double nNoisy});

Future<void> _seedFixture(Connection writer) async {
  for (final id in [_author, _sender, _recipient]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_beaconId', '$_author', 'Noisy contact', 'd', 0)
ON CONFLICT DO NOTHING
''');
}

Future<void> _cleanup(Connection writer) async {
  const ids = "'$_author', '$_sender', '$_recipient'";
  await writer.execute(
    'DELETE FROM public.trust_publish_queue '
    'WHERE subject_user_id IN ($ids) OR object_user_id IN ($ids)',
  );
  await writer.execute(
    'DELETE FROM public.trust_evidence '
    'WHERE subject_user_id IN ($ids) OR object_user_id IN ($ids)',
  );
  await writer.execute(
    'DELETE FROM public.user_trust_edge '
    'WHERE subject IN ($ids) OR object IN ($ids)',
  );
  await writer.execute(
    "DELETE FROM public.beacon_forward_edge WHERE beacon_id = '$_beaconId'",
  );
  await writer.execute(
    "DELETE FROM public.inbox_item WHERE beacon_id = '$_beaconId'",
  );
}

Future<String> _createEdge(
  ForwardEdgeRepository repo,
  Connection writer,
) async {
  await repo.create(
    beaconId: _beaconId,
    senderId: _sender,
    recipientId: _recipient,
    note: '',
  );
  final rows = await writer.execute('''
SELECT id FROM public.beacon_forward_edge
WHERE beacon_id = '$_beaconId' AND recipient_id = '$_recipient'
''');
  return rows.single.single! as String;
}

Future<({int? outcome, DateTime? resolvedAt})> _edgeContact(
  Connection writer,
  String edgeId,
) async {
  final row = (await writer.execute(
    Sql.named(
      'SELECT contact_outcome, contact_resolved_at '
      'FROM public.beacon_forward_edge WHERE id = @id',
    ),
    parameters: {'id': edgeId},
  )).single;
  return (outcome: row[0] as int?, resolvedAt: row[1] as DateTime?);
}

Future<List<String>> _contactEvidenceKeys(Connection writer) async {
  final rows = await writer.execute('''
SELECT source_key FROM public.trust_evidence
WHERE source_key LIKE 'contact:%' AND retracted_at IS NULL
ORDER BY source_key
''');
  return rows.map((r) => r.single! as String).toList();
}

Future<void> _insertEvidence(
  Connection writer, {
  required int kind,
  required double count,
  required String sourceKey,
  DateTime? occurredAt,
}) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.trust_evidence (
  id, subject_user_id, object_user_id, kind, count, source_key, occurred_at
) VALUES (
  @id, @subject, @object, @kind, @count, @source_key,
  coalesce(@occurred_at, now())
)
'''),
    parameters: {
      'id': 'T${sourceKey.hashCode.abs().toRadixString(16).padLeft(12, '0')}',
      'subject': _recipient,
      'object': _sender,
      'kind': kind,
      'count': count,
      'source_key': sourceKey,
      'occurred_at': occurredAt,
    },
  );
}

Future<_FoldRow> _fold(Connection writer) async {
  final row = (await writer.execute(
    Sql.named(
      'SELECT trust_w, trust_recent, n_noisy '
      'FROM public.trust_fold_pair(@s, @o)',
    ),
    parameters: {'s': _recipient, 'o': _sender},
  )).single;
  return (
    trustW: row[0]! as double,
    trustRecent: row[1]! as double,
    nNoisy: row[2]! as double,
  );
}

/// Projects recipient → sender and returns `target_w` (0 when the row is
/// absent).
Future<double> _projectedTarget(Connection writer) async {
  await writer.execute(
    Sql.named('SELECT public.trust_project_pair(@s, @o)'),
    parameters: {'s': _recipient, 'o': _sender},
  );
  final rows = await writer.execute(
    Sql.named(
      'SELECT target_w FROM public.user_trust_edge '
      'WHERE subject = @s AND object = @o',
    ),
    parameters: {'s': _recipient, 'o': _sender},
  );
  return rows.isEmpty ? 0 : rows.single.single! as double;
}

Future<DateTime> _dbNow(Connection writer) async =>
    (await writer.execute('SELECT clock_timestamp()')).single.single!
        as DateTime;
