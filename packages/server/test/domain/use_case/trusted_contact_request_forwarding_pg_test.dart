@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_people_seen_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_requests_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_admission_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_forward_graph_case.dart';
import 'package:tentura_server/domain/use_case/beacon_involvement_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/forward_inbound_query_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Utrustauthor';
const _viewer = 'Utrustviewer';
const _recipient = 'Utrustrecv';
const _outsider = 'Utrustoutside';
const _request = 'Btrustrequest';
const _privateRequest = 'Btrustprivate';
const _sourcePost = 'Btrustpost';
const _bud = 'Btrustbud';
const _postMember = 'Utrustpostmember';
const _forwardSender = 'Utrustsender';
const _offerer = 'Utrustofferer';
const _roomMember = 'Utrustroom';
const _steward = 'Utruststeward';

final _involvementDenied = isA<UnauthorizedException>()
    .having((e) => e.code.codeNumber, 'code', 1102)
    .having(
      (e) => e.description,
      'description',
      'Viewer cannot read request involvement',
    );

// Coverage: the forward picker loads beaconInvolvement; inbound sources,
// coordination offers and the forward graph share the same access boundary.
// Each read checks outsiders and non-discoverable Requests before the trusted
// reader. The involvement scenario then sends and checks persisted delivery.
// Siblings: roles = mutual contact without involvement / outsider; state =
// published open Request / non-discoverable Request. Existing forward suites
// own author/member/Post/terminal-state policy. Input, width, locale and network
// presentation are n/a for server reads; freshness is a new read of real PG data.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRUSTED_CONTACT_FORWARD_TEST_DB',
    defaultNamePrefix: 'tentura_test_trusted_forward',
  );
  final skip = await pgSkipReason(target);
  late DisposablePgWriterSession session;
  late TenturaDb db;
  late _Harness h;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    db = openDisposablePgDatabase(target);
    h = _Harness(db, target.databaseEnv);
  });
  setUp(() async => _seed(session.writer));
  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  group('Forwarding Requests discovered through mutual trust', () {
    // Run the denial assertions first so a red positive scenario still proves
    // the access boundary, without depending on the guard's implementation.
    Future<void> verifyAudience(
      Future<Object?> Function(String, String) read,
    ) async {
      final field = ConstellationFieldRequestsRepository(db);
      final rows = await field.discoverableRequestsByIds(
        viewerId: _viewer,
        beaconIds: {_request, _privateRequest},
        filters: ConstellationFieldMembershipFilters.defaults,
      );
      expect(rows.map((row) => row.id), unorderedEquals([_request]));
      expect(
        await h.access.canReadContent(beaconId: _request, viewerId: _viewer),
        isTrue,
      );
      expect(
        await h.access.canReadContent(beaconId: _request, viewerId: _outsider),
        isFalse,
      );
      expect(
        await h.access.canReadContent(
          beaconId: _privateRequest,
          viewerId: _viewer,
        ),
        isFalse,
      );
      final involvement = await session.writer.execute('''
SELECT
  (SELECT count(*) FROM public.beacon_forward_edge WHERE beacon_id = '$_request'),
  (SELECT count(*) FROM public.beacon_help_offer WHERE beacon_id = '$_request'),
  (SELECT count(*) FROM public.beacon_participant WHERE beacon_id = '$_request' AND user_id = '$_viewer'),
  (SELECT count(*) FROM public.inbox_item WHERE beacon_id = '$_request' AND user_id = '$_viewer')
''');
      expect(involvement.single.toList(), [0, 0, 0, 0]);
      for (final (request, viewer) in [
        (_request, _outsider),
        (_privateRequest, _viewer),
      ]) {
        await expectLater(
          read(request, viewer),
          throwsA(isA<UnauthorizedException>()),
        );
        await expectLater(
          h.forward.forward(
            senderId: viewer,
            beaconId: request,
            recipientIds: [_recipient],
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      }
    }

    test(
      'a trusted reader loads recipient involvement and delivers a forward',
      () async {
        await verifyAudience(
          (id, viewer) =>
              h.involvement.asMap(beaconId: id, currentUserId: viewer),
        );
        final result = await h.involvement.asMap(
          beaconId: _request,
          currentUserId: _viewer,
        );
        expect(result.forwardedToIds, isEmpty);
        expect(result.helpOfferedIds, isEmpty);
        expect(result.myForwardedRecipients, isEmpty);
        final delivery = await h.forward.forward(
          senderId: _viewer,
          beaconId: _request,
          recipientIds: [_recipient],
          sharedNote: 'Can you help?',
        );
        expect(delivery.deliveredRecipientIds, [_recipient]);
        final edges = await ForwardEdgeRepository(db).fetchByBeaconId(_request);
        expect(edges, hasLength(1));
        expect(edges.single.senderId, _viewer);
        expect(edges.single.recipientId, _recipient);
        expect(edges.single.note, 'Can you help?');
        final inbox = await session.writer.execute(
          "SELECT user_id FROM public.inbox_item WHERE beacon_id = '$_request' AND user_id = '$_recipient'",
        );
        expect(inbox, hasLength(1));
      },
    );

    test(
      'a trusted reader can load inbound sources without having received a forward',
      () async {
        await verifyAudience(
          (id, viewer) =>
              h.inbound.listEligible(beaconId: id, viewerId: viewer),
        );
        expect(
          await h.inbound.listEligible(beaconId: _request, viewerId: _viewer),
          isEmpty,
        );
      },
    );

    test('a trusted reader can load the Request forward graph', () async {
      await verifyAudience(
        (id, viewer) => h.graph.asMap(beaconId: id, currentUserId: viewer),
      );
      final graph = await h.graph.asMap(
        beaconId: _request,
        currentUserId: _viewer,
      );
      expect(graph.beaconId, _request);
      expect(graph.authorId, _author);
      expect(graph.edges, isEmpty);
    });

    test(
      'a trusted reader can load help offers for forwarding context',
      () async {
        await verifyAudience(
          (id, viewer) => h.coordination.helpOffersWithCoordination(
            beaconId: id,
            viewerId: viewer,
          ),
        );
        expect(
          await h.coordination.helpOffersWithCoordination(
            beaconId: _request,
            viewerId: _viewer,
          ),
          isEmpty,
        );
      },
    );
  }, skip: skip);

  group('Request forwarding availability', () {
    test(
      'discoverability lets a trusted contact read involvement and deliver a forward',
      () async {
        final writer = session.writer;
        await _setRequestState(writer, _request, discoverable: false);
        await expectLater(
          h.involvement.asMap(beaconId: _request, currentUserId: _viewer),
          throwsA(_involvementDenied),
        );
        final hidden = await _viewerCanForward(writer, _request, _viewer);

        await _setRequestState(writer, _request, discoverable: true);
        final available = await _viewerCanForward(writer, _request, _viewer);
        final closedPolicy = await _viewerCanForward(
          writer,
          _request,
          _viewer,
          closedPolicy: true,
        );
        final involvement = await h.involvement.asMap(
          beaconId: _request,
          currentUserId: _viewer,
        );
        expect(involvement.myForwardedRecipients, isEmpty);
        final delivery = await h.forward.forward(
          senderId: _viewer,
          beaconId: _request,
          recipientIds: [_recipient],
        );
        expect(delivery.deliveredRecipientIds, [_recipient]);
        final edges = await ForwardEdgeRepository(db).fetchByBeaconId(_request);
        expect(edges.map((e) => (e.senderId, e.recipientId, e.cancelledAt)), [
          (_viewer, _recipient, null),
        ]);

        expect(
          {
            'discoverable, open policy': available,
            'non-discoverable, open policy': hidden,
            'discoverable, closed policy': closedPolicy,
          },
          {
            'discoverable, open policy': true,
            'non-discoverable, open policy': false,
            'discoverable, closed policy': false,
          },
        );
      },
    );

    test('an uninvited Post member cannot read or forward the Request', () async {
      final writer = session.writer;
      await _seedPostBudAudience(writer);
      final flags = <String, bool>{};
      for (final discoverable in [true, false]) {
        await _setRequestState(writer, _bud, discoverable: discoverable);
        expect(
          await h.access.canReadContent(beaconId: _bud, viewerId: _postMember),
          isFalse,
          reason: 'Post membership with discoverable=$discoverable',
        );
        await expectLater(
          h.involvement.asMap(beaconId: _bud, currentUserId: _postMember),
          throwsA(_involvementDenied),
        );
        flags['Post member, discoverable=$discoverable'] =
            await _viewerCanForward(writer, _bud, _postMember);
      }
      flags['outsider on a discoverable Request'] = await _viewerCanForward(
        writer,
        _request,
        _outsider,
      );
      expect(flags, {
        'Post member, discoverable=true': false,
        'Post member, discoverable=false': false,
        'outsider on a discoverable Request': false,
      });
    });

    test(
      'Request forwarding requires involvement and direct access to the Request',
      () async {
        final writer = session.writer;
        await _seedPostBudAudience(writer);
        await writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$_bud', '$_forwardSender', '$_recipient'),
       ('$_sourcePost', '$_author', '$_recipient')
''');
        await writer.execute('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, status)
VALUES ('$_bud', '$_offerer', 0)
''');
        await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$_bud', '$_roomMember', 2, 3)
''');
        await writer.execute('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES ('$_bud', '$_steward')
''');

        // A closed forward policy is legal on Posts only. All of these
        // viewers can read involvement, but only the author may forward.
        for (final viewer in [_author, _recipient, _postMember]) {
          expect(
            await h.access.canReadInvolvement(
              beaconId: _sourcePost,
              viewerId: viewer,
            ),
            isTrue,
            reason: viewer,
          );
          expect(
            await _viewerCanForward(writer, _sourcePost, viewer),
            viewer == _author,
            reason: 'closed policy for $viewer',
          );
        }

        const audience = {
          'author': _author,
          'forward recipient': _recipient,
          'forward sender': _forwardSender,
          'active help offerer': _offerer,
          'room member': _roomMember,
          'steward': _steward,
          'trusted contact': _viewer,
          'Post member': _postMember,
          'outsider': _outsider,
        };
        final mismatches = <String>[];
        for (final status in [0, 7, 8, 6]) {
          for (final discoverable in [true, false]) {
            await _setRequestState(
              writer,
              _bud,
              status: status,
              discoverable: discoverable,
            );
            for (final MapEntry(key: role, value: viewer) in audience.entries) {
              final state =
                  '$role, status=$status, '
                  'discoverable=$discoverable';
              final canReadInvolvement = await h.access.canReadInvolvement(
                beaconId: _bud,
                viewerId: viewer,
              );
              if (status == 0 ||
                  (viewer == _author && const {7, 8}.contains(status))) {
                // Pin the actual standing of the fixture, independently of
                // the flag. This also protects existing participant access.
                final readsInvolvement = switch (viewer) {
                  _postMember || _outsider || _forwardSender => false,
                  _viewer => discoverable,
                  _ => true,
                };
                expect(canReadInvolvement, readsInvolvement, reason: state);
              }
              for (final closedPolicy in [false, true]) {
                final expected =
                    canReadInvolvement &&
                    const {0, 7, 8}.contains(status) &&
                    (!closedPolicy || viewer == _author);
                final actual = await _viewerCanForward(
                  writer,
                  _bud,
                  viewer,
                  closedPolicy: closedPolicy,
                );
                if (actual != expected) {
                  final policy = closedPolicy ? 'closed' : 'open';
                  mismatches.add(
                    '$state, policy=$policy: expected $expected, got $actual',
                  );
                }
              }
            }
          }
        }
        expect(mismatches, isEmpty);
      },
    );

    group('schema upgrade', () {
      final upgradeTarget = DisposablePgTarget.fromNamedEnvironment(
        envVarName: 'TENTURA_REQUEST_FORWARD_FLAG_UPGRADE_TEST_DB',
        defaultNamePrefix: 'tentura_test_request_forward_upgrade',
      );

      late DisposablePgWriterSession upgrade;

      setUpAll(() async {
        upgrade = await setUpDisposablePgWriter(
          target: upgradeTarget,
          lastInclusiveVersion: '0317',
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: upgrade);
      });

      test(
        'upgrading corrects the flag for an existing non-discoverable Request',
        () async {
          final writer = upgrade.writer;
          await _seed(writer);
          expect(
            await _viewerCanForward(writer, _privateRequest, _viewer),
            isTrue,
          );

          await migrateDbSchema(writer);

          final signature = await writer.execute('''
SELECT proargnames, pg_get_function_result(oid)
FROM pg_proc
WHERE oid =
  'public.beacon_get_viewer_can_forward(public.beacon, json)'::regprocedure
''');
          expect(signature.single.toList(), [
            ['beacon_row', 'hasura_session'],
            'boolean',
          ]);
          expect(
            await _viewerCanForward(writer, _privateRequest, _viewer),
            isFalse,
            reason:
                'the migrated flag must hide forwarding for this trusted contact',
          );
          expect(migrationsForTesting.map((m) => m.version), contains('0318'));
        },
      );
    });
  }, skip: skip);
}

Future<bool> _viewerCanForward(
  Connection writer,
  String beaconId,
  String viewer, {
  bool closedPolicy = false,
}) async {
  // The table constraint permits closed policy on Posts only. Exercise the
  // function's closed-policy Request input with a typed composite, preserving
  // the stored Request and all involvement data it uses.
  final rows = await writer.execute(
    Sql.named('''
SELECT public.beacon_get_viewer_can_forward(
  CASE WHEN @closed_policy::boolean
       THEN jsonb_populate_record(b, '{"forward_policy": 0}'::jsonb)
       ELSE b
  END,
  json_build_object('x-hasura-user-id', @viewer::text)
)
FROM public.beacon b WHERE b.id = @beacon
'''),
    parameters: {
      'beacon': beaconId,
      'viewer': viewer,
      'closed_policy': closedPolicy,
    },
  );
  return rows.single.single! as bool;
}

Future<void> _setRequestState(
  Connection writer,
  String beaconId, {
  required bool discoverable,
  int status = 0,
}) => writer.execute(
  Sql.named('''
UPDATE public.beacon
SET is_discoverable = @discoverable, status = @status
WHERE id = @beacon
'''),
  parameters: {
    'beacon': beaconId,
    'discoverable': discoverable,
    'status': status,
  },
);

Future<void> _seedPostBudAudience(Connection writer) async {
  for (final (i, id) in [
    _postMember,
    _forwardSender,
    _offerer,
    _roomMember,
    _steward,
  ].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('bud-forward', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  is_discoverable, forward_policy, parent_beacon_id, published_at)
VALUES ('$_sourcePost', '$_author', '', '', 0, 1, false, 0, NULL, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$_sourcePost', '$_postMember', 2, 3),
       ('$_sourcePost', '$_forwardSender', 2, 3)
''');
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  is_discoverable, forward_policy, parent_beacon_id, published_at)
VALUES ('$_bud', '$_author', 'Budded Request', '', 0, 0, true, 1, '$_sourcePost', now())
''');
}

Future<void> _seed(Connection writer) async {
  await writer.execute('TRUNCATE public.beacon, public."user" CASCADE');
  for (final (i, id) in [_author, _viewer, _recipient, _outsider].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('trusted-forward', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount) VALUES
  ('$_viewer', '$_author', 1), ('$_author', '$_viewer', 1),
  ('$_viewer', '$_recipient', 1), ('$_recipient', '$_viewer', 1)
''');
  for (final (id, discoverable) in [
    (_request, true),
    (_privateRequest, false),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  is_discoverable, forward_policy, published_at)
VALUES (@id, @author, 'Need a hand', 'Moving day', 0, 0, @discoverable, 1, now())
'''),
      parameters: {'id': id, 'author': _author, 'discoverable': discoverable},
    );
  }
}

final class _Harness {
  _Harness(TenturaDb db, Env env) {
    final logger = Logger('TrustedContactRequestForwardingPgTest');
    access = BeaconAccessRepository(db);
    final beacons = BeaconRepository(db);
    final edges = ForwardEdgeRepository(db);
    final offers = HelpOfferRepository(db);
    final room = BeaconRoomRepository(db);
    final inbox = InboxRepository(db);
    final commitments = CommitmentRepository(db);
    final blocks = UserBlockRepository(env, db);
    final users = UserRepository(
      env,
      db,
      _UnusedGenealogy(),
      InviteSeedPromptRepositoryMock(),
    );
    final attention = TransactionalAttentionCase(
      MutatingUnitOfWork(db),
      AttentionDispatchRepository(db, logger),
    );
    final intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(room, db, offers, commitments),
      users,
      access,
      blocks,
    );
    involvement = BeaconInvolvementCase(
      edges,
      offers,
      HelpOfferAdmissionRepository(db),
      inbox,
      access,
      env: env,
      logger: logger,
    );
    inbound = ForwardInboundQueryCase(
      beacons,
      edges,
      users,
      access,
      env: env,
      logger: logger,
    );
    graph = BeaconForwardGraphCase(
      beacons,
      edges,
      offers,
      access,
      room,
      env: env,
      logger: logger,
    );
    coordination = CoordinationCase(
      beacons,
      offers,
      CoordinationRepository(
        db,
        DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
        VoteUserFriendshipLookup(db),
        room,
        BeaconPeopleSeenRepository(db),
      ),
      room,
      blocks,
      commitments,
      CommitmentQueryCase(commitments, offers, env: env, logger: logger),
      BeaconHierarchyRepository(db),
      guard: access,
      attentionIntents: intents,
      attention: attention,
      attentionSystemSettlement: AttentionSystemSettlementRepository(db),
      env: env,
      logger: logger,
    );
    forward = ForwardCase(
      edges,
      ForwardAttributionRepository(db),
      offers,
      inbox,
      CapabilityEvidenceRepository(db),
      beacons,
      blocks,
      PersonVisibilityRepository(db),
      access,
      attention: attention,
      attentionIntents: intents,
      env: env,
      logger: logger,
    );
  }
  late final BeaconAccessRepository access;
  late final BeaconInvolvementCase involvement;
  late final ForwardInboundQueryCase inbound;
  late final BeaconForwardGraphCase graph;
  late final CoordinationCase coordination;
  late final ForwardCase forward;
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}
