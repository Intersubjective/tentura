import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/domain/use_case/contact_resolution_sweep_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/transaction_statement_recorder.dart';

void main() {
  group('Ignored contact resolution transaction budgets', () {
    test('a full contact sweep records and projects evidence with constant SQL',
        () async {
      final recorder = TransactionStatementRecorder(
        select: (sql, arguments) {
          if (!sql.contains('UPDATE public.beacon_forward_edge')) return [];
          return List.generate(200, (index) => {
            'id': 'forward-$index',
            'beacon_id': 'beacon-$index',
            'sender_id': 'sender',
            'recipient_id': 'recipient-$index',
          });
        },
      );
      final database = TenturaDb.forTest(database: recorder);
      addTearDown(database.close);
      final sweep = ContactResolutionSweepCase(
        unitOfWork: MutatingUnitOfWork(database),
        forwardEdgeRepository: ForwardEdgeRepository(database),
        trustLedger: TrustLedgerRepository(database),
        env: Env(environment: Environment.test, printEnv: false),
        logger: Logger('ContactResolutionTransactionBudgetTest'),
      );

      await sweep.run();

      expect(
        recorder.statements.any(
          (statement) => statement.sql.contains('INSERT INTO public.trust_evidence'),
        ),
        isTrue,
        reason: 'The measured sweep must persist noisy-contact evidence',
      );
      expect(
        recorder.statements.any(
          (statement) => statement.sql.contains('trust_project_pair'),
        ),
        isTrue,
        reason: 'Projection round trips belong to the same lane-hold budget',
      );
      final recipients = {for (var index = 0; index < 200; index++)
        'recipient-$index'};
      expectSetBasedWorkload(
        recorder,
        memberIds: recipients,
        isMemberWrite: (sql) => mutatesTable(sql, 'trust_evidence'),
        maximumRowsPerBatch: 200,
        maximumMemberStatements: 16,
        maximumSingletonTailsPerWrite: 1,
      );
      expectSetBasedWorkload(
        recorder,
        memberIds: recipients,
        isMemberWrite: (sql) => sql.contains('trust_project_pair'),
        maximumRowsPerBatch: 200,
        maximumMemberStatements: 16,
        maximumSingletonTailsPerWrite: 1,
      );
      expectBoundedTransactions(recorder);
    });
  });
}
