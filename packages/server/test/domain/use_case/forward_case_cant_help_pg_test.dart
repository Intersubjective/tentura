@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

const _beaconId = 'Bcanthelp01';
const _postId = 'Bcanthelp02';
const _authorId = 'Ucanthauth1';
const _recipientId = 'Ucanthrcp01';
const _strangerId = 'Ucanthstr01';

/// #486 — «Can't help» on a forwarded Request tells the author, with the
/// recipient's note, once; nobody else hears the reason.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_CANT_HELP_TEST_DB',
    defaultNamePrefix: 'tentura_test_cant_help',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('ForwardCase.cantHelp (#486)', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late ForwardCase forwardCase;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      final env = target.databaseEnv;
      final logger = Logger('ForwardCaseCantHelpPgTest');
      final helpOffers = HelpOfferRepository(database);
      final commitments = CommitmentRepository(database);
      forwardCase = ForwardCase(
        ForwardEdgeRepository(database),
        _NoopForwardAttribution(),
        helpOffers,
        InboxRepository(database),
        CapabilityEvidenceRepository(database),
        BeaconRepository(database),
        FakeUserBlockRepository(),
        _AllVisiblePeers(),
        FakeBeaconAccessGuard(),
        attention: TransactionalAttentionCase(
          MutatingUnitOfWork(database),
          AttentionDispatchRepository(database, logger),
        ),
        attentionIntents: AttentionIntentCase(
          BeaconRoomNotificationContextRepository(
            BeaconRoomRepository(database),
            database,
            helpOffers,
            commitments,
          ),
          UserRepository(
            env,
            database,
            _NoopInviteGenealogyRepository(),
            InviteSeedPromptRepositoryMock(),
          ),
          BeaconAccessRepository(database),
          FakeUserBlockRepository(),
        ),
        env: env,
        logger: logger,
      );
    });

    setUp(() async {
      if (skipReason != false) return;
      await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.inbox_item,
  public.beacon,
  public."user"
CASCADE
''');
      for (final (id, name) in [
        (_authorId, 'Author'),
        (_recipientId, 'Nina Mover'),
        (_strangerId, 'Stranger'),
      ]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$name', 'key-$id')
''');
      }
      await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_beaconId', '$_authorId', 'Moving day', 'desc',
  ${BeaconStatus.open.smallintValue})
''');
      await writer.execute('''
INSERT INTO public.inbox_item (user_id, beacon_id, status)
VALUES ('$_recipientId', '$_beaconId', 0)
''');
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<List<Map<String, Object?>>> receipts(String accountId) async {
      final rows = await writer.execute('''
SELECT requires_action, presentation_payload::text
FROM public.notification_outbox
WHERE account_id = '$accountId' AND presentation_key = 'forward_declined'
''');
      return [
        for (final r in rows)
          {
            'requiresAction': r[0],
            'payload': jsonDecode(r[1]! as String),
          },
      ];
    }

    Future<(int, String)> inboxRow() async {
      final rows = await writer.execute('''
SELECT status, rejection_message FROM public.inbox_item
WHERE user_id = '$_recipientId' AND beacon_id = '$_beaconId'
''');
      return (rows.single[0]! as int, rows.single[1]! as String);
    }

    test('declines the row and tells the author, with the note', () async {
      final ok = await forwardCase.cantHelp(
        beaconId: _beaconId,
        userId: _recipientId,
        message: '  Away that weekend  ',
      );
      expect(ok, isTrue);
      expect(await inboxRow(), (2, 'Away that weekend'));
      final author = await receipts(_authorId);
      expect(author, hasLength(1));
      expect(author.single['requiresAction'], isFalse);
      final payload = author.single['payload']! as Map;
      expect(payload['targetEntityId'], _recipientId);
      expect(payload['eventType'], 'forwardDeclined');
      expect(payload['excerpt'], 'Away that weekend');
      expect(payload['actorUserId'], _recipientId);
      expect(await receipts(_recipientId), isEmpty);
    }, skip: skipReason);

    test('saving the note again does not tell the author twice', () async {
      await forwardCase.cantHelp(beaconId: _beaconId, userId: _recipientId);
      await forwardCase.cantHelp(
        beaconId: _beaconId,
        userId: _recipientId,
        message: 'Sorry',
      );
      expect(await inboxRow(), (2, 'Sorry'));
      expect(await receipts(_authorId), hasLength(1));
    }, skip: skipReason);

    test('someone with an active help offer is refused', () async {
      await writer.execute('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message)
VALUES ('$_beaconId', '$_recipientId', 'I can help')
''');
      expect(
        await forwardCase.cantHelp(beaconId: _beaconId, userId: _recipientId),
        isFalse,
      );
      expect((await inboxRow()).$1, 0);
      expect(await receipts(_authorId), isEmpty);
    }, skip: skipReason);

    test('a Request that never reached the viewer is refused', () async {
      expect(
        await forwardCase.cantHelp(beaconId: _beaconId, userId: _strangerId),
        isFalse,
      );
      expect(await receipts(_authorId), isEmpty);
    }, skip: skipReason);

    test('a closed-before-you-answered row stays as it is', () async {
      // The tombstone guard (m0246) admits this only as the beacon trigger.
      await writer.runTx((tx) async {
        await tx.execute(
          "SELECT set_config('tentura.allow_inbox_tombstone_transition', "
          "'1', true)",
        );
        await tx.execute('''
UPDATE public.inbox_item
SET status = 3, before_response_terminal_at = now()
WHERE user_id = '$_recipientId' AND beacon_id = '$_beaconId'
''');
      });
      expect(
        await forwardCase.cantHelp(beaconId: _beaconId, userId: _recipientId),
        isFalse,
      );
      expect((await inboxRow()).$1, 3);
      expect(await receipts(_authorId), isEmpty);
    }, skip: skipReason);

    test('a Post has no «Can’t help»', () async {
      await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  is_discoverable)
VALUES ('$_postId', '$_authorId', '', '', 0, 1, false)
''');
      await expectLater(
        forwardCase.cantHelp(beaconId: _postId, userId: _recipientId),
        throwsA(isA<BeaconNotRequestException>()),
      );
    }, skip: skipReason);
  }, skip: skipReason);
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

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
