@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

const _beaconId = 'Bcapc3bcn001';
const _authorId = 'Ucapc3auth01';
const _senderId = 'Ucapc3send01';
const _recipientId = 'Ucapc3recip1';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('ForwardCase forward-reason reconciliation (C3a)', () {
    late Connection writer;
    late TenturaDb database;
    late ForwardCase forwardCase;
    late ForwardEdgeRepository forwardEdgeRepo;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      database = TenturaDb(target.databaseEnv);
      forwardEdgeRepo = ForwardEdgeRepository(database);
      final beaconRepo = BeaconRepository(database);
      final helpOfferRepo = HelpOfferRepository(database);
      final capEvidenceRepo = CapabilityEvidenceRepository(database);
      final unitOfWork = MutatingUnitOfWork(database);
      final dispatch = _NoopAttentionDispatch();
      final attention = TransactionalAttentionCase(unitOfWork, dispatch);
      final intents = AttentionIntentCase(
        _NoopNotificationContext(),
        _NoopUsers(),
        FakeBeaconAccessGuard(),
        FakeUserBlockRepository(),
      );

      forwardCase = ForwardCase(
        forwardEdgeRepo,
        _NoopForwardAttribution(),
        helpOfferRepo,
        _NoopInbox(),
        capEvidenceRepo,
        beaconRepo,
        FakeUserBlockRepository(),
        _AllVisiblePeers(),
        FakeBeaconAccessGuard(),
        attentionIntents: intents,
        attention: attention,
        env: target.databaseEnv,
        logger: Logger('ForwardReasonReconciliationPgTest'),
      );
    });

    setUp(() async {
      await writer.execute(r'''
DELETE FROM public.person_capability_event
WHERE observer_user_id LIKE 'Ucapc3%'
   OR subject_user_id LIKE 'Ucapc3%'
''');
      await writer.execute(r'''
DELETE FROM public.capability_evidence_edge
WHERE observer_user_id LIKE 'Ucapc3%'
   OR subject_user_id LIKE 'Ucapc3%'
''');
      await writer.execute(r'''
DELETE FROM public.capability_evidence_generation
WHERE observer_user_id LIKE 'Ucapc3%'
   OR subject_user_id LIKE 'Ucapc3%'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_forward_edge
WHERE beacon_id = 'Bcapc3bcn001'
''');
      await _seedFixture(writer);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    Future<String> createEdgeWithTransport() async {
      await forwardCase.forward(
        senderId: _senderId,
        beaconId: _beaconId,
        recipientIds: [_recipientId],
        sharedReasonSlugs: const ['transport'],
      );
      final edge = await forwardEdgeRepo.findActiveEdge(
        beaconId: _beaconId,
        senderId: _senderId,
        recipientId: _recipientId,
      );
      expect(edge, isNotNull);
      return edge!.id;
    }

    test(
      'updateForward transport then pets leaves exactly one active reason row',
      () async {
        final edgeId = await createEdgeWithTransport();
        expect(await _activeForwardSlugs(writer, edgeId), ['transport']);

        expect(
          await forwardCase.updateForward(
            edgeId: edgeId,
            senderId: _senderId,
            note: 'pets note',
            reasonSlugs: const ['pets'],
          ),
          isTrue,
        );

        expect(await _activeForwardSlugs(writer, edgeId), ['pets']);
      },
      skip: skipReason,
    );

    test(
      'cancelForward reconciles seed evidence away',
      () async {
        final edgeId = await createEdgeWithTransport();
        expect(await _activeForwardSlugs(writer, edgeId), isNotEmpty);

        expect(
          await forwardCase.cancelForward(edgeId: edgeId, senderId: _senderId),
          isTrue,
        );

        expect(await _activeForwardSlugs(writer, edgeId), isEmpty);
        final edge = await forwardEdgeRepo.fetchById(edgeId);
        expect(edge?.cancelledAt, isNotNull);
      },
      skip: skipReason,
    );

    test(
      'updateForward explicit empty list clears reasons',
      () async {
        final edgeId = await createEdgeWithTransport();
        expect(
          await forwardCase.updateForward(
            edgeId: edgeId,
            senderId: _senderId,
            note: 'cleared',
            reasonSlugs: const [],
          ),
          isTrue,
        );
        expect(await _activeForwardSlugs(writer, edgeId), isEmpty);
      },
      skip: skipReason,
    );

    test(
      'updateForward null reasonSlugs leaves existing set untouched',
      () async {
        final edgeId = await createEdgeWithTransport();

        expect(
          await forwardCase.updateForward(
            edgeId: edgeId,
            senderId: _senderId,
            note: 'note only',
          ),
          isTrue,
        );
        expect(await _activeForwardSlugs(writer, edgeId), ['transport']);

        expect(
          await forwardCase.updateForward(
            edgeId: edgeId,
            senderId: _senderId,
            note: 'cleared explicitly',
            reasonSlugs: const [],
          ),
          isTrue,
        );
        expect(await _activeForwardSlugs(writer, edgeId), isEmpty);
      },
      skip: skipReason,
    );

    test(
      'cancel then re-forward yields independent reason set on new edge',
      () async {
        final firstEdgeId = await createEdgeWithTransport();
        expect(
          await forwardCase.cancelForward(
            edgeId: firstEdgeId,
            senderId: _senderId,
          ),
          isTrue,
        );
        expect(await _activeForwardSlugs(writer, firstEdgeId), isEmpty);

        await forwardCase.forward(
          senderId: _senderId,
          beaconId: _beaconId,
          recipientIds: [_recipientId],
          sharedReasonSlugs: const ['pets'],
        );
        final secondEdge = await forwardEdgeRepo.findActiveEdge(
          beaconId: _beaconId,
          senderId: _senderId,
          recipientId: _recipientId,
        );
        expect(secondEdge, isNotNull);
        expect(secondEdge!.id, isNot(firstEdgeId));
        expect(await _activeForwardSlugs(writer, secondEdge.id), ['pets']);
        expect(await _activeForwardSlugs(writer, firstEdgeId), isEmpty);
      },
      skip: skipReason,
    );

    test(
      'invalid reason slug rolls back edge creation',
      () async {
        await expectLater(
          forwardCase.forward(
            senderId: _senderId,
            beaconId: _beaconId,
            recipientIds: [_recipientId],
            sharedReasonSlugs: const ['__invalid_slug__'],
          ),
          throwsA(isA<ExceptionBase>()),
        );

        final edge = await forwardEdgeRepo.findActiveEdge(
          beaconId: _beaconId,
          senderId: _senderId,
          recipientId: _recipientId,
        );
        expect(edge, isNull);
        expect(await _forwardReasonCountForPair(writer), 0);
      },
      skip: skipReason,
    );
  });
}

Future<List<String>> _activeForwardSlugs(
  Connection writer,
  String edgeId,
) async {
  final rows = await writer.execute(
    Sql.named(r'''
SELECT tag_slug
FROM public.person_capability_event
WHERE forward_edge_id = @edgeId
  AND source_type = 1
  AND deleted_at IS NULL
ORDER BY tag_slug
'''),
    parameters: {'edgeId': edgeId},
  );
  return rows.map((r) => r[0]! as String).toList();
}

Future<int> _forwardReasonCountForPair(Connection writer) async {
  final rows = await writer.execute(r'''
SELECT count(*)::int
FROM public.person_capability_event
WHERE observer_user_id = 'Ucapc3send01'
  AND subject_user_id = 'Ucapc3recip1'
  AND source_type = 1
  AND deleted_at IS NULL
''');
  return rows.single.single! as int;
}

Future<void> _seedFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Ucapc3auth01', 'Author', 'pk-auth'),
  ('Ucapc3send01', 'Sender', 'pk-send'),
  ('Ucapc3recip1', 'Recipient', 'pk-recip')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (
  'Bcapc3bcn001',
  'Ucapc3auth01',
  'Forward reason beacon',
  'd',
  0
)
ON CONFLICT DO NOTHING
''');
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

class _AllVisiblePeers extends Fake implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> mutuallyVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async =>
      peerIds.toSet();
}

class _NoopForwardAttribution extends Fake
    implements ForwardAttributionRepositoryPort {}

class _NoopInbox extends Fake implements InboxRepositoryPort {
  @override
  Future<void> upsertWatchingForSender({
    required String senderId,
    required String beaconId,
    String? context,
    bool touchForwardOrdering = true,
  }) async {}

  @override
  Future<void> markForwardCancelledForRecipient({
    required String beaconId,
    required String recipientId,
  }) async {}
}

class _NoopAttentionDispatch extends Fake
    implements AttentionDispatchPort {
  @override
  Future<void> record(AttentionDispatchIntent intent) async {}
}

class _NoopNotificationContext extends Fake
    implements BeaconRoomNotificationContextPort {}

class _NoopUsers extends Fake implements UserRepositoryPort {
  @override
  Future<UserEntity> getById(String id) async => UserEntity(id: id);
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_FORWARD_REASON_TEST_DB'] ??
        'tentura_test_forward_reason_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';

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

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final admin = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await admin.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await admin.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await admin.close();
    }
  }

  Future<void> drop() async {
    final admin = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await admin.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await admin.close();
    }
  }
}
