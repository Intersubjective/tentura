@Tags(['pg'])
library;

import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/post_bud_repository.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// `PostBudPort.insertInvite` records, as the invitee's Post arrival route,
/// the inbound Post edge that was active when the child was published (the
/// bud-time provenance contract), whatever happened to the Post's edges
/// afterwards.
///
/// The Post `_post` (author `_author`) was published 20 days ago and the child
/// `_child` was budded 5 days ago. `_invitee` arrived through `Fa1` (sender
/// `_firstSender`) before budding.
const _author = 'Uarr0author01';
const _firstSender = 'Uarr0first0001';
const _laterSender = 'Uarr0later0001';
const _invitee = 'Uarr0invitee01';
const _users = [_author, _firstSender, _laterSender, _invitee];

const _post = 'Barr0post0001';
const _child = 'Barr0child001';

const _firstEdge = 'Fa1';
const _laterEdge = 'Fa2';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_INVITE_ARRIVAL_ROUTE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_bud_arrival',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('arrival route recorded on an author invite', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late PostBudRepository repository;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = openDisposablePgDatabase(target);
      repository = PostBudRepository(db, _UnusedVisibility());
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    Future<void> sql(String s) => writer.execute(s);

    Future<void> edge(
      String id,
      String sender,
      String age, {
      String? cancelledAt,
    }) => sql('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, batch_id, created_at, cancelled_at)
VALUES ('$id', '$_post', '$sender', '$_invitee', 'X$id',
        now() - interval '$age',
        ${cancelledAt == null ? 'NULL' : "now() - interval '$cancelledAt'"})
''');

    Future<void> seed() async {
      await sql('''
TRUNCATE TABLE
  public.beacon_author_invite,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
      for (var i = 0; i < _users.length; i++) {
        await sql('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('${_users[i]}', '${_users[i]}', '${pgTestPublicKey('arr', i + 1)}')
''');
      }
      await sql('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false,
        now() - interval '20 days')
''');
      await sql('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, parent_beacon_id,
   is_discoverable, published_at)
VALUES ('$_child', '$_author', 'Move the piano', '', 0, '$_post', false,
        now() - interval '5 days')
''');
    }

    Future<String?> invite() async {
      final inviteId = await repository.insertInvite(
        beaconId: _child,
        inviterId: _author,
        inviteeId: _invitee,
        sourcePostId: _post,
        forwardEdgeId: null,
        warm: true,
      );
      expect(inviteId, isNotNull);
      final rows = await writer.execute(
        'SELECT arrival_post_edge_id FROM public.beacon_author_invite '
        "WHERE id = '$inviteId'",
      );
      return rows.single[0] as String?;
    }

    setUp(seed);

    test(
      'a Post edge received before budding is the recorded arrival route',
      () async {
        await edge(_firstEdge, _firstSender, '10 days');
        expect(await invite(), _firstEdge);
      },
    );

    test('a Post edge received after budding does not replace the '
        'bud-time arrival route', () async {
      await edge(_firstEdge, _firstSender, '10 days');
      await edge(_laterEdge, _laterSender, '1 day');
      expect(await invite(), _firstEdge);
    });

    test('a bud-time arrival route cancelled after budding is still '
        'recorded', () async {
      await edge(_firstEdge, _firstSender, '10 days', cancelledAt: '2 days');
      expect(await invite(), _firstEdge);
    });

    test('a bud-time arrival route cancelled after budding is preferred over '
        'a later active edge', () async {
      await edge(_firstEdge, _firstSender, '10 days', cancelledAt: '2 days');
      await edge(_laterEdge, _laterSender, '1 day');
      expect(await invite(), _firstEdge);
    });
  });
}

final class _UnusedVisibility extends Fake
    implements PersonVisibilityRepositoryPort {}
