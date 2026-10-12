import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/domain/attention/attention_sweep_models.dart';
import 'package:tentura_server/domain/attention/attention_undo_models.dart';

import '../../support/transaction_statement_recorder.dart';

const _accountId = 'account';
const _operationId = 'clear-operation';
const _largeMembership = 1201;

Set<String> _memberIds(List<Map<String, Object?>> members) => {
  for (final member in members)
    (member['receipt_id'] ?? member['outcome_beacon_id'])! as String,
};

bool _attentionMemberWrite(String sql) =>
    mutatesTable(sql, 'attention_clear_operation_member') ||
    mutatesTable(sql, 'notification_outbox') ||
    mutatesTable(sql, 'inbox_item');

List<Map<String, Object?>> _members(int count, {required String state}) =>
    List.generate(
      count,
      (index) => {
        'receipt_id': index.isEven ? 'receipt-$index' : null,
        'outcome_beacon_id': index.isOdd ? 'beacon-$index' : null,
        'outcome_generation': 0,
        'decision_revision': 0,
        'state': state,
        'skip_reason': null,
      },
    );

List<Map<String, Object?>> _eligible(List<Map<String, Object?>> members) => [
  for (final member in members)
    {
      'kind': member['receipt_id'] == null ? 'outcome' : 'receipt',
      'member_id': member['receipt_id'] ?? member['outcome_beacon_id'],
      'beacon_id': member['outcome_beacon_id'],
      'outcome_generation': 0,
      'decision_revision': 0,
    },
];

void main() {
  group('Activity clear and undo transaction budgets', () {
    test(
      'capturing a large clear operation commits bounded set-based chunks',
      () async {
        final members = _members(_largeMembership, state: 'pending');
        final recorder = TransactionStatementRecorder(
          select: (sql, arguments) {
            if (sql == AttentionSweepRepository.captureSql) {
              return _eligible(members);
            }
            if (sql.contains('SELECT receipt_id, outcome_beacon_id, state')) {
              return members;
            }
            return [];
          },
        );
        final database = TenturaDb.forTest(database: recorder);
        addTearDown(database.close);

        final result = await AttentionSweepRepository(database).dismissAll(
          accountId: _accountId,
          operationId: _operationId,
          // Isolate capture from apply: a bounded request must not first hold
          // the lane for one INSERT per member across the entire surface.
          maxBatches: 0,
        );

        expect(result.pending, hasLength(_largeMembership));
        expect(result.appliedCount, 0);
        expectSetBasedWorkload(
          recorder,
          memberIds: _memberIds(members),
          isMemberWrite: (sql) =>
              mutatesTable(sql, 'attention_clear_operation_member'),
          maximumRowsPerBatch: AttentionSweepLimits.maxBatchSize,
          maximumMemberStatements: 16,
          maximumSingletonTailsPerWrite: 1,
        );
        expectBoundedTransactions(
          recorder,
          minimumCommittedBatches:
              (members.length / AttentionSweepLimits.maxBatchSize).ceil(),
        );
      },
    );

    test(
      'applying a full clear batch uses constant SQL for both attention axes',
      () async {
        final members = _members(
          AttentionSweepLimits.batchSize,
          state: 'applied',
        );
        final recorder = TransactionStatementRecorder(
          // Resume an existing capture so only apply is measured here.
          affectedRows: (sql, arguments) =>
              sql.contains('INSERT INTO public.attention_clear_operation\n')
              ? 0
              : 1,
          select: (sql, arguments) {
            if (sql.contains('SELECT account_id')) {
              return [
                {'account_id': _accountId},
              ];
            }
            if (sql.contains("state = 'pending'") && sql.contains('LIMIT')) {
              return members;
            }
            if (sql.startsWith('WITH ') && sql.contains('AS member_id')) {
              return _eligible(members);
            }
            if (sql.contains('SELECT id FROM public.notification_outbox')) {
              return [
                for (final member in members)
                  if (member['receipt_id'] != null)
                    {'id': member['receipt_id']},
              ];
            }
            if (sql.contains('SELECT receipt_id, outcome_beacon_id, state')) {
              return members;
            }
            return [];
          },
        );
        final database = TenturaDb.forTest(database: recorder);
        addTearDown(database.close);

        final result = await AttentionSweepRepository(database).dismissAll(
          accountId: _accountId,
          operationId: _operationId,
          maxBatches: 1,
        );

        expect(result.appliedReceiptIds, hasLength(100));
        expect(result.appliedOutcomeBeaconIds, hasLength(100));
        expectSetBasedWorkload(
          recorder,
          memberIds: _memberIds(members),
          isMemberWrite: _attentionMemberWrite,
          maximumRowsPerBatch: AttentionSweepLimits.maxBatchSize,
          maximumMemberStatements: 16,
        );
        expectBoundedTransactions(recorder);
      },
    );

    test(
      'undoing a large clear operation releases the lane between chunks',
      () async {
        final members = _members(_largeMembership, state: 'applied');
        final recorder = TransactionStatementRecorder(
          select: (sql, arguments) {
            if (sql.contains('AS never_applied')) {
              return [
                {
                  'account_id': _accountId,
                  'never_applied': false,
                  'expired': false,
                },
              ];
            }
            if (sql.contains('SELECT receipt_id, outcome_beacon_id, state')) {
              return members;
            }
            if (sql.contains('UPDATE public.notification_outbox') ||
                sql.contains('UPDATE public.inbox_item')) {
              return [
              for (final id in referencedMemberIds(arguments, _memberIds(members)))
                {'id': id},
              ];
            }
            return [];
          },
        );
        final database = TenturaDb.forTest(database: recorder);
        addTearDown(database.close);

        final result = await AttentionSweepRepository(database).undo(
          accountId: _accountId,
          operationId: _operationId,
          undoToken: const AttentionUndoToken(
            accountId: _accountId,
            operationId: _operationId,
          ).encode(),
        );

        expect(result.status, AttentionUndoStatus.complete);
        expectSetBasedWorkload(
          recorder,
          memberIds: _memberIds(members),
          isMemberWrite: _attentionMemberWrite,
          maximumRowsPerBatch: AttentionSweepLimits.maxBatchSize,
        );
        expect(
          result.restoredReceiptIds.length +
              result.restoredOutcomeBeaconIds.length,
          _largeMembership,
        );
        expectBoundedTransactions(
          recorder,
          minimumCommittedBatches:
              (_largeMembership / AttentionSweepLimits.maxBatchSize).ceil(),
        );
      },
    );
  });
}
