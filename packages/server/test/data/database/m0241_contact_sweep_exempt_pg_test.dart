@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/domain/use_case/contact_resolution_sweep_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// m0241 (budding B5, Arch §2.5, I8): the ignored-contact sweep skips
/// `contact_sweep_exempt` edges (warm bud invites), which still resolve as
/// engaged / declined; `contact_resolve_without_evidence` resolves a contact
/// the way a sender cancel does, with no evidence.
const _author = 'Um0240author01';
const _sender = 'Um0240sender01';
const _recipients = [
  'Um0240recip001',
  'Um0240recip002',
  'Um0240recip003',
  'Um0240recip004',
];
const _beacon = 'Bm0240beacon01';

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0241_SWEEP_EXEMPT_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0241_sweep_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0241_SWEEP_EXEMPT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0241_sweep',
  );
  final pgSkip =
      await pgSkipReason(migrationTarget) ?? await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0240',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('an edge written before the migration can be resolved', () async {
      final writer = session.writer;
      await _seed(writer);
      final edge = await _edge(writer, _recipients[0]);

      await migrateDbSchema(writer);

      expect(await _resolve(writer, edge), isTrue);
      final contact = await _contact(writer, edge);
      expect(contact.resolvedAt, isNotNull);
      expect(contact.outcome, isNull);
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late ForwardEdgeRepository forwardEdges;
    late ContactResolutionSweepCase sweep;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      forwardEdges = ForwardEdgeRepository(database);
      sweep = ContactResolutionSweepCase(
        unitOfWork: MutatingUnitOfWork(database),
        forwardEdgeRepository: forwardEdges,
        trustLedger: TrustLedgerRepository(database),
        env: target.databaseEnv,
        logger: Logger('M0241SweepExemptPgTest'),
      );
    });

    setUp(() async {
      await _seed(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test('an exempt edge past its deadline gets no noisy evidence', () async {
      final edge = await _edge(writer, _recipients[0], exempt: true);
      await _pastDeadline(writer, edge);

      await sweep.run();

      final contact = await _contact(writer, edge);
      expect(contact.outcome, isNull);
      expect(contact.resolvedAt, isNull);
      expect(await _contactEvidence(writer), isEmpty);
    });

    test('an exempt edge still resolves as engaged on a help offer', () async {
      final edge = await _edge(writer, _recipients[0], exempt: true);
      await writer.execute('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, status)
VALUES ('$_beacon', '${_recipients[0]}', 0)
''');

      final contact = await _contact(writer, edge);
      expect(contact.outcome, 1);
      expect(contact.resolvedAt, isNotNull);
      expect(await _contactEvidence(writer), ['contact:$edge:engaged']);
    });

    test('an exempt edge still resolves as declined on an inbox '
        'decline', () async {
      final edge = await _edge(writer, _recipients[0], exempt: true);
      await writer.execute('''
UPDATE public.inbox_item SET status = 2
WHERE beacon_id = '$_beacon' AND user_id = '${_recipients[0]}'
''');

      final contact = await _contact(writer, edge);
      expect(contact.outcome, 2);
      expect(contact.resolvedAt, isNotNull);
      expect(await _contactEvidence(writer), isEmpty);
    });

    test('resolving before the sweep: resolved without evidence, then '
        'skipped by the sweep', () async {
      final edge = await _edge(writer, _recipients[0]);
      await _pastDeadline(writer, edge);

      expect(await _resolve(writer, edge), isTrue);
      final resolved = await _contact(writer, edge);
      expect(resolved.outcome, isNull);
      expect(resolved.resolvedAt, isNotNull);
      expect(await _contactEvidence(writer), isEmpty);

      await sweep.run();

      final after = await _contact(writer, edge);
      expect(after.outcome, isNull);
      expect(after.resolvedAt, resolved.resolvedAt);
      expect(await _contactEvidence(writer), isEmpty);
    });

    test('resolving is a no-op on an already resolved contact', () async {
      final edge = await _edge(writer, _recipients[0]);
      await _pastDeadline(writer, edge);
      await sweep.run();
      expect((await _contact(writer, edge)).outcome, 3);

      expect(await _resolve(writer, edge), isFalse);
      expect((await _contact(writer, edge)).outcome, 3);
      expect(await _contactEvidence(writer), ['contact:$edge:noisy']);
    });

    test('old exempt rows do not starve the sweep of a younger '
        'non-exempt row', () async {
      final exempt = [
        for (final r in _recipients.take(3))
          await _edge(writer, r, exempt: true),
      ];
      for (final (i, edge) in exempt.indexed) {
        await _pastDeadline(writer, edge, hours: 10 + i);
      }
      final ordinary = await _edge(writer, _recipients[3]);
      await _pastDeadline(writer, ordinary);

      final claimed = await forwardEdges.claimIgnoredContacts(limit: 2);

      expect(claimed.map((c) => c.edgeId), [ordinary]);
      for (final edge in exempt) {
        expect((await _contact(writer, edge)).resolvedAt, isNull);
      }
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.trust_evidence,
  public.beacon_help_offer,
  public.inbox_item,
  public.beacon_forward_edge,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _sender, ..._recipients];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('m0241', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_beacon', '$_author', 'Sweep beacon', 'desc', 0)
''');
}

/// An active edge sender → [recipient]; `contact_sweep_exempt` = [exempt].
Future<String> _edge(
  Connection writer,
  String recipient, {
  bool exempt = false,
}) async {
  final rows = await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_forward_edge
  (beacon_id, sender_id, recipient_id, contact_sweep_exempt)
VALUES (@beacon, @sender, @recipient, @exempt)
RETURNING id, contact_deadline_at IS NOT NULL
'''),
    parameters: {
      'beacon': _beacon,
      'sender': _sender,
      'recipient': recipient,
      'exempt': exempt,
    },
  );
  expect(rows.single[1], isTrue, reason: 'the deadline is still set');
  return rows.single[0]! as String;
}

Future<void> _pastDeadline(
  Connection writer,
  String edge, {
  int hours = 1,
}) => writer.execute('''
UPDATE public.beacon_forward_edge
SET contact_deadline_at = now() - interval '$hours hours'
WHERE id = '$edge'
''');

Future<bool> _resolve(Connection writer, String edge) async {
  final rows = await writer.execute(
    Sql.named('SELECT public.contact_resolve_without_evidence(@edge)'),
    parameters: {'edge': edge},
  );
  return rows.single.single! as bool;
}

Future<({int? outcome, DateTime? resolvedAt})> _contact(
  Connection writer,
  String edge,
) async {
  final row = (await writer.execute(
    Sql.named(
      'SELECT contact_outcome, contact_resolved_at '
      'FROM public.beacon_forward_edge WHERE id = @id',
    ),
    parameters: {'id': edge},
  )).single;
  return (outcome: row[0] as int?, resolvedAt: row[1] as DateTime?);
}

Future<List<String>> _contactEvidence(Connection writer) async {
  final rows = await writer.execute(
    'SELECT source_key FROM public.trust_evidence '
    "WHERE source_key LIKE 'contact:%' AND retracted_at IS NULL "
    'ORDER BY source_key',
  );
  return [for (final r in rows) r.single! as String];
}
