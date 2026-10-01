@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/contact_resolution_sweep_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

/// B2: the writers of the contact-resolution transition table
/// (`docs/plans/episode-closure-architecture.md` § 6). Declining is covered in
/// `test/data/database/m0206_noisy_contact_pg_test.dart` (inbox trigger).
const _beaconId = 'Bcr0206beacon';
const _authorId = 'Ucr0206author';
const _senderId = 'Ucr0206sender';
const _recipientId = 'Ucr0206recip1';
const _thirdId = 'Ucr0206third1';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONTACT_RESOLUTION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_contact_res',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('contact resolution transitions', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late ForwardEdgeRepository forwardEdges;
    late ForwardCase forwardCase;
    late HelpOfferCase helpOfferCase;
    late ContactResolutionSweepCase sweep;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        database = openDisposablePgDatabase(target);
        forwardEdges = ForwardEdgeRepository(database);

        final env = target.databaseEnv;
        final logger = Logger('ContactResolutionPgTest');
        final unitOfWork = MutatingUnitOfWork(database);
        final attention = TransactionalAttentionCase(
          unitOfWork,
          AttentionDispatchRepository(database, logger),
        );
        final helpOffers = HelpOfferRepository(database);
        final beacons = BeaconRepository(database);
        final inbox = InboxRepository(database);

        forwardCase = ForwardCase(
          forwardEdges,
          _NoopForwardAttribution(),
          helpOffers,
          inbox,
          CapabilityEvidenceRepository(database),
          beacons,
          FakeUserBlockRepository(),
          _AllVisiblePeers(),
          FakeBeaconAccessGuard(),
          attention: attention,
          env: env,
          logger: logger,
        );
        helpOfferCase = HelpOfferCase(
          helpOffers,
          beacons,
          CommitmentRepository(database),
          inbox,
          CapabilityCase(
            PersonCapabilityEventRepository(database),
            env: env,
            logger: logger,
          ),
          FakeBeaconAccessGuard(),
          roomRepository: BeaconRoomRepository(database),
          attention: attention,
          env: env,
          logger: logger,
        );
        sweep = ContactResolutionSweepCase(
          unitOfWork: unitOfWork,
          forwardEdgeRepository: forwardEdges,
          trustLedger: TrustLedgerRepository(database),
          env: env,
          logger: logger,
        );
      });

      setUp(() async {
        await _resetFixture(writer);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: database);
      });
    }

    Future<String> createEdge({
      String sender = _senderId,
      String recipient = _recipientId,
    }) async {
      await forwardEdges.create(
        beaconId: _beaconId,
        senderId: sender,
        recipientId: recipient,
        note: '',
      );
      final rows = await writer.execute('''
SELECT id FROM public.beacon_forward_edge
WHERE beacon_id = '$_beaconId' AND sender_id = '$sender'
  AND recipient_id = '$recipient'
''');
      return rows.single.single! as String;
    }

    Future<void> pastDeadline(String edgeId) => writer.execute('''
UPDATE public.beacon_forward_edge
SET contact_deadline_at = now() - interval '1 hour'
WHERE id = '$edgeId'
''');

    test(
      'recipient offers help before the deadline: engaged evidence, resolved',
      () async {
        final edgeId = await createEdge();
        await helpOfferCase.offerHelp(
          beaconId: _beaconId,
          userId: _recipientId,
        );

        final contact = await _contact(writer, edgeId);
        expect(contact.outcome, 1);
        expect(contact.resolvedAt, isNotNull);
        final evidence = await _evidence(writer, 'contact:$edgeId:engaged');
        expect(evidence, isNotNull);
        expect(evidence!.subject, _recipientId);
        expect(evidence.object, _senderId);
        expect(evidence.kind, 6);
        expect(evidence.retracted, isFalse);
      },
      skip: skipReason,
    );

    test(
      'recipient forwards the request on before the deadline: '
      'engaged evidence on the incoming edge, resolved',
      () async {
        final edgeId = await createEdge();
        await forwardCase.forward(
          senderId: _recipientId,
          beaconId: _beaconId,
          recipientIds: [_thirdId],
        );

        final contact = await _contact(writer, edgeId);
        expect(contact.outcome, 1);
        expect(contact.resolvedAt, isNotNull);
        final evidence = await _evidence(writer, 'contact:$edgeId:engaged');
        expect(evidence, isNotNull);
        expect(evidence!.subject, _recipientId);
        expect(evidence.object, _senderId);
        expect(evidence.retracted, isFalse);
      },
      skip: skipReason,
    );

    test(
      'sender cancels before resolution: resolved with NULL outcome, '
      'no evidence',
      () async {
        final edgeId = await createEdge();
        expect(
          await forwardCase.cancelForward(
            edgeId: edgeId,
            senderId: _senderId,
          ),
          isTrue,
        );

        final contact = await _contact(writer, edgeId);
        expect(contact.outcome, isNull);
        expect(contact.resolvedAt, isNotNull);
        expect(await _contactEvidenceCount(writer), 0);
      },
      skip: skipReason,
    );

    test(
      'deadline passes unresolved: sweep records noisy and resolves as ignored',
      () async {
        final edgeId = await createEdge();
        await pastDeadline(edgeId);

        await sweep.run();

        final contact = await _contact(writer, edgeId);
        expect(contact.outcome, 3);
        expect(contact.resolvedAt, isNotNull);
        final evidence = await _evidence(writer, 'contact:$edgeId:noisy');
        expect(evidence, isNotNull);
        expect(evidence!.subject, _recipientId);
        expect(evidence.object, _senderId);
        expect(evidence.kind, 7);
        expect(evidence.retracted, isFalse);
      },
      skip: skipReason,
    );

    test(
      'sweep leaves edges before their deadline and already resolved edges',
      () async {
        final future = await createEdge();
        final cancelled = await createEdge(recipient: _thirdId);
        await forwardCase.cancelForward(
          edgeId: cancelled,
          senderId: _senderId,
        );
        await pastDeadline(cancelled);

        await sweep.run();

        expect((await _contact(writer, future)).resolvedAt, isNull);
        expect((await _contact(writer, cancelled)).outcome, isNull);
        expect(await _contactEvidenceCount(writer), 0);
      },
      skip: skipReason,
    );

    test(
      'sweep is idempotent: a second run adds no second noisy row',
      () async {
        final edgeId = await createEdge();
        await pastDeadline(edgeId);

        await sweep.run();
        await sweep.run();

        expect(await _contactEvidenceCount(writer), 1);
        expect((await _contact(writer, edgeId)).outcome, 3);
      },
      skip: skipReason,
    );

    test(
      'watching is neutral: no evidence after the deadline sweep',
      () async {
        final edgeId = await createEdge();
        await InboxRepository(database).setStatus(
          userId: _recipientId,
          beaconId: _beaconId,
          status: 1,
          rejectionMessage: '',
        );
        await pastDeadline(edgeId);

        await sweep.run();

        expect(await _contactEvidenceCount(writer), 0);
        expect((await _contact(writer, edgeId)).outcome, isNot(3));
      },
      skip: skipReason,
    );

    test(
      'late engagement after ignored retracts noisy and records engaged',
      () async {
        final edgeId = await createEdge();
        await pastDeadline(edgeId);
        await sweep.run();
        expect((await _contact(writer, edgeId)).outcome, 3);

        await helpOfferCase.offerHelp(
          beaconId: _beaconId,
          userId: _recipientId,
        );

        final noisy = await _evidence(writer, 'contact:$edgeId:noisy');
        expect(noisy, isNotNull);
        expect(noisy!.retracted, isTrue);
        final engaged = await _evidence(writer, 'contact:$edgeId:engaged');
        expect(engaged, isNotNull);
        expect(engaged!.retracted, isFalse);
        expect((await _contact(writer, edgeId)).outcome, 1);
      },
      skip: skipReason,
    );

    test(
      'late forward after ignored retracts noisy and records engaged',
      () async {
        final edgeId = await createEdge();
        await pastDeadline(edgeId);
        await sweep.run();

        await forwardCase.forward(
          senderId: _recipientId,
          beaconId: _beaconId,
          recipientIds: [_thirdId],
        );

        expect(
          (await _evidence(writer, 'contact:$edgeId:noisy'))!.retracted,
          isTrue,
        );
        expect(
          (await _evidence(writer, 'contact:$edgeId:engaged'))!.retracted,
          isFalse,
        );
        expect((await _contact(writer, edgeId)).outcome, 1);
      },
      skip: skipReason,
    );
  });
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.trust_evidence,
  public.beacon_forward_edge,
  public.inbox_item,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_authorId, _senderId, _recipientId, _thirdId]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_beaconId', '$_authorId', 'Contact beacon', 'desc', 0)
''');
}

Future<({int? outcome, DateTime? resolvedAt})> _contact(
  Connection writer,
  String edgeId,
) async {
  final row = (await writer.execute(
    Sql.named(
      'SELECT contact_outcome, contact_resolved_at '
      'FROM public.beacon_forward_edge WHERE id = @id',
    ),
    parameters: {'id': edgeId},
  )).single;
  return (outcome: row[0] as int?, resolvedAt: row[1] as DateTime?);
}

Future<int> _contactEvidenceCount(Connection writer) async {
  final rows = await writer.execute(
    'SELECT count(*)::int FROM public.trust_evidence '
    "WHERE source_key LIKE 'contact:%'",
  );
  return rows.single.single! as int;
}

Future<({String subject, String object, int kind, bool retracted})?> _evidence(
  Connection writer,
  String sourceKey,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT subject_user_id, object_user_id, kind, retracted_at IS NOT NULL '
      'FROM public.trust_evidence WHERE source_key = @k',
    ),
    parameters: {'k': sourceKey},
  );
  if (rows.isEmpty) return null;
  final r = rows.single;
  return (
    subject: r[0]! as String,
    object: r[1]! as String,
    kind: r[2]! as int,
    retracted: r[3]! as bool,
  );
}

class _AllVisiblePeers extends Fake implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async => peerIds.toSet();
}

class _NoopForwardAttribution extends Fake
    implements ForwardAttributionRepositoryPort {}
