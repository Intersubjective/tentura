@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/use_case/closure_draft_reminder_sweep_case.dart';
import 'package:tentura_server/domain/use_case/stale_request_reminder_sweep_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// A17: closure receipts (Arch §9) and the two hourly reminder sweeps.
///
/// Collaborators come from the production DI container (dev environment
/// against the disposable database), so no constructor shape is assumed:
/// - `ClosureReceiptsPort` must be the real outbox-writing binding (not
///   `NoopClosureReceipts`) and join the ambient transaction;
/// - `ClosureDraftReminderSweepCase` / `StaleRequestReminderSweepCase` must be
///   registered and expose `runDue({DateTime? now})`.

const _author = 'Uclntauth001';
const _m1 = 'Uclntmemb001';
const _m2 = 'Uclntmemb002';
const _m3 = 'Uclntmemb003';
const _removed = 'Uclntremov001';
const _beacon = 'Bclntbeac001';
const _users = [_author, _m1, _m2, _m3, _removed];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CLOSURE_NOTIFICATIONS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_closure_notifications',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late Connection writer;
  late MutatingUnitOfWorkPort uow;
  late ClosureReceiptsPort receipts;
  late ClosureDraftReminderSweepCase draftSweep;
  late StaleRequestReminderSweepCase staleSweep;

  Future<void> sql(String s) => writer.execute(s);

  Future<List<List<Object?>>> rows(String s) async =>
      (await writer.execute(s)).map((r) => r.toList()).toList();

  Future<void> seedEpoch({
    int epoch = 1,
    int status = 0,
    String closesAt = "now() + interval '23 hours 30 minutes'",
  }) => sql('''
INSERT INTO public.beacon_closure (beacon_id, epoch, status, opened_at, closes_at)
VALUES ('$_beacon', $epoch, $status, now() - interval '6 days', $closesAt)
''');

  Future<void> member(String id, {int epoch = 1, int? departure}) => sql('''
INSERT INTO public.beacon_closure_member
  (beacon_id, epoch, user_id, departure, active_at_open)
VALUES ('$_beacon', $epoch, '$id', ${departure ?? 'NULL'}, ${departure == null})
''');

  Future<void> support(
    String voter,
    Iterable<String> targets, {
    required int version,
  }) async {
    for (final t in targets) {
      await sql('''
INSERT INTO public.beacon_closure_support (beacon_id, voter_id, target_id, version)
VALUES ('$_beacon', '$voter', '$t', $version)
''');
    }
  }

  Future<void> clearDraft(String voter) => sql('''
DELETE FROM public.beacon_closure_support
WHERE beacon_id = '$_beacon' AND voter_id = '$voter' AND version = 0
''');

  Future<void> commit(String voter) => sql('''
INSERT INTO public.beacon_closure_commit (beacon_id, voter_id, committed_at)
VALUES ('$_beacon', '$voter', now())
''');

  Future<List<List<Object?>>> outbox(String keyPrefix) => rows('''
SELECT source_event_key, account_id, access_policy, presentation_key,
       presentation_payload::text
FROM public.notification_outbox
WHERE source_event_key LIKE '$keyPrefix%' ORDER BY source_event_key
''');

  Future<List<String>> keys(String keyPrefix) async => [
    for (final r in await outbox(keyPrefix)) r[0]! as String,
  ];

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      final db = target.databaseEnv;
      await configureDependencies(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse('http://127.0.0.1:2080'),
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          publicOrigin: 'http://127.0.0.1:2080',
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      await getIt.allReady(ignorePendingAsyncCreation: true);
      uow = getIt<MutatingUnitOfWorkPort>();
      receipts = getIt<ClosureReceiptsPort>();
      draftSweep = getIt<ClosureDraftReminderSweepCase>();
      staleSweep = getIt<StaleRequestReminderSweepCase>();
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await sql('''
TRUNCATE public.beacon_closure_result, public.beacon_closure_member,
  public.beacon_closure, public.beacon_closure_support,
  public.beacon_closure_commit, public.notification_outbox,
  public.user_block, public.beacon_help_offer,
  public.beacon_activity_event, public.beacon_commitment_event,
  public.beacon_room_message
CASCADE
''');
      await sql("DELETE FROM public.beacon WHERE id LIKE 'Bclnt%'");
      for (var i = 0; i < _users.length; i++) {
        await sql('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('${_users[i]}', '${_users[i]}', '${pgTestPublicKey('clnt', i + 1)}')
ON CONFLICT (id) DO NOTHING
''');
      }
      await sql('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_beacon', '$_author', 'closure notifications', '',
        ${BeaconStatus.reviewOpen.smallintValue}, now())
''');
    });
  }

  group('closure receipts', () {
    Future<void> openWithMembers() async {
      await seedEpoch();
      await member(_m1);
      await member(_m2);
      await member(_m3);
      await member(_removed, departure: 2);
    }

    test('the DI binding is the real implementation, not the no-op', () {
      expect(receipts, isNot(isA<NoopClosureReceipts>()));
    }, skip: skipReason);

    test('opened writes one keyed row per recipient', () async {
      await openWithMembers();
      await uow.run<void>(
        actorUserId: _author,
        action: () => receipts.opened(_beacon, 1),
      );

      final got = await keys('closure_opened:');
      expect(
        got,
        containsAll([
          'closure_opened:$_beacon:1:$_author',
          'closure_opened:$_beacon:1:$_m1',
          'closure_opened:$_beacon:1:$_m2',
          'closure_opened:$_beacon:1:$_m3',
        ]),
      );
      expect(got.toSet(), hasLength(got.length), reason: 'no duplicate keys');

      final byAccount = {
        for (final r in await outbox('closure_opened:')) r[1]: r,
      };
      expect(byAccount[_author]![2], 'beacon_content');
      expect(byAccount[_m1]![2], 'beacon_content');
    }, skip: skipReason);

    test(
      'a removed member gets a recipient_safe row with the bookmark key',
      () async {
        await openWithMembers();
        await uow.run<void>(
          actorUserId: _author,
          action: () => receipts.opened(_beacon, 1),
        );

        final row = (await outbox(
          'closure_opened:$_beacon:1:$_removed',
        )).single;
        expect(row[2], 'recipient_safe');
        expect(row[3], 'closure_opened_bookmark_only');
      },
      skip: skipReason,
    );

    test('finalized carries codes only and is idempotent', () async {
      await openWithMembers();
      await sql('''
INSERT INTO public.beacon_closure_result
  (beacon_id, epoch, user_id, outcome, band, draft_flag, helped)
VALUES ('$_beacon', 1, '$_m1', 1, 1, 2, 0.5)
''');
      for (var i = 0; i < 2; i++) {
        await uow.run<void>(
          actorUserId: _author,
          action: () => receipts.finalized(_beacon, 1),
        );
      }

      final all = await outbox('closure_finalized:');
      final mine = all.where((r) => r[1] == _m1).single;
      expect(mine[0], 'closure_finalized:$_beacon:1:$_m1');
      expect(mine[2], 'beacon_content');
      expect(
        all.where((r) => r[1] == _removed).single[3],
        'closure_finalized',
        reason: 'removed member: recipient_safe presentation key',
      );
      expect(
        all.map((r) => r[0]).toSet(),
        hasLength(all.length),
        reason: 'a second finalize attempt writes nothing new',
      );
      final payload = jsonDecode(mine[4]! as String) as Map<String, dynamic>;
      expect(payload['outcome'], 1);
      expect(payload['band'], 1);
      expect(payload['draftFlag'], 2);
      const allowed = {
        'eventType',
        'beaconId',
        'epoch',
        'outcome',
        'band',
        'draftFlag',
      };
      expect(allowed, containsAll(payload.keys), reason: 'codes only');
      for (final k in ['outcome', 'band', 'draftFlag']) {
        expect(payload[k], isA<int>(), reason: '$k is a numeric code');
      }
    }, skip: skipReason);

    test('a second finalize attempt leaves the row count unchanged', () async {
      await openWithMembers();
      await uow.run<void>(
        actorUserId: _author,
        action: () => receipts.finalized(_beacon, 1),
      );
      final before = (await outbox('closure_finalized:')).length;
      expect(before, greaterThan(0));
      await uow.run<void>(
        actorUserId: _author,
        action: () => receipts.finalized(_beacon, 1),
      );
      expect((await outbox('closure_finalized:')).length, before);
    }, skip: skipReason);

    test(
      'cancelled mirrors the keying and the removed-member policy',
      () async {
        await openWithMembers();
        await uow.run<void>(
          actorUserId: _author,
          action: () => receipts.cancelled(_beacon, 1),
        );
        final got = await keys('closure_cancelled:');
        expect(got, contains('closure_cancelled:$_beacon:1:$_m1'));
        final removedRow = (await outbox(
          'closure_cancelled:$_beacon:1:$_removed',
        )).single;
        expect(removedRow[2], 'recipient_safe');
        expect(removedRow[3], 'closure_cancelled');
      },
      skip: skipReason,
    );

    test(
      'a blocked member gets recipient_safe rows for every receipt',
      () async {
        await openWithMembers();
        await sql('''
INSERT INTO public.beacon_closure_result
  (beacon_id, epoch, user_id, outcome, band, draft_flag, helped)
VALUES ('$_beacon', 1, '$_m3', 1, 2, 0, 0.5)
''');
        await sql('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_author', '$_m3', '$_author')
''');
        await uow.run<void>(
          actorUserId: _author,
          action: () async {
            await receipts.opened(_beacon, 1);
            await receipts.finalized(_beacon, 1);
            await receipts.cancelled(_beacon, 1);
          },
        );
        for (final (type, key) in const [
          ('opened', 'closure_opened_bookmark_only'),
          ('finalized', 'closure_finalized'),
          ('cancelled', 'closure_cancelled'),
        ]) {
          final row = (await outbox('closure_$type:$_beacon:1:$_m3')).single;
          expect(row[2], 'recipient_safe', reason: type);
          expect(row[3], key, reason: type);
        }
        expect(
          (await outbox('closure_opened:$_beacon:1:$_m1')).single[2],
          'beacon_content',
          reason: 'an unblocked member still reads the request',
        );
      },
      skip: skipReason,
    );

    test('receipts roll back with the transaction', () async {
      await openWithMembers();
      await expectLater(
        uow.run<void>(
          actorUserId: _author,
          action: () async {
            await receipts.opened(_beacon, 1);
            await receipts.finalized(_beacon, 1);
            await receipts.cancelled(_beacon, 1);
            // The test's own `writer` is another connection and cannot see
            // uncommitted rows; the app database joins the transaction.
            final inside = await getIt<TenturaDb>()
                .customSelect(
                  'SELECT count(*) AS n FROM public.notification_outbox '
                  "WHERE source_event_key LIKE 'closure_%'",
                )
                .getSingle();
            expect(
              inside.read<int>('n'),
              greaterThan(0),
              reason: 'rows are visible inside the transaction',
            );
            throw StateError('rollback');
          },
        ),
        throwsStateError,
      );
      expect(await keys('closure_'), isEmpty);
    }, skip: skipReason);
  });

  group('draft reminder sweep', () {
    Future<List<String>> run({DateTime? now}) async {
      await draftSweep.runDue(now: now ?? DateTime.now().toUtc());
      return keys('closure_draft_reminder:');
    }

    setUp(() async {
      if (skipReason != false) return;
      await seedEpoch();
      for (final m in [_m1, _m2, _m3]) {
        await member(m);
      }
    });

    test('untouched voters get nothing', () async {
      expect(await run(), isEmpty);
    }, skip: skipReason);

    test('a committed Skip (empty sets) gets nothing', () async {
      await commit(_m1);
      expect(await run(), isEmpty);
    }, skip: skipReason);

    test('a committed Done without later edits gets nothing', () async {
      await support(_m1, [_m2], version: 0);
      await support(_m1, [_m2], version: 1);
      await commit(_m1);
      expect(await run(), isEmpty);
    }, skip: skipReason);

    test('equal multi-target sets after Done get nothing', () async {
      await support(_m1, [_m2, _m3], version: 0);
      await support(_m1, [_m2, _m3], version: 1);
      await commit(_m1);
      expect(await run(), isEmpty);
    }, skip: skipReason);

    test('a draft without a commit gets one reminder', () async {
      await support(_m1, [_m2], version: 0);
      expect(await run(), ['closure_draft_reminder:$_beacon:1:$_m1']);
      expect((await outbox('closure_draft_reminder:')).single[1], _m1);
    }, skip: skipReason);

    test(
      'an edit after Done (different target set) gets one reminder',
      () async {
        await support(_m1, [_m2], version: 0);
        await support(_m1, [_m2], version: 1);
        await commit(_m1);
        await clearDraft(_m1);
        await support(_m1, [_m3], version: 0);
        expect(await outbox('closure_draft_reminder:'), isEmpty);
        expect(await run(), ['closure_draft_reminder:$_beacon:1:$_m1']);
        expect((await outbox('closure_draft_reminder:')).single[1], _m1);
      },
      skip: skipReason,
    );

    test('adding a target to the draft after Done gets one reminder', () async {
      await support(_m1, [_m2], version: 0);
      await support(_m1, [_m2], version: 1);
      await commit(_m1);
      await support(_m1, [_m3], version: 0);
      expect(await run(), ['closure_draft_reminder:$_beacon:1:$_m1']);
    }, skip: skipReason);

    test(
      'clearing the draft after a committed Done gets one reminder',
      () async {
        await support(_m1, [_m2], version: 0);
        await support(_m1, [_m2], version: 1);
        await commit(_m1);
        await clearDraft(_m1);
        expect(await run(), ['closure_draft_reminder:$_beacon:1:$_m1']);
      },
      skip: skipReason,
    );

    test('each eligible voter gets exactly one row', () async {
      await support(_m1, [_m2], version: 0);
      await support(_m3, [_m2], version: 0);
      await commit(_m2);
      expect(await run(), [
        'closure_draft_reminder:$_beacon:1:$_m1',
        'closure_draft_reminder:$_beacon:1:$_m3',
      ]);
    }, skip: skipReason);

    test('fires once per epoch however often the sweep runs', () async {
      await support(_m1, [_m2], version: 0);
      await run();
      expect(await run(), hasLength(1));
    }, skip: skipReason);

    test('only epochs closing 23-24 h ahead are swept', () async {
      await sql('DELETE FROM public.beacon_closure');
      await seedEpoch(closesAt: "now() + interval '30 hours'");
      await member(_m1);
      await support(_m1, [_m2], version: 0);
      expect(await run(), isEmpty, reason: 'more than 24 h away');

      await sql(
        "UPDATE public.beacon_closure SET closes_at = now() + interval '22 hours'",
      );
      expect(await run(), isEmpty, reason: 'less than 23 h away');
    }, skip: skipReason);

    test('only evaluating epochs (status 0) are swept', () async {
      await sql('UPDATE public.beacon_closure SET status = 1');
      await support(_m1, [_m2], version: 0);
      expect(await run(), isEmpty);
    }, skip: skipReason);

    test('a removed member is not a voter', () async {
      await member(_removed, departure: 2);
      await support(_removed, [_m2], version: 0);
      expect(await run(), isEmpty);
    }, skip: skipReason);
  });

  group('stale request reminder sweep', () {
    final now = DateTime.utc(2026, 10, 1, 12);
    const recent = "'2026-09-28T00:00:00Z'";
    const old = "'2026-09-01T00:00:00Z'";

    Future<List<String>> run(DateTime at) async {
      await staleSweep.runDue(now: at);
      return keys('stale_request:');
    }

    Future<void> makeOpen({String endAt = 'NULL', String active = 'now()'}) =>
        sql('''
UPDATE public.beacon SET status = ${BeaconStatus.open.smallintValue},
  end_at = $endAt, created_at = $active, status_changed_at = NULL
WHERE id = '$_beacon'
''');

    Future<void> setStatus(BeaconStatus st) => sql(
      'UPDATE public.beacon SET status = ${st.smallintValue} '
      "WHERE id = '$_beacon'",
    );

    test('an open request past its end fires for the author', () async {
      await makeOpen(endAt: "'2026-09-01T00:00:00Z'");
      expect(await run(now), ['stale_request:$_beacon:2026-W40']);
      expect((await outbox('stale_request:')).single[1], _author);
    }, skip: skipReason);

    test('fires once per ISO week', () async {
      await makeOpen(endAt: "'2026-09-01T00:00:00Z'");
      await run(now);
      expect(await run(now.add(const Duration(days: 2))), hasLength(1));
      expect(await run(now.add(const Duration(days: 7))), [
        'stale_request:$_beacon:2026-W40',
        'stale_request:$_beacon:2026-W41',
      ]);
    }, skip: skipReason);

    test('no activity for 14 days makes an open request stale', () async {
      await makeOpen(active: old);
      expect(await run(now), ['stale_request:$_beacon:2026-W40']);
    }, skip: skipReason);

    test('recent room activity keeps a request fresh', () async {
      await makeOpen(active: old);
      await sql('''
INSERT INTO public.beacon_room_message (beacon_id, author_id, body, created_at)
VALUES ('$_beacon', '$_author', 'hi', '2026-09-28T00:00:00Z')
''');
      expect(await run(now), isEmpty);
    }, skip: skipReason);

    test('recent activity-event keeps a request fresh', () async {
      await makeOpen(active: old);
      await sql('''
INSERT INTO public.beacon_activity_event (beacon_id, visibility, type, created_at)
VALUES ('$_beacon', 0, 0, $recent)
''');
      expect(await run(now), isEmpty);
    }, skip: skipReason);

    test('a recently updated help offer keeps a request fresh', () async {
      await makeOpen(active: old);
      await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, status, created_at, updated_at)
VALUES ('$_beacon', '$_m1', 0, '2026-09-01T00:00:00Z', $recent)
''');
      expect(await run(now), isEmpty);
    }, skip: skipReason);

    test('a recent commitment event keeps a request fresh', () async {
      await makeOpen(active: old);
      await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, status, created_at, updated_at)
VALUES ('$_beacon', '$_m1', 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z')
''');
      await sql('''
INSERT INTO public.beacon_commitment_event (id, beacon_id, user_id, kind, created_at)
VALUES ('Ecommit00001', '$_beacon', '$_m1', 1, $recent)
''');
      expect(await run(now), isEmpty);
    }, skip: skipReason);

    test('a recent status change keeps a request fresh', () async {
      await makeOpen(active: old);
      await sql(
        "UPDATE public.beacon SET status_changed_at = $recent WHERE id = '$_beacon'",
      );
      expect(await run(now), isEmpty);
    }, skip: skipReason);

    test('old activity in every source is still stale', () async {
      await makeOpen(active: old);
      await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, status, created_at, updated_at)
VALUES ('$_beacon', '$_m1', 0, '2026-09-02T00:00:00Z', '2026-09-02T00:00:00Z')
''');
      expect(await run(now), ['stale_request:$_beacon:2026-W40']);
    }, skip: skipReason);

    test('a future end with recent activity is not stale', () async {
      await makeOpen(endAt: "'2026-12-01T00:00:00Z'", active: recent);
      expect(await run(now), isEmpty);
    }, skip: skipReason);

    test('needsMoreHelp and enoughHelp count as the open family', () async {
      for (final st in [BeaconStatus.needsMoreHelp, BeaconStatus.enoughHelp]) {
        await sql('DELETE FROM public.notification_outbox');
        await makeOpen(endAt: "'2026-09-01T00:00:00Z'");
        await setStatus(st);
        expect(await run(now), hasLength(1), reason: st.name);
      }
    }, skip: skipReason);

    test(
      'closed, cancelled, deleted, draft and review requests are skipped',
      () async {
        for (final st in [
          BeaconStatus.closed,
          BeaconStatus.cancelled,
          BeaconStatus.deleted,
          BeaconStatus.draft,
          BeaconStatus.reviewOpen,
        ]) {
          await makeOpen(endAt: "'2026-09-01T00:00:00Z'");
          await setStatus(st);
          expect(await run(now), isEmpty, reason: st.name);
        }
      },
      skip: skipReason,
    );

    test('an overdue end fires even with recent activity', () async {
      await makeOpen(endAt: "'2026-09-20T00:00:00Z'", active: recent);
      await sql('''
INSERT INTO public.beacon_room_message (beacon_id, author_id, body, created_at)
VALUES ('$_beacon', '$_author', 'hi', '2026-09-30T00:00:00Z')
''');
      expect(await run(now), ['stale_request:$_beacon:2026-W40']);
    }, skip: skipReason);

    test('a future end does not stop 14 days of silence', () async {
      await makeOpen(endAt: "'2026-12-01T00:00:00Z'", active: old);
      expect(await run(now), ['stale_request:$_beacon:2026-W40']);
    }, skip: skipReason);

    test('the 14 day threshold: 13 days fresh, 15 days stale', () async {
      await makeOpen(active: "'2026-09-18T12:00:00Z'");
      expect(await run(now), isEmpty, reason: '13 days of silence');
      await sql(
        "UPDATE public.beacon SET created_at = '2026-09-16T12:00:00Z' WHERE id = '$_beacon'",
      );
      expect(await run(now), hasLength(1), reason: '15 days of silence');
    }, skip: skipReason);

    test('no helpers are required and only the author is notified', () async {
      await makeOpen(endAt: "'2026-09-01T00:00:00Z'");
      await seedEpoch();
      await member(_m1);
      await run(now);
      final got = await outbox('stale_request:');
      expect(got, hasLength(1));
      expect(got.single[1], _author);
      expect(got.single[2], 'beacon_content');
    }, skip: skipReason);
  });
}
