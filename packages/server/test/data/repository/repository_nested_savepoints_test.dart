import 'package:injectable/injectable.dart' show Environment;
import 'package:test/fake.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/invite_seed_prompt_port.dart';
import 'package:tentura_server/env.dart';

import '../../support/savepoint_counting_interceptor.dart';
import '../../support/transaction_statement_recorder.dart';

const _actor = 'Usavepointactor1';

class _FakeGenealogy extends Fake implements InviteGenealogyRepositoryPort {}

class _FakeSeedPrompt extends Fake implements InviteSeedPromptPort {}

/// Runs [body] against a scripted database and returns how many savepoints it
/// opened. Rows are never found, so [body] may fail after its first
/// transaction boundary; failures are irrelevant to the count.
Future<({int savepoints, TransactionStatementRecorder recorder})> _measure(
  Future<void> Function(TenturaDb db) body, {
  SelectFixture? select,
  Future<void> Function(RecordedStatement)? beforeStatement,
}) async {
  final recorder = TransactionStatementRecorder(
    select: select ?? (_, _) => const [],
    beforeStatement: beforeStatement,
  );
  final counter = SavepointCountingInterceptor();
  final db = TenturaDb.forTest(database: recorder.interceptWith(counter));
  addTearDown(db.close);
  try {
    await body(db);
  } on Object {
    // Missing fixture rows are expected; only transaction structure matters.
  }
  return (savepoints: counter.savepoints, recorder: recorder);
}

UserRepository _users(TenturaDb db) => UserRepository(
  Env(environment: Environment.test, printEnv: false),
  db,
  _FakeGenealogy(),
  _FakeSeedPrompt(),
);

Future<void> _inActorUnitOfWork(
  TenturaDb db,
  Future<void> Function() action,
) => MutatingUnitOfWork(db).run<void>(actorUserId: _actor, action: action);

void main() {
  group('Repository methods joining an existing unit of work', () {
    test('publishing a draft Request opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => BeaconRepository(db).publishDraft(id: 'B1', actorId: _actor),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('publishing a draft Request standalone opens no savepoint', () async {
      final result = await _measure(
        (db) => BeaconRepository(db).publishDraft(id: 'B1', actorId: _actor),
      );
      expect(result.savepoints, 0);
    });

    test('publishing a child draft Request opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => BeaconRepository(
            db,
          ).publishChildDraft(childBeaconId: 'B2', actorId: _actor),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('recording a Request status transition opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => BeaconRepository(db).recordBeaconStatusTransition(
            beaconId: 'B1',
            fromStatus: BeaconStatus.open,
            toStatus: BeaconStatus.closed,
            reason: 'test',
            actorId: _actor,
          ),
        ),
      );
      expect(result.savepoints, 0);
    });

    test(
      'recording a status transition from a system unit of work opens no '
      'savepoint',
      () async {
        final result = await _measure(
          (db) => db.withMutatingSystem(
            () => BeaconRepository(db).recordBeaconStatusTransition(
              beaconId: 'B1',
              fromStatus: BeaconStatus.open,
              toStatus: BeaconStatus.closed,
              reason: 'test',
              actorId: null,
            ),
          ),
        );
        expect(result.savepoints, 0);
      },
    );

    test('cancelling a forward for a recipient opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => InboxRepository(db).markForwardCancelledForRecipient(
            beaconId: 'B1',
            recipientId: 'Urecipient0001',
          ),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('blocking a user opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => UserBlockRepository(
            Env(environment: Environment.test, printEnv: false),
            db,
          ).block(blockerId: _actor, blockedId: 'Ublocked00001', cascadeMode: 0),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('unblocking a user opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => UserBlockRepository(
            Env(environment: Environment.test, printEnv: false),
            db,
          ).unblock(blockerId: _actor, blockedId: 'Ublocked00001'),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('promoting a block to direct opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => UserBlockRepository(
            Env(environment: Environment.test, printEnv: false),
            db,
          ).promoteToDirect(blockerId: _actor, blockedId: 'Ublocked00001'),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('invited signup with a key opens no savepoint', () async {
      final result = await _measure(
        (db) => db.withTransaction(
          () => _users(db).createInvited(
            invitationId: 'I1',
            publicKey: 'key',
            displayName: 'Name',
          ),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('invited signup with a credential opens no savepoint', () async {
      final result = await _measure(
        (db) => db.withTransaction(
          () => _users(db).createInvitedWithCredential(
            invitationId: 'I1',
            type: CredentialType.emailOtp,
            identifier: 'a@example.com',
            displayName: 'Name',
          ),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('binding an existing account to an invitation opens no savepoint',
        () async {
      final result = await _measure(
        (db) => db.withTransaction(
          () => _users(db).bindMutual(invitationId: 'I1', userId: _actor),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('updating a coordination item status opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => CoordinationItemRepository(
            db,
          ).updateStatus(id: 'C1', newStatus: 1, actorId: _actor),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('creating a coordination item opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => CoordinationItemRepository(db).create(beaconId: 'B1', kind: 1, creatorId: _actor, title: 't'),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('accepting a coordination item opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => CoordinationItemRepository(db).acceptItem(id: 'C1', actorId: _actor, acceptedById: _actor),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('redirecting a coordination item target opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => CoordinationItemRepository(db).redirectTarget(id: 'C1', actorId: _actor, newTargetPersonId: 'Utarget000001'),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('publishing a coordination item draft opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => CoordinationItemRepository(db).publishDraft(id: 'C1', actorId: _actor, targetPersonId: 'Utarget000001'),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('updating a published coordination item opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => CoordinationItemRepository(db).updatePublishedItem(id: 'C1', actorId: _actor, title: 't'),
        ),
      );
      expect(result.savepoints, 0);
    });

    test('publishing a coordination item blocker draft opens no savepoint', () async {
      final result = await _measure(
        (db) => _inActorUnitOfWork(
          db,
          () => CoordinationItemRepository(db).publishDraftBlocker(id: 'C1', actorId: _actor),
        ),
      );
      expect(result.savepoints, 0);
    });
  });

  group('Promotion publication conflict recovery', () {
    const insertMarker = 'INSERT INTO public.beacon_promotions';

    Future<void> failUniqueInsert(RecordedStatement statement) async {
      if (statement.sql.contains(insertMarker)) {
        throw StateError(
          'duplicate key value violates unique constraint '
          '"beacon_promotions_published_source_uidx" '
          'Key (source_message_id)=(Msource00001) already exists.',
        );
      }
    }

    test(
      'a conflicting insert is isolated in a savepoint and reported with '
      'the already published child',
      () async {
        Object? failure;
        final result = await _measure(
          (db) => _inActorUnitOfWork(db, () async {
            try {
              await BeaconHierarchyCommandRepository(db).markPromotionPublished(
                childBeaconId: 'Bchild000001',
                parentBeaconId: 'Bparent00001',
                sourceMessageId: 'Msource00001',
                promoterUserId: _actor,
              );
            } on Object catch (error) {
              failure = error;
            }
          }),
          select: (sql, _) => sql.contains('FROM public.beacon_promotions')
              ? [
                  {'child_beacon_id': 'Bexisting001'},
                ]
              : const [],
          beforeStatement: failUniqueInsert,
        );

        expect(failure, isA<BeaconPromotionPublishConflict>());
        expect(
          (failure! as BeaconPromotionPublishConflict).existingChildBeaconId,
          'Bexisting001',
        );
        expect(
          result.savepoints,
          1,
          reason: 'The recovery savepoint is the one designated exception',
        );
        final lookups = result.recorder.statements.where(
          (s) => s.sql.contains('FROM public.beacon_promotions'),
        );
        expect(lookups, isNotEmpty);
      },
    );
  });
}
