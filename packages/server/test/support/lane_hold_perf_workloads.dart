import 'package:drift_postgres/drift_postgres.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/domain/attention/attention_undo_models.dart';
import 'package:tentura_server/domain/port/trust_publish_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/contact_resolution_sweep_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import 'transaction_statement_recorder.dart';
import 'user_erasure_test_stack.dart';

/// Fresh executions of the production paths, on the selected perf database.
/// Seeding and cleanup are excluded from the lane-hold samples. No SQL result
/// or transaction clock is synthesized by this fixture.
final class LaneHoldPerfWorkloads {
  LaneHoldPerfWorkloads(this.writer, this.env)
    : recorder = TransactionStatementRecorder.executing(
        PgDatabase.opened(writer, enableMigrations: false),
      ),
      prefix = 'Lh${DateTime.now().microsecondsSinceEpoch}';

  final Connection writer;
  final Env env;
  final TransactionStatementRecorder recorder;
  final String prefix;
  late final database = TenturaDb.forTest(database: recorder);
  late final accountId = '${prefix}account';
  late final operationId = '${prefix}operation';
  final logger = Logger('LaneHoldPerfWorkloads');

  Future<void> _sql(String sql, [Map<String, Object?> parameters = const {}]) =>
      writer.execute(Sql.named(sql), parameters: parameters);

  Future<void> _users(int peers) async {
    await _sql(
      '''
INSERT INTO public."user" (id, display_name, public_key)
SELECT @prefix || 'peer' || n, 'Lane hold fixture', @prefix || 'key' || n
FROM generate_series(0, @peers::integer) n
''',
      {'prefix': prefix, 'peers': peers},
    );
    await _sql(
      '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@account, 'Lane hold fixture', @account || 'key')
''',
      {'account': accountId},
    );
  }

  Future<void> _receipts(int count) async {
    await _users(0);
    // Request-less profile receipts are authorized optional attention. This
    // isolates membership growth from request visibility and revision changes.
    await _sql(
      '''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, source_event_key, destination_kind, presentation_key,
  presentation_payload, suppression_class, access_policy, requires_action
)
SELECT @prefix || 'receipt' || n, @account, 'coordination',
       'coordinationChanged', 'normal', 'Fixture', 'Fixture', '/attention',
       @prefix || 'dedup' || n, @prefix || 'source' || n, 'profile',
       'mutual_connection_formed', '{"eventType":"fixture"}'::jsonb,
       'standard', 'profile', false
FROM generate_series(0, @count::integer - 1) n
''',
      {'prefix': prefix, 'account': accountId, 'count': count},
    );
  }

  void _startMeasurement() {
    recorder.statements.clear();
    recorder.transactions.clear();
  }

  Future<void> run(String path, int rows) async {
    switch (path) {
      case 'trust_publish_ack':
        await _users(rows);
        await _sql(
          '''
INSERT INTO public.user_trust_edge (subject, object, target_w, prev_sent_weight)
SELECT @account, @prefix || 'peer' || n, 0.5, 0.25
FROM generate_series(0, @rows::integer - 1) n
''',
          {'account': accountId, 'prefix': prefix, 'rows': rows},
        );
        await _sql(
          '''
INSERT INTO public.trust_publish_queue (subject_user_id, object_user_id)
SELECT @account, @prefix || 'peer' || n
FROM generate_series(0, @rows::integer - 1) n
''',
          {'account': accountId, 'prefix': prefix, 'rows': rows},
        );
        final repository = TrustPublishRepository(database);
        final token = await repository.acquireLease(prefix);
        check(token, isNotNull, reason: 'The perf publisher must own its lease');
        _startMeasurement();
        await repository.ack(token!, [
          for (var index = 0; index < rows; index++)
            PublishRow(accountId, '${prefix}peer$index', 0.5),
        ]);
        check(
          (await writer.execute(
            Sql.named('SELECT count(*) FROM public.trust_publish_queue '
                'WHERE subject_user_id = @account'),
            parameters: {'account': accountId},
          )).single.single,
          0,
          reason: 'Timing an empty or abandoned acknowledgement is not evidence',
        );
      case 'attention_capture':
      case 'attention_apply':
      case 'attention_undo':
        await _receipts(rows);
        final sweep = AttentionSweepRepository(database);
        if (path != 'attention_capture') {
          final prepared = await sweep.dismissAll(
            accountId: accountId,
            operationId: operationId,
            maxBatches: path == 'attention_undo' ? null : 0,
          );
          if (path == 'attention_undo') {
            check(prepared.appliedCount, rows);
          } else {
            check(prepared.pending, hasLength(rows));
          }
        }
        _startMeasurement();
        if (path == 'attention_undo') {
          final result = await sweep.undo(
            accountId: accountId,
            operationId: operationId,
            undoToken: AttentionUndoToken(
              accountId: accountId,
              operationId: operationId,
            ).encode(),
          );
          check(result.status, AttentionUndoStatus.complete);
          check(result.restoredReceiptIds, hasLength(rows));
        } else {
          final result = await sweep.dismissAll(
            accountId: accountId,
            operationId: operationId,
            maxBatches: path == 'attention_capture' ? 0 : 1,
          );
          check(
            path == 'attention_capture' ? result.pending.length : result.appliedCount,
            rows,
          );
        }
      case 'user_erasure_published':
      case 'user_erasure_drafts':
        await _users(0);
        final drafts = path == 'user_erasure_drafts';
        await _sql(
          '''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
SELECT @prefix || 'beacon' || n, @account, 'Fixture', 'Fixture', @status,
       CASE WHEN @drafts THEN NULL ELSE now() END
FROM generate_series(0, @rows::integer - 1) n
''',
          {
            'prefix': prefix,
            'account': accountId,
            'status': (drafts ? BeaconStatus.draft : BeaconStatus.deleted).smallintValue,
            'drafts': drafts,
            'rows': rows,
          },
        );
        final stack = buildUserErasureTestStack(
          db: database,
          userRepository: buildDefaultUserRepository(database),
          lifecycleEffects: BeaconLifecycleEffectsCase(
            BeaconHierarchyOutboxRepository(database),
            env: env,
            logger: logger,
          ),
          attention: TransactionalAttentionCase(
            MutatingUnitOfWork(database),
            AttentionDispatchRepository(database, logger),
          ),
        );
        _startMeasurement();
        check(await stack.erasureCase.deleteById(id: accountId), isTrue);
        final persisted = await writer.execute(
          Sql.named('SELECT title FROM public.beacon WHERE starts_with(id, @prefix)'),
          parameters: {'prefix': prefix},
        );
        check(persisted, hasLength(drafts ? 0 : rows));
        if (!drafts) {
          check(persisted.map((row) => row.single), everyElement('Deleted request'));
        }
      case 'contact_resolution':
        await _users(rows);
        await _sql(
          '''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@beacon, @account, 'Fixture', 'Fixture', 0)
''',
          {'beacon': '${prefix}beacon', 'account': accountId},
        );
        await _sql(
          '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, note, contact_deadline_at
)
SELECT @prefix || 'forward' || n, @prefix || 'beacon', @account,
       @prefix || 'peer' || n, '', now() - interval '1 day'
FROM generate_series(0, @rows::integer - 1) n
''',
          {'prefix': prefix, 'account': accountId, 'rows': rows},
        );
        // The insert trigger assigns the deadline; backdate it past every
        // unrelated overdue edge so this fixture owns the sweep's LIMIT.
        await _sql(
          '''
UPDATE public.beacon_forward_edge
SET contact_deadline_at = timestamptz '1970-01-02'
WHERE starts_with(id, @prefix)
''',
          {'prefix': prefix},
        );
        final sweep = ContactResolutionSweepCase(
          unitOfWork: MutatingUnitOfWork(database),
          forwardEdgeRepository: ForwardEdgeRepository(database),
          trustLedger: TrustLedgerRepository(database),
          env: env,
          logger: logger,
        );
        _startMeasurement();
        await sweep.run();
        check(
          (await writer.execute(
            Sql.named('SELECT count(*) FROM public.trust_evidence '
                'WHERE starts_with(source_key, @source)'),
            parameters: {'source': 'contact:${prefix}forward'},
          )).single.single,
          rows,
          reason: 'All fixture contacts must produce committed evidence',
        );
      default:
        fail('Unknown lane-hold workload: $path');
    }
    expectSyncOutsideTransactions(recorder);
    expectBoundedTransactions(recorder);
  }

  Future<void> close() async {
    await database.close();
    // Only this fixture's rows are removed; the retained baseline is untouched.
    await _sql('DELETE FROM public.trust_evidence WHERE starts_with(source_key, @prefix)',
        {'prefix': 'contact:${prefix}forward'});
    await _sql('DELETE FROM public.trust_publish_queue WHERE starts_with(subject_user_id, @prefix) '
        'OR starts_with(object_user_id, @prefix)', {'prefix': prefix});
    await _sql('DELETE FROM public.user_trust_edge WHERE starts_with(subject, @prefix) '
        'OR starts_with(object, @prefix)', {'prefix': prefix});
    await _sql("UPDATE public.trust_publisher_lease SET lease_until = now() - interval '1 second' "
        'WHERE owner = @prefix', {'prefix': prefix});
    await _sql('DELETE FROM public.attention_clear_operation WHERE starts_with(id, @prefix)',
        {'prefix': prefix});
    await _sql('DELETE FROM public.notification_outbox WHERE starts_with(id, @prefix)',
        {'prefix': prefix});
    await _sql('DELETE FROM public.beacon_forward_edge WHERE starts_with(id, @prefix)',
        {'prefix': prefix});
    await _sql('DELETE FROM public.beacon WHERE starts_with(id, @prefix)', {'prefix': prefix});
    await _sql('DELETE FROM public."user" WHERE starts_with(id, @prefix)', {'prefix': prefix});
  }
}
