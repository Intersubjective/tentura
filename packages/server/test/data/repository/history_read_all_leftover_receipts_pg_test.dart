@Tags(['pg', 'repo-files'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';

/// History's unread count covers every uncleared optional receipt, read or
/// not. «Read all» must leave none of them behind: receipts an older Read all
/// marked seen but never cleared, demoted ones, any forward state, any kind.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HISTORY_READ_ALL_LEFTOVER_TEST_DB',
    defaultNamePrefix: 'tentura_test_hist_readall_left',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('History «Read all» with receipts left over from earlier', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository feedRepo;
    late AttentionAckRepository ack;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      feedRepo = AttentionRepository(database);
      ack = AttentionAckRepository(database);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_help_offer,
  public.beacon_participant,
  public.inbox_item,
  public.attention_request_state,
  public.beacon_forward_edge,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_viewer, _author]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    Future<void> seedForwardedRequest(String id, {int status = 0}) async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @author, 'Forwarded', 'A Request forwarded to the viewer', 0)
'''),
        parameters: {'id': id, 'author': _author},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (@e, @b, @author, @viewer, CAST(@at AS timestamptz), NULL)
'''),
        parameters: {
          'e': 'FE$id',
          'b': id,
          'author': _author,
          'viewer': _viewer,
          'at': _old,
        },
      );
      final insertInbox = Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@u, @b, @s, 1, CAST(@at AS timestamptz), '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = @s
''');
      final insertParams = {'u': _viewer, 'b': id, 's': status, 'at': _old};
      if (status == 3 || status == 4) {
        // Tombstone statuses (closed before response) are only written by the
        // beacon trigger; open the same session switch it uses (m0193).
        await writer.runTx((tx) async {
          await tx.execute(
            "SELECT set_config('tentura.allow_inbox_tombstone_transition', "
            "'1', true)",
          );
          await tx.execute(insertInbox, parameters: insertParams);
        });
      } else {
        await writer.execute(insertInbox, parameters: insertParams);
      }
    }

    Future<void> seedAuthoredRequest(String id) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @viewer, 'Mine', 'Authored by the viewer', 0)
'''),
      parameters: {'id': id, 'viewer': _viewer},
    );

    Future<void> seedPost(String id, {required bool expired}) async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, published_at,
   expires_at, expiry_warning_eligible, is_discoverable)
VALUES (@id, @author, '', '', 1, 0, now() - interval '3 days',
  CASE WHEN @expired THEN now() - interval '1 minute'
       ELSE now() + interval '2 hours' END, false, false)
'''),
        parameters: {'id': id, 'author': _author, 'expired': expired},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@pid, @id, @viewer, 6, 0, 3)
'''),
        parameters: {'pid': 'P$id', 'id': id, 'viewer': _viewer},
      );
    }

    /// An old receipt, as an earlier build left it: [seen] sets `seen_at`,
    /// `cleared_at` stays NULL.
    Future<void> seedReceipt(
      String id, {
      String? beaconId,
      String key = 'request_status_changed',
      bool seen = false,
      String placement = 'primary',
      bool requiresAction = false,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  beacon_id, actor_user_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy, placement, requires_action,
  attention_thread_key
) VALUES (
  @id, @viewer, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedup, CAST(@at AS timestamptz),
  CASE WHEN @seen THEN CAST(@at AS timestamptz) END,
  @b, @author, @source,
  CASE WHEN @b::text IS NULL THEN 'profile' ELSE 'beacon' END,
  @key, '{"eventType":"fixture","personal":true}'::jsonb,
  'standard', CASE WHEN @b::text IS NULL THEN 'profile'
       ELSE 'beacon_content' END,
  @placement, @requires,
  CASE WHEN @requires THEN 'v1|' || @id || '|a|b' END
)
'''),
      parameters: {
        'id': id,
        'viewer': _viewer,
        'author': _author,
        'dedup': 'dedup-$id',
        'source': 'source-$id',
        'at': _old,
        'seen': seen,
        'b': beaconId,
        'key': beaconId == null ? 'mutual_connection_formed' : key,
        'placement': placement,
        'requires': requiresAction,
      },
    );

    Future<AttentionFeed> history({
      AttentionRepository? repo,
      AttentionFeedView view = AttentionFeedView.all,
    }) => (repo ?? feedRepo).attentionFeed(accountId: _viewer, view: view);

    Future<int> unread() async => (await history()).summary.unreadTotal;

    Future<int> unreadAfterReload() async {
      final fresh = openDisposablePgDatabase(target);
      try {
        return (await history(
          repo: AttentionRepository(fresh),
        )).summary.unreadTotal;
      } finally {
        await fresh.close();
      }
    }

    Future<List<Object?>> row(String id) async {
      final r = await writer.execute(
        Sql.named(
          'SELECT seen_at, cleared_at FROM public.notification_outbox '
          'WHERE id = @id',
        ),
        parameters: {'id': id},
      );
      return r.single.toList();
    }

    /// Every receipt id the Unread view lists, following the cursor.
    Future<List<String>> unreadViewIds(AttentionRepository repo) async {
      final ids = <String>[];
      AttentionCursor? cursor;
      var pages = 0;
      do {
        final feed = await repo.attentionFeed(
          accountId: _viewer,
          view: AttentionFeedView.unread,
          cursor: cursor,
        );
        ids.addAll(feed.page.items.map((i) => i.id));
        cursor = feed.page.nextCursor;
        pages++;
      } while (cursor != null && pages < 10);
      return ids;
    }

    /// Read all, then: [mustBeCleared] rows are seen and cleared, the count
    /// is 0 and the Unread view (every page) lists nothing, on this
    /// connection and on a new one.
    Future<void> expectReadAllLeavesNone(
      String reason, {
      List<String> mustBeCleared = const ['Nold'],
    }) async {
      await ack.markAllSeen(_viewer);
      for (final id in mustBeCleared) {
        final r = await row(id);
        expect(r[0], isNotNull, reason: '$reason: $id seen');
        expect(r[1], isNotNull, reason: '$reason: $id cleared');
      }
      expect(await unread(), 0, reason: '$reason: unread after Read all');
      expect(await unreadViewIds(feedRepo), isEmpty, reason: '$reason: view');
      final fresh = openDisposablePgDatabase(target);
      try {
        final repo = AttentionRepository(fresh);
        expect(
          (await history(repo: repo)).summary.unreadTotal,
          0,
          reason: '$reason: after reload',
        );
        expect(
          await unreadViewIds(repo),
          isEmpty,
          reason: '$reason: Unread view after reload',
        );
      } finally {
        await fresh.close();
      }
    }

    group('an old forwarded-Request receipt', () {
      test('seen earlier but never cleared is cleared by Read all', () async {
        await seedForwardedRequest(_fwd, status: 1);
        await seedReceipt(
          'Nold',
          beaconId: _fwd,
          key: 'relay_received',
          seen: true,
        );
        expect(await unread(), 1, reason: 'precondition');

        await expectReadAllLeavesNone('followed, seen');
        expect((await row('Nold'))[1], isNotNull);
        expect(
          (await history(view: AttentionFeedView.unread)).page.items,
          isEmpty,
        );
      });

      test('never read and never opened is marked seen and cleared', () async {
        await seedForwardedRequest(_fwd, status: 1);
        await seedReceipt('Nold', beaconId: _fwd, key: 'relay_received');

        await expectReadAllLeavesNone('followed, unseen');
      });

      for (final seen in [false, true]) {
        test('demoted to the timeline (seen: $seen) reads as seen', () async {
          await seedForwardedRequest(_fwd, status: 1);
          await seedReceipt(
            'Nold',
            beaconId: _fwd,
            key: 'relay_received',
            seen: seen,
            placement: 'timeline_only',
          );

          await expectReadAllLeavesNone('timeline_only');
          final item = (await history()).page.items.firstWhere(
            (i) => i.id == 'Nold',
          );
          expect(item.seenAt, isNotNull);
        });
      }

      for (final (name, status, offer) in [
        ('pending', 0, false),
        ('watching', 1, false),
        ('notInterested', 2, false),
        ('closedBeforeResponse', 3, false),
        ('helping', 1, true),
      ]) {
        test('in the $name forward state, seen earlier, is cleared', () async {
          await seedForwardedRequest(_fwd, status: status);
          if (offer) {
            await writer.execute(
              Sql.named('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, message, status, created_at, updated_at)
VALUES (@b, @u, 'offer', 0, now(), now())
'''),
              parameters: {'b': _fwd, 'u': _viewer},
            );
          }
          await seedReceipt(
            'Nold',
            beaconId: _fwd,
            key: 'relay_received',
            seen: true,
          );
          expect(await unread(), 1, reason: 'precondition');

          await expectReadAllLeavesNone(name);
        });
      }

      test(
        'on a Request closed before the viewer answered is cleared',
        () async {
          await seedForwardedRequest(_fwd);
          await writer.execute(
            Sql.named('UPDATE public.beacon SET status = 1 WHERE id = @b'),
            parameters: {'b': _fwd},
          );
          await seedReceipt(
            'Nold',
            beaconId: _fwd,
            key: 'relay_received',
            seen: true,
          );
          expect(await unread(), 1, reason: 'precondition');

          await expectReadAllLeavesNone('closed before response');
        },
      );
    });

    group('every receipt kind shown in History', () {
      for (final seen in [false, true]) {
        test(
          '(seen: $seen) ends read and uncounted after one Read all',
          () async {
            await seedForwardedRequest(_fwd);
            await seedAuthoredRequest(_mine);
            await seedPost(_post, expired: false);
            await seedPost(_oldPost, expired: true);
            await seedReceipt('Nexp', beaconId: _oldPost, seen: seen);
            await seedReceipt('Nfwd', beaconId: _fwd, seen: seen);
            await seedReceipt('Nmine', beaconId: _mine, seen: seen);
            await seedReceipt('Nnone', seen: seen);
            await seedReceipt('Npost', beaconId: _post, seen: seen);
            expect(await unread(), 4, reason: 'precondition');

            await ack.markAllSeen(_viewer);

            for (final id in ['Nfwd', 'Nmine', 'Nnone', 'Npost']) {
              final r = await row(id);
              expect(r[0], isNotNull, reason: '$id seen');
              expect(r[1], isNotNull, reason: '$id cleared');
            }
            expect((await row('Nexp'))[0], isNotNull, reason: 'expired seen');
            expect(await unread(), 0);
            expect(await unreadAfterReload(), 0);
            expect(
              (await history(view: AttentionFeedView.unread)).page.items,
              isEmpty,
            );
          },
        );
      }
    });

    test('a live obligation is read but stays owed, next to a leftover '
        'optional receipt that is cleared', () async {
      await seedForwardedRequest(_fwd, status: 1);
      await seedAuthoredRequest(_mine);
      await seedReceipt(
        'Nold',
        beaconId: _fwd,
        key: 'relay_received',
        seen: true,
      );
      await seedReceipt('Nduty', beaconId: _mine, requiresAction: true);

      await ack.markAllSeen(_viewer);

      final duty = await row('Nduty');
      expect(duty[0], isNotNull, reason: 'obligation read');
      expect(duty[1], isNull, reason: 'obligation not cleared');
      expect((await row('Nold'))[1], isNotNull, reason: 'optional cleared');
      expect(await unread(), 1);
      expect(await unreadAfterReload(), 1, reason: 'after reload');
    });

    test(
      'a receipt on an expired Post is marked seen and never counted',
      () async {
        await seedPost(_post, expired: true);
        await seedReceipt('Nexp', beaconId: _post);
        expect(await unread(), 0, reason: 'not counted before');

        await ack.markAllSeen(_viewer);

        expect((await row('Nexp'))[0], isNotNull);
        expect(await unread(), 0);
      },
    );

    test('a second Read all changes nothing', () async {
      await seedForwardedRequest(_fwd, status: 1);
      await seedReceipt(
        'Nold',
        beaconId: _fwd,
        key: 'relay_received',
        seen: true,
      );
      await ack.markAllSeen(_viewer);
      final first = await row('Nold');
      expect(first[1], isNotNull);

      await ack.markAllSeen(_viewer);

      expect(await row('Nold'), first);
      expect(await unread(), 0);
    });

    test('a history longer than one page ends with nothing unread', () async {
      await seedForwardedRequest(_fwd, status: 1);
      await seedReceipt(
        'Nold',
        beaconId: _fwd,
        key: 'relay_received',
        seen: true,
      );
      for (var i = 0; i < 59; i++) {
        await seedReceipt(
          'Nbulk${i.toString().padLeft(3, '0')}',
          seen: i.isEven,
        );
      }
      expect(await unread(), 60, reason: 'precondition');

      await expectReadAllLeavesNone(
        '60 items',
        mustBeCleared: [
          'Nold',
          for (var i = 0; i < 59; i++) 'Nbulk${i.toString().padLeft(3, '0')}',
        ],
      );
    });
  }, skip: skipReason);
}

const _viewer = 'Uleftovrv1';
const _author = 'Uleftovrau1';
const _fwd = 'Bleftovrfwd';
const _mine = 'Bleftovrmine';
const _post = 'Bleftovrpost';
const _oldPost = 'Bleftovrpast';
const _old = '2026-11-13T10:00:00Z';
