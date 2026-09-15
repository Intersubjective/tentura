@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('HelpOfferCase expectedOfferKind — real row lock', () {
    late Connection writer;
    late TenturaDb db;
    late HelpOfferCase case_;
    late HelpOfferRepository helpOffers;
    late CommitmentRepository commitments;
    late AttentionDispatchRepository dispatch;

    const authorId = 'Uhokauthor01';
    const offererId = 'Uhokoffer01';
    const beaconId = 'Bhok00000001';

    Future<void> insertUser(String id, {required int slot}) => db.customStatement(
      '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', '${pgTestPublicKey('hok', slot)}', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
    );

    Future<void> reciprocalTrust(String a, String b) => db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$a', '$b', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$b', '$a', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

    Future<void> insertBeacon({required int status}) => db.customStatement('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$beaconId', '$authorId', 'title', 'desc', $status, true,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status
''');

    Future<int> countHelpOffers() async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon_help_offer WHERE beacon_id = @id',
        ),
        parameters: {'id': beaconId},
      );
      return rows.single.first! as int;
    }

    Future<int> countCommitments() async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon_commitment_event WHERE beacon_id = @id',
        ),
        parameters: {'id': beaconId},
      );
      return rows.single.first! as int;
    }

    Future<int> countAttentionOutbox() async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.notification_outbox WHERE beacon_id = @id',
        ),
        parameters: {'id': beaconId},
      );
      return rows.single.first! as int;
    }

    if (skipReason == false) {
      setUpAll(() async {
        await target.recreate();
        writer = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        await writer.execute('SET check_function_bodies = false');
        await migrateDbSchema(writer);
        db = TenturaDb(target.databaseEnv);
        final env = Env(environment: Environment.test);
        final logger = Logger('help_offer_expected_kind_pg_test');
        final beacons = BeaconRepository(db);
        helpOffers = HelpOfferRepository(db);
        commitments = CommitmentRepository(db);
        dispatch = AttentionDispatchRepository(db, logger);
        final room = BeaconRoomRepository(db);
        final access = BeaconAccessRepository(db);
        final attentionIntents = AttentionIntentCase(
          BeaconRoomNotificationContextRepository(
            room,
            db,
            helpOffers,
            commitments,
          ),
          UserRepository(
            env,
            db,
            _NoopTrustEvidenceRepository(),
            _NoopInviteGenealogyRepository(),
            InviteSeedPromptRepositoryMock(),
          ),
          access,
          FakeUserBlockRepository(),
        );
        final attention = TransactionalAttentionCase(
          MutatingUnitOfWork(db),
          dispatch,
        );
        final capabilityCase = CapabilityCase(
          PersonCapabilityEventRepository(db),
          env: env,
          logger: logger,
        );
        case_ = HelpOfferCase(
          helpOffers,
          beacons,
          commitments,
          InboxRepository(db),
          capabilityCase,
          access,
          roomRepository: room,
          attentionIntents: attentionIntents,
          attention: attention,
          env: env,
          logger: logger,
        );
      });

      setUp(() async {
        await db.customStatement('DELETE FROM public.notification_outbox');
        await db.customStatement('DELETE FROM public.beacon_commitment_event');
        await db.customStatement('DELETE FROM public.beacon_help_offer');
        await db.customStatement('DELETE FROM public.beacon');
        await db.customStatement('DELETE FROM public.vote_user');
        await db.customStatement('DELETE FROM public."user"');
        await insertUser(authorId, slot: 1);
        await insertUser(offererId, slot: 2);
        await reciprocalTrust(authorId, offererId);
        await insertBeacon(status: BeaconStatus.open.smallintValue);
      });

      tearDownAll(() async {
        await db.close();
        await writer.close();
        await target.drop();
      });
    }

    test(
      'checks newly committed locked state and rejects mismatch without writes',
      () async {
        await writer.execute('BEGIN');
        await writer.execute(
          Sql.named(
            'SELECT id FROM public.beacon WHERE id = @id FOR UPDATE',
          ),
          parameters: {'id': beaconId},
        );

        final offerFuture = case_.offerHelp(
          beaconId: beaconId,
          userId: offererId,
          expectedOfferKind: 0,
        );

        await Future<void>.delayed(const Duration(milliseconds: 200));
        await writer.execute(
          Sql.named(
            'UPDATE public.beacon SET status = @status WHERE id = @id',
          ),
          parameters: {
            'id': beaconId,
            'status': BeaconStatus.enoughHelp.smallintValue,
          },
        );
        await writer.execute('COMMIT');

        await expectLater(
          offerFuture,
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) =>
                  (e.code as HelpOfferCoordinationExceptionCodes).exceptionCode,
              'code',
              HelpOfferCoordinationExceptionCode.offerKindChanged,
            ),
          ),
        );

        expect(await countHelpOffers(), 0);
        expect(await countCommitments(), 0);
        expect(await countAttentionOutbox(), 0);
      },
      skip: skipReason,
    );
  });
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

final class _DisposablePgTarget {
  _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? 'localhost';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        'tentura_test_hok_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS ${_quoteIdent(databaseName)} WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE ${_quoteIdent(databaseName)}');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS ${_quoteIdent(databaseName)} WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }

  static String _quoteIdent(String value) => '"${value.replaceAll('"', '""')}"';
}
