@Tags(['pg', 'mr'])
library;


import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

import '../../support/disposable_pg_target.dart';

const _viewerId = 'Upvrepo_viewer';
const _peerAId = 'Upvrepo_peera1';
const _blockedPeerId = 'Upvrepo_block1';
const _beaconId = 'Bpvrepo00001';
const _authorId = 'Upvrepo_author';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_VISIBILITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_person_visibility',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('PersonVisibilityRepository symmetric send-time check', () {
    late Connection writer;
    late TenturaDb database;
    late PersonVisibilityRepository visibilityRepo;
    late ForwardCase forwardCase;
    late ForwardEdgeRepository forwardEdgeRepo;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);

      database = TenturaDb(target.databaseEnv);
      visibilityRepo = PersonVisibilityRepository(database);
      forwardEdgeRepo = ForwardEdgeRepository(database);
      final helpOfferRepo = HelpOfferRepository(database);
      final unitOfWork = MutatingUnitOfWork(database);
      final attention = TransactionalAttentionCase(
        unitOfWork,
        _NoopAttentionDispatch(),
      );
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
        _NoopCapabilityEvidence(),
        _StaticBeaconRepo(),
        FakeUserBlockRepository(),
        visibilityRepo,
        FakeBeaconAccessGuard(),
        attentionIntents: intents,
        attention: attention,
        env: target.databaseEnv,
        logger: Logger('PersonVisibilityRepositoryPgTest'),
      );
    });

    setUp(() async {
      await writer.execute(r'''
DELETE FROM public.beacon_forward_edge WHERE beacon_id = 'Bpvrepo00001'
''');
      await writer.execute(r'''
DELETE FROM public.beacon WHERE id = 'Bpvrepo00001'
''');
      await writer.execute(r'''
DELETE FROM public.user_block
WHERE blocker_id LIKE 'Upvrepo_%' OR blocked_id LIKE 'Upvrepo_%'
''');
      await writer.execute(r'''
DELETE FROM public.vote_user
WHERE subject LIKE 'Upvrepo_%' OR object LIKE 'Upvrepo_%'
''');
      await writer.execute(r'''
DELETE FROM public."user" WHERE id LIKE 'Upvrepo_%'
''');
      await _seedAsymmetricFixture(writer);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test(
      'mutuallyVisiblePeerIds returns repaired symmetry pair',
      () async {
        final visible = await visibilityRepo.mutuallyVisiblePeerIds(
          viewerId: _viewerId,
          peerIds: [_peerAId],
          context: '',
        );
        expect(visible, {_peerAId});
      },
      skip: skipReason,
    );

    test('mutuallyVisiblePeerIds excludes blocked peer', () async {
      await writer.execute(r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('Upvrepo_viewer', 'Upvrepo_block1', 'Upvrepo_block1')
ON CONFLICT DO NOTHING
''');

      final visible = await visibilityRepo.mutuallyVisiblePeerIds(
        viewerId: _viewerId,
        peerIds: [_blockedPeerId],
        context: '',
      );
      expect(visible, isEmpty);
    }, skip: skipReason);

    test(
      'ForwardCase authorizes send to symmetry-repaired peer via real port',
      () async {
        final result = await forwardCase.forward(
          senderId: _viewerId,
          beaconId: _beaconId,
          recipientIds: [_peerAId],
        );

        expect(result.deliveredRecipientIds, [_peerAId]);
        final edge = await forwardEdgeRepo.findActiveEdge(
          beaconId: _beaconId,
          senderId: _viewerId,
          recipientId: _peerAId,
        );
        expect(edge, isNotNull);
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedAsymmetricFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Upvrepo_viewer', 'Viewer', 'pk-viewer'),
  ('Upvrepo_peera1', 'Peer A', 'pk-peera'),
  ('Upvrepo_block1', 'Blocked', 'pk-block'),
  ('Upvrepo_author', 'Author', 'pk-author')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('Bpvrepo00001', 'Upvrepo_author', 'Visibility beacon', 'd', 0)
ON CONFLICT (id) DO UPDATE SET
  user_id = EXCLUDED.user_id,
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  status = EXCLUDED.status
''');

  await writer.execute(r'''
INSERT INTO public.vote_user (subject, object, amount)
VALUES ('Upvrepo_viewer', 'Upvrepo_peera1', 1)
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

  await writer.execute(
    "SELECT mr_put_edge('Upvrepo_peera1', 'Upvrepo_viewer', 0.75::double precision, ''::text, 0)",
  );
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
}

class _NoopCapabilityEvidence extends Fake implements CapabilityEvidencePort {}

class _NoopAttentionDispatch extends Fake implements AttentionDispatchPort {
  @override
  Future<void> record(AttentionDispatchIntent intent) async {}
}

class _NoopNotificationContext extends Fake
    implements BeaconRoomNotificationContextPort {}

class _NoopUsers extends Fake implements UserRepositoryPort {
  @override
  Future<UserEntity> getById(String id) async => UserEntity(id: id);
}

class _StaticBeaconRepo extends Fake implements BeaconRepositoryPort {
  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async {
    return BeaconEntity(
      id: beaconId,
      title: 'Visibility beacon',
      author: const UserEntity(id: _authorId),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }
}

