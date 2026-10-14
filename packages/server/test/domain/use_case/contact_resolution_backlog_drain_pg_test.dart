@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/domain/use_case/contact_resolution_sweep_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/transaction_statement_recorder.dart';

const _due = 450;
const _beaconId = 'Bdrain0beacon';
const _senderId = 'Udrain0sender';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONTACT_RESOLUTION_DRAIN_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_contact_drain',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('contact resolution backlog draining', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;

    // Production SQL on the real database, with every lane hold recorded.
    late TransactionStatementRecorder recorder;
    late TenturaDb recordedDatabase;

    ContactResolutionSweepCase sweepWith(Env env) => ContactResolutionSweepCase(
      unitOfWork: MutatingUnitOfWork(recordedDatabase),
      forwardEdgeRepository: ForwardEdgeRepository(recordedDatabase),
      trustLedger: TrustLedgerRepository(recordedDatabase),
      env: env,
      logger: Logger('ContactResolutionBacklogDrainPgTest'),
    );

    Future<int> unresolved() async =>
        (await writer.execute(
              'SELECT count(*)::int FROM public.beacon_forward_edge '
              'WHERE contact_resolved_at IS NULL',
            )).single.single!
            as int;

    Future<int> noisyEvidence() async =>
        (await writer.execute(
              'SELECT count(*)::int FROM public.trust_evidence '
              "WHERE source_key LIKE 'contact:%:noisy'",
            )).single.single!
            as int;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        database = openDisposablePgDatabase(target);
      });

      setUp(() {
        recorder = TransactionStatementRecorder.executing(
          PgDatabase.opened(writer, enableMigrations: false),
        );
        recordedDatabase = TenturaDb.forTest(database: recorder);
      });

      setUp(() async {
        await writer.execute('''
TRUNCATE TABLE
  public.trust_evidence,
  public.beacon_forward_edge,
  public.inbox_item,
  public.beacon,
  public."user"
CASCADE
''');
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT 'Udrain0' || lpad(n::text, 5, '0'), 'peer', 'key-' || n
FROM generate_series(0, $_due - 1) n
''');
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_senderId', 'sender', 'key-sender')
''');
        await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_beaconId', '$_senderId', 'Drain beacon', 'desc', 0)
''');
        await writer.execute('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, note
)
SELECT 'Edrain0' || lpad(n::text, 5, '0'), '$_beaconId', '$_senderId',
       'Udrain0' || lpad(n::text, 5, '0'), ''
FROM generate_series(0, $_due - 1) n
''');
        // Edge n is overdue by (due - n) minutes: edge 0 is the oldest.
        await writer.execute('''
UPDATE public.beacon_forward_edge
SET contact_deadline_at =
  now() - interval '10 days' + (substr(id, 8)::int) * interval '1 minute'
WHERE beacon_id = '$_beaconId'
''');
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: database);
      });
    }

    test(
      'one run resolves more than 200 due contacts and records each once',
      () async {
        expect(await unresolved(), _due);

        await sweepWith(
          Env(
            environment: Environment.test,
            printEnv: false,
            contactResolutionBatchSize: 200,
            contactResolutionRunRowBudget: 1000,
            contactResolutionRunTimeBudget: const Duration(minutes: 5),
          ),
        ).run();

        expect(await unresolved(), 0);
        expect(await noisyEvidence(), _due);
        expectBoundedTransactions(recorder, minimumCommittedBatches: 3);
      },
      skip: skipReason,
    );

    test(
      'a run stopped by its row budget resolves exactly the oldest contacts; '
      'bounded further runs finish the rest',
      () async {
        final env = Env(
          environment: Environment.test,
          printEnv: false,
          contactResolutionBatchSize: 40,
          contactResolutionRunRowBudget: 100,
        );

        await sweepWith(env).run();

        expect(await unresolved(), _due - 100);
        expect(await noisyEvidence(), 100);
        expectBoundedTransactions(recorder, minimumCommittedBatches: 3);
        final oldestResolved = await writer.execute('''
SELECT count(*)::int FROM public.beacon_forward_edge
WHERE contact_resolved_at IS NOT NULL AND substr(id, 8)::int < 100
''');
        expect(
          oldestResolved.single.single,
          100,
          reason: 'Chunks must be claimed oldest deadline first',
        );

        // ceil(450 / 100) = 5 runs in total.
        for (var run = 2; run <= 5; run++) {
          await sweepWith(env).run();
        }
        expectBoundedTransactions(recorder);
        expect(await unresolved(), 0);
        expect(await noisyEvidence(), _due);
      },
      skip: skipReason,
    );
  });
}
