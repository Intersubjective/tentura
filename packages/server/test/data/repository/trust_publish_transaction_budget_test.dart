import 'dart:async';

import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/domain/port/trust_publish_port.dart';

import '../../support/transaction_statement_recorder.dart';

List<Map<String, Object?>> _select(String sql, List<Object?> arguments) {
  if (sql.contains('trust_publisher_lease')) {
    return [
      {'valid': 1},
    ];
  }
  if (sql.contains('user_trust_edge')) {
    return [
      {'target_w': 0.5},
    ];
  }
  if (sql.contains('lane_probe')) {
    return [
      {'lane_probe': 42},
    ];
  }
  return [];
}

void main() {
  group('Trust publication acknowledgement transaction boundaries', () {
    test(
      'a full publication batch uses constant statements per commit',
      () async {
        final recorder = TransactionStatementRecorder(select: _select);
        final database = TenturaDb.forTest(database: recorder);
        addTearDown(database.close);
        final repository = TrustPublishRepository(database);
        final rows = List.generate(
          200,
          (index) => PublishRow('publisher', 'peer-$index', 0.5),
        );

        await repository.ack(1, rows);

        expect(
          recorder.statements.any(
            (statement) => statement.sql.contains('trust_publish_queue'),
          ),
          isTrue,
          reason: 'The measurement must execute acknowledgement writes',
        );
        expectSetBasedWorkload(
          recorder,
          memberIds: {for (var index = 0; index < 200; index++) 'peer-$index'},
          isMemberWrite: (sql) => mutatesTable(sql, 'user_trust_edge') ||
              mutatesTable(sql, 'trust_publish_queue'),
        maximumRowsPerBatch: 200,
        maximumMemberStatements: 16,
        maximumSingletonTailsPerWrite: 1,
        );
        expectBoundedTransactions(recorder);
        final syncStatements = recorder.statements.where(
          (statement) => statement.sql.contains('mr_sync'),
        );
        expect(
          syncStatements,
          hasLength(1),
          reason: 'Acknowledgement must retain MeritRank synchronization',
        );
        expect(
          syncStatements.every((statement) => statement.transaction == null),
          isTrue,
          reason:
              'MeritRank synchronization must run outside every transaction',
        );
      },
    );

    test(
      'acknowledgement synchronizes MeritRank after committing its writes',
      () async {
        late TransactionStatementRecorder recorder;
        recorder = TransactionStatementRecorder(
          select: _select,
          beforeStatement: (statement) async {
            if (!statement.sql.contains('mr_sync')) return;
            expectBoundedTransactions(recorder);
            expect(statement.transaction, isNull);
            expect(
              recorder.transactions.every((batch) => batch.committed),
              isTrue,
              reason:
                  'All acknowledgement writes must commit before sync starts',
            );
          },
        );
        final database = TenturaDb.forTest(database: recorder);
        addTearDown(database.close);

        await TrustPublishRepository(database).ack(
          1,
          [const PublishRow('publisher', 'peer', 0.5)],
        );

        expect(
          recorder.statements.where(
            (statement) => statement.sql.contains('mr_sync'),
          ),
          hasLength(1),
          reason: 'Successful acknowledgement must execute synchronization',
        );
      },
    );

    test(
      'a blocked MeritRank sync leaves the DB lane available after ack commit',
      () async {
        final syncStarted = Completer<void>();
        final releaseSync = Completer<void>();
        RecordedStatement? blockedSync;
        final recorder = TransactionStatementRecorder(
          select: _select,
          beforeStatement: (statement) async {
            if (!statement.sql.contains('mr_sync')) return;
            blockedSync = statement;
            syncStarted.complete();
            await releaseSync.future;
          },
        );
        final database = TenturaDb.forTest(database: recorder);
        final ack = TrustPublishRepository(database).ack(
          1,
          [const PublishRow('publisher', 'peer', 0.5)],
        );

        try {
          final syncIsBlocked = await Future.any([
            syncStarted.future.then((_) => true),
            ack.then((_) => false),
          ]).timeout(const Duration(seconds: 2));
          expect(
            syncIsBlocked,
            isTrue,
            reason:
                'The lane probe must run during acknowledgement synchronization',
          );

          final probe = await database
              .customSelect('SELECT 42 AS lane_probe')
              .getSingle()
              .then((row) => row.read<int>('lane_probe'))
              .timeout(
                const Duration(milliseconds: 250),
                onTimeout: () => -1,
              );

          expect(
            probe,
            42,
            reason: 'An unrelated read must finish while MeritRank is blocked',
          );
          expect(blockedSync!.transaction, isNull);
          expectBoundedTransactions(recorder);
          expect(
            recorder.transactions.every((batch) => batch.committed),
            isTrue,
          );
        } finally {
          if (!releaseSync.isCompleted) releaseSync.complete();
          await ack;
          await database.close();
        }
      },
    );
  });
}
