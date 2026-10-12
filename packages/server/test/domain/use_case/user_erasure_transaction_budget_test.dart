import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_erasure_repository.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/transaction_statement_recorder.dart';

const _ownedRows = 1201;
// Test safety ceilings, independent of the attention feature's batching API.
// These allow erasure-specific chunk sizes (e.g. 100, 200, 256, or 512).
const _maximumErasureRowsPerBatch = 512;

void main() {
  group('Account erasure transaction budgets', () {
    for (final drafts in [false, true]) {
      test(
        'erasing many ${drafts ? 'draft' : 'deleted published'} Requests '
        'releases the lane between bounded SQL batches',
        () async {
          final recorder = TransactionStatementRecorder(
            select: (sql, arguments) {
              if (!sql.contains('FROM public.beacon') ||
                  !sql.contains('ORDER BY id')) {
                return [];
              }
              final published = sql.contains('published_at IS NOT NULL');
              if (published == drafts) return [];
              return List.generate(
                _ownedRows,
                (index) => {
                  'id': 'owned-$index',
                  'status': (drafts ? BeaconStatus.draft : BeaconStatus.deleted)
                      .smallintValue,
                },
              );
            },
          );
          final database = TenturaDb.forTest(database: recorder);
          addTearDown(database.close);
          final users = _Users(database);
          final env = Env(environment: Environment.test, printEnv: false);
          final logger = Logger('UserErasureTransactionBudgetTest');
          final erasure = UserErasureCase(
            UserErasureRepository(database),
            _Beacons(),
            users,
            FakeBeaconHierarchyRepository(),
            BeaconLifecycleEffectsCase(_Outbox(), env: env, logger: logger),
            TransactionalAttentionCase(
              MutatingUnitOfWork(database),
              _Attention(),
            ),
            _ImageGc(),
            env: env,
            logger: logger,
          );

          expect(await erasure.deleteById(id: 'account'), isTrue);
          expect(users.deleted, isTrue);
          expect(
            recorder.statements.any(
              (statement) => statement.sql.contains(
                drafts ? 'DELETE FROM public.beacon' : 'UPDATE public.beacon',
              ),
            ),
            isTrue,
            reason: 'The measurement must execute content erasure',
          );
          expectSetBasedWorkload(
            recorder,
            memberIds: {
              for (var index = 0; index < _ownedRows; index++) 'owned-$index',
            },
            isMemberWrite: (sql) =>
                mutatesTable(sql, 'beacon') ||
                mutatesTable(sql, 'beacon_image') ||
                mutatesTable(sql, 'beacon_image_stage'),
            maximumRowsPerBatch: _maximumErasureRowsPerBatch,
            maximumSingletonTailsPerWrite: 1,
          );
          expectBoundedTransactions(
            recorder,
            minimumCommittedBatches: (_ownedRows / _maximumErasureRowsPerBatch)
                .ceil(),
          );
        },
      );
    }
  });
}

class _Users extends Fake implements UserRepositoryPort {
  _Users(this.database);

  final TenturaDb database;
  bool deleted = false;

  @override
  Future<bool> deleteById({required String id}) async {
    await database.customStatement(
      r'DELETE FROM public."user" WHERE id = $1',
      [id],
    );
    deleted = true;
    return true;
  }
}

class _Beacons extends Fake implements BeaconRepositoryPort {}

class _Outbox extends Fake implements BeaconHierarchyOutboxPort {}

class _Attention extends Fake implements AttentionDispatchPort {}

class _ImageGc extends Fake implements ImageObjectGcPort {}
