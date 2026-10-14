import 'dart:io';

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

ContactResolutionSweepCase _sweepOver(
  TransactionStatementRecorder recorder,
  Env env,
) {
  final database = TenturaDb.forTest(database: recorder);
  addTearDown(database.close);
  return ContactResolutionSweepCase(
    unitOfWork: MutatingUnitOfWork(database),
    forwardEdgeRepository: ForwardEdgeRepository(database),
    trustLedger: TrustLedgerRepository(database),
    env: env,
    logger: Logger('ContactResolutionChunkedDrainTest'),
  );
}

/// Serves the claim query like a table holding `due` overdue contacts: each
/// claim returns at most its LIMIT, oldest first, and removes those rows from
/// the backlog. The backlog survives across runs (and across recorders).
class _Backlog {
  _Backlog(this.remaining, {this.claimDelay = Duration.zero});

  int remaining;
  int issued = 0;
  final Duration claimDelay;
  final claimLimits = <int>[];
  final claimSql = <String>[];

  /// Recipients in the order the claim queries handed them out. Ids are not
  /// monotonic in that order, so a sorted write order cannot pass by luck.
  final issuedRecipients = <String>[];

  TransactionStatementRecorder recorder() => TransactionStatementRecorder(
    select: (sql, arguments) {
      if (!sql.contains('UPDATE public.beacon_forward_edge')) return [];
      claimSql.add(sql);
      final limit = arguments.whereType<int>().first;
      claimLimits.add(limit);
      final take = remaining < limit ? remaining : limit;
      remaining -= take;
      return List.generate(take, (_) {
        final n = issued++;
        final recipient = _recipientAt(n);
        issuedRecipients.add(recipient);
        return {
          'id': 'forward-$n',
          'beacon_id': 'beacon-$n',
          'sender_id': 'sender',
          'recipient_id': recipient,
        };
      });
    },
    beforeStatement: (statement) async {
      if (claimDelay > Duration.zero &&
          statement.sql.contains('UPDATE public.beacon_forward_edge')) {
        await Future<void>.delayed(claimDelay);
      }
    },
  );
}

/// Issue position -> recipient id, a fixed permutation of 0..1999.
String _recipientAt(int n) =>
    'recipient-${((n * 7) % 2000).toString().padLeft(4, '0')}';

Set<String> _recipients(int count) => {
  for (var i = 0; i < count; i++) _recipientAt(i),
};

/// Recipients in the order their noisy evidence was written.
List<String> _evidenceOrder(
  TransactionStatementRecorder recorder,
  Set<String> universe,
) => [
  for (final s in recorder.statements.where(
    (s) => mutatesTable(s.sql, 'trust_evidence'),
  ))
    ...referencedMemberIds(s.arguments, universe),
];

int _evidenceRows(
  TransactionStatementRecorder recorder,
  Set<String> universe,
) => _evidenceOrder(recorder, universe).toSet().length;

void main() {
  group('Ignored contact resolution backlog draining', () {
    test('one run resolves a backlog larger than a single chunk in bounded '
        'transactions', () async {
      final backlog = _Backlog(450);
      final recorder = backlog.recorder();
      final sweep = _sweepOver(
        recorder,
        Env(
          environment: Environment.test,
          printEnv: false,
          contactResolutionBatchSize: 50,
        ),
      );

      await sweep.run();

      final recipients = _recipients(450);
      expect(
        _evidenceRows(recorder, recipients),
        450,
        reason: 'Every due contact must get its noisy evidence in one run',
      );
      expect(backlog.remaining, 0);
      expect(backlog.claimLimits.take(9), everyElement(50));
      expectSetBasedWorkload(
        recorder,
        memberIds: recipients,
        isMemberWrite: (sql) => mutatesTable(sql, 'trust_evidence'),
        maximumRowsPerBatch: 50,
        maximumMemberStatements: 16 * 9,
        maximumSingletonTailsPerWrite: 1,
      );
      expectSetBasedWorkload(
        recorder,
        memberIds: recipients,
        isMemberWrite: (sql) => sql.contains('trust_project_pair'),
        maximumRowsPerBatch: 50,
        maximumMemberStatements: 16 * 9,
        maximumSingletonTailsPerWrite: 1,
      );
      expectBoundedTransactions(recorder, minimumCommittedBatches: 9);
      for (final transaction in recorder.transactions) {
        final writesEvidence = transaction.statements.any(
          (s) => mutatesTable(s.sql, 'trust_evidence'),
        );
        if (!writesEvidence) continue;
        expect(
          transaction.statements.any(
            (s) => s.sql.contains('trust_project_pair'),
          ),
          isTrue,
          reason: 'Each chunk projects the evidence it recorded',
        );
      }
    });

    test('every chunk is claimed oldest-deadline first and recorded in the '
        'order it was claimed', () async {
      final backlog = _Backlog(240);
      final recorder = backlog.recorder();
      final sweep = _sweepOver(
        recorder,
        Env(
          environment: Environment.test,
          printEnv: false,
          contactResolutionBatchSize: 60,
        ),
      );

      await sweep.run();

      expect(backlog.claimSql, isNotEmpty);
      for (final sql in backlog.claimSql) {
        expect(
          sql,
          matches(
            RegExp(
              r'ORDER BY\s+\w+\.contact_deadline_at',
              caseSensitive: false,
            ),
          ),
          reason: 'Every chunk claim must keep the deterministic ordering',
        );
      }
      final chunkOf = {
        for (var i = 0; i < backlog.issuedRecipients.length; i++)
          backlog.issuedRecipients[i]: i ~/ 60,
      };
      final written = _evidenceOrder(recorder, _recipients(240));
      expect(written, hasLength(240));
      final chunks = [for (final r in written) chunkOf[r]!];
      expect(
        chunks,
        [...chunks]..sort(),
        reason: 'An earlier-claimed chunk is recorded before a later one',
      );
    });

    test('a run never processes more rows than its row budget; later runs '
        'drain the rest', () async {
      final backlog = _Backlog(1000);
      final env = Env(
        environment: Environment.test,
        printEnv: false,
        contactResolutionBatchSize: 50,
        contactResolutionRunRowBudget: 120,
      );
      final all = _recipients(1000);

      final first = backlog.recorder();
      await _sweepOver(first, env).run();

      expect(
        _evidenceRows(first, all),
        120,
        reason: 'Budget is a cap: 50 + 50 + 20, not three full chunks',
      );
      expect(backlog.remaining, 880);
      expect(backlog.claimLimits, [50, 50, 20]);
      expectBoundedTransactions(first, minimumCommittedBatches: 3);

      var runs = 1;
      while (backlog.remaining > 0 && runs < 9) {
        await _sweepOver(backlog.recorder(), env).run();
        runs++;
      }
      expect(
        backlog.remaining,
        0,
        reason: '1000 contacts at 120 per run need ceil(1000/120) = 9 runs',
      );
      expect(runs, 9);
    });

    test('a time budget spent during a chunk lets that chunk finish, then '
        'ends the run', () async {
      final backlog = _Backlog(
        1000,
        claimDelay: const Duration(milliseconds: 150),
      );
      final recorder = backlog.recorder();
      final sweep = _sweepOver(
        recorder,
        Env(
          environment: Environment.test,
          printEnv: false,
          contactResolutionBatchSize: 50,
          contactResolutionRunTimeBudget: const Duration(milliseconds: 100),
        ),
      );

      await sweep.run();

      expect(backlog.claimLimits, [
        50,
      ], reason: 'The first chunk outlives the budget; no second one starts');
      expect(
        _evidenceRows(recorder, _recipients(1000)),
        50,
        reason: 'The chunk in flight is recorded in full',
      );
      expect(backlog.remaining, 950);
      expectBoundedTransactions(recorder);
    });

    test(
      'a time budget that is not spent does not cut the run short',
      () async {
        final backlog = _Backlog(
          150,
          claimDelay: const Duration(milliseconds: 20),
        );
        final recorder = backlog.recorder();
        final sweep = _sweepOver(
          recorder,
          Env(
            environment: Environment.test,
            printEnv: false,
            contactResolutionBatchSize: 50,
            contactResolutionRunTimeBudget: const Duration(minutes: 5),
          ),
        );

        await sweep.run();

        expect(backlog.remaining, 0);
        expect(_evidenceRows(recorder, _recipients(150)), 150);
      },
    );

    test('a run on an empty backlog claims once and writes nothing', () async {
      final backlog = _Backlog(0);
      final recorder = backlog.recorder();
      final sweep = _sweepOver(
        recorder,
        Env(environment: Environment.test, printEnv: false),
      );

      await sweep.run();

      expect(backlog.claimLimits, hasLength(1));
      expect(
        recorder.statements.any((s) => mutatesTable(s.sql, 'trust_evidence')),
        isFalse,
      );
    });
  });

  group('Contact resolution sweep configuration', () {
    test('defaults: 25-row chunks, sweep cadence shorter than one hour', () {
      final env = Env(environment: Environment.test, printEnv: false);

      expect(env.contactResolutionBatchSize, 25);
      expect(env.contactResolutionRunRowBudget, greaterThan(200));
      expect(env.contactResolutionRunTimeBudget, greaterThan(Duration.zero));
      expect(
        env.contactResolutionSweepInterval,
        lessThan(const Duration(hours: 1)),
      );
      expect(env.contactResolutionSweepInterval, greaterThan(Duration.zero));
    });

    test(
      'chunk size, budgets and cadence are read from process environment',
      () async {
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['run', 'test/support/print_contact_resolution_env.dart'],
          environment: {
            'CONTACT_RESOLUTION_BATCH_SIZE': '37',
            'CONTACT_RESOLUTION_RUN_ROW_BUDGET': '411',
            'CONTACT_RESOLUTION_RUN_TIME_BUDGET_SECONDS': '9',
            'CONTACT_RESOLUTION_SWEEP_INTERVAL_MINUTES': '7',
          },
        );

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          (result.stdout as String).trim().split('\n').last,
          'batch=37 rows=411 timeSeconds=9 intervalMinutes=7',
        );
      },
    );
  });
}
