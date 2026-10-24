@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/post_expiry_warning_sweep_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_user_block_repository.dart';

const _author = 'Upostexpwrn01';
const _member = 'Upostexpwrn02';
const _post = 'Bpostexpwrn01';

/// The author-only notice sent 3 hours before a Post expires, for Posts whose
/// lifetime at publication was longer than 3 hours.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_EXPIRY_WARNING_SWEEP_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_expiry_warn',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late PostExpiryWarningSweepCase sweep;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    sweep = _buildSweep(database, target.databaseEnv);
  });

  setUp(() => _resetFixture(writer));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<List<String>> recipients() async {
    final rows = await writer.execute('''
SELECT outbox.account_id
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = 'postExpiringSoon'
ORDER BY outbox.account_id
''');
    return [for (final r in rows) r[0]! as String];
  }

  Future<int> occurrences() async =>
      (await writer.execute(
            'SELECT count(*) FROM public.attention_occurrence '
            "WHERE event_type = 'postExpiringSoon'",
          )).single[0]!
          as int;

  Future<int> memberRows() async {
    final rows = await writer.execute('''
SELECT
  (SELECT count(*) FROM public.attention_occurrence_recipient
    WHERE account_id = '$_member')
  + (SELECT count(*) FROM public.notification_outbox
    WHERE account_id = '$_member')
  + (SELECT count(*) FROM public.attention_channel_delivery
    WHERE account_id = '$_member')
''');
    return (rows.single[0]! as num).toInt();
  }

  Future<List<AttentionReceipt>> memberFeedItems() async {
    final query = AttentionRepository(database);
    final items = <AttentionReceipt>[];
    for (final surface in AttentionSurface.values) {
      final feed = await query.attentionFeed(
        accountId: _member,
        view: AttentionFeedView.all,
        surface: surface,
      );
      for (final item in feed.page.items) {
        items
          ..add(item)
          ..addAll(item.eventsPreview);
      }
    }
    return items;
  }

  Future<void> expireIn(Duration left) => writer.execute('''
UPDATE public.beacon
SET expires_at = now() + interval '${left.inMinutes} minutes'
WHERE id = '$_post'
''');

  group('post expiry warning sweep', () {
    test('an eligible Post expiring in 2 hours warns only the author, '
        'once', () async {
      await _insertPost(writer, left: const Duration(hours: 2));

      await sweep.runDue();

      expect(await recipients(), [_author]);
      expect(await occurrences(), 1);
      expect(await memberRows(), 0, reason: 'members get no receipt or job');
      expect(await memberFeedItems(), isEmpty);

      await sweep.runDue();

      expect(await recipients(), [_author]);
      expect(await occurrences(), 1);
    });

    test('a Post published with a 3 hour lifetime is never warned', () async {
      // Published an hour ago with a 3 hour lifetime: 2 hours left, but the
      // lifetime never exceeded the warning window.
      await _insertPost(
        writer,
        left: const Duration(hours: 2),
        eligible: false,
        publishedAgo: const Duration(hours: 1),
      );

      await sweep.runDue();

      expect(await occurrences(), 0);
    });

    test('a closed Post is not warned', () async {
      await _insertPost(writer, left: const Duration(hours: 2), status: 6);

      await sweep.runDue();

      expect(await occurrences(), 0);
    });

    test('a Post expiring in 4 hours is not warned yet', () async {
      await _insertPost(writer, left: const Duration(hours: 4));

      await sweep.runDue();

      expect(await occurrences(), 0);
    });

    test('a Post that already expired is not warned', () async {
      await _insertPost(writer, left: const Duration(hours: 2));
      await writer.execute('''
UPDATE public.beacon SET expires_at = now() - interval '1 minute'
WHERE id = '$_post'
''');

      await sweep.runDue();

      expect(await occurrences(), 0);
    });

    test('an eligible 72 hour Post shortened to 2 hours left is warned on '
        'the next run, and a second shortening does not warn again', () async {
      await _insertPost(writer, left: const Duration(hours: 72));
      await sweep.runDue();
      expect(await occurrences(), 0);

      await expireIn(const Duration(hours: 2));
      await sweep.runDue();
      expect(await occurrences(), 1);

      await expireIn(const Duration(hours: 1));
      await sweep.runDue();
      expect(await occurrences(), 1);
    });

    test('the author receipt is a Post notice with the Post id for '
        'navigation', () async {
      await _insertPost(writer, left: const Duration(hours: 2));

      await sweep.runDue();

      final outbox = await writer.execute('''
SELECT outbox.beacon_id, outbox.presentation_key,
  outbox.presentation_payload->>'eventType'
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = 'postExpiringSoon' AND outbox.account_id = '$_author'
''');
      expect(outbox, hasLength(1));
      expect(outbox.single[0], _post, reason: 'push navigates to the Post');
      expect(outbox.single[1], 'post_expiring_soon');
      expect(outbox.single[2], 'postExpiringSoon');

      final meta = await writer.execute('''
SELECT occ.source_event_key, outbox.category, rcp.collapse_key
FROM public.attention_occurrence AS occ
JOIN public.notification_outbox AS outbox ON outbox.occurrence_id = occ.id
JOIN public.attention_occurrence_recipient AS rcp
  ON rcp.occurrence_id = occ.id AND rcp.account_id = outbox.account_id
WHERE occ.event_type = 'postExpiringSoon' AND outbox.account_id = '$_author'
''');
      expect(meta, hasLength(1));
      expect(meta.single[0], 'post_expiring:$_post');
      expect(meta.single[1], 'coordination', reason: 'the Post category');
      expect(
        meta.single[2],
        AttentionCollapseKey.none('post_expiring:$_post'),
        reason: 'a warning never collapses into another notification',
      );

      final push = await writer.execute('''
SELECT job.payload->>'beaconId', job.payload->>'kind',
  job.payload->>'beaconKind'
FROM public.attention_channel_delivery AS job
JOIN public.attention_occurrence AS occ ON occ.id = job.occurrence_id
WHERE occ.event_type = 'postExpiringSoon' AND job.account_id = '$_author'
''');
      expect(push, hasLength(1));
      expect(push.single[0], _post, reason: 'push payload carries the Post id');
      expect(push.single[1], 'postExpiringSoon');
      expect(push.single[2], 'post');

      // The receipt as the client reads it, on whichever surface holds it.
      final query = AttentionRepository(database);
      final receipts = <AttentionReceipt>[];
      for (final surface in AttentionSurface.values) {
        final feed = await query.attentionFeed(
          accountId: _author,
          view: AttentionFeedView.all,
          surface: surface,
        );
        for (final item in feed.page.items) {
          receipts
            ..add(item)
            ..addAll(item.eventsPreview);
        }
      }
      final warning = receipts.where(
        (r) => r.presentationKey == 'post_expiring_soon',
      );
      expect(warning, isNotEmpty);
      for (final r in warning) {
        expect(r.beaconId, _post);
        expect(r.beaconKind, BeaconKind.post);
        expect(
          (jsonDecode(jsonEncode(r.presentationPayload))
              as Map<String, dynamic>)['eventType'],
          'postExpiringSoon',
        );
      }
      expect(await memberFeedItems(), isEmpty);
    });
  });
}

PostExpiryWarningSweepCase _buildSweep(TenturaDb db, Env env) {
  final logger = Logger('PostExpiryWarningSweepPgTest');
  final room = BeaconRoomRepository(db);
  final attention = TransactionalAttentionCase(
    MutatingUnitOfWork(db),
    AttentionDispatchRepository(db, logger),
  );
  final intents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      room,
      db,
      HelpOfferRepository(db),
      CommitmentRepository(db),
    ),
    UserRepository(
      env,
      db,
      _NoopInviteGenealogyRepository(),
      InviteSeedPromptRepositoryMock(),
    ),
    BeaconAccessRepository(db),
    FakeUserBlockRepository(),
  );
  return PostExpiryWarningSweepCase(BeaconRepository(db), intents, attention);
}

Future<void> _insertPost(
  Connection writer, {
  required Duration left,
  bool eligible = true,
  int status = 0,
  Duration publishedAgo = Duration.zero,
}) async {
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at, expiry_warning_eligible)
VALUES (
  '$_post', '$_author', '', '', $status, 1, 1, false,
  now() - interval '${publishedAgo.inMinutes} minutes',
  now() + interval '${left.inMinutes} minutes', $eligible
)
''');
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Ppostexpwrn01', '$_post', '$_member', 6, 0, 0)
''');
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_author, _member]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
''');
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
