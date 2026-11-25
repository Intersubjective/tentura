@Tags(['pg', 'repo-files'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    show PhantomsCompanion;
import 'package:tentura_server/data/repository/owner_graph_unit_of_work.dart';
import 'package:tentura_server/utils/id.dart';

import '../../support/disposable_pg_target.dart';

const _beforePhantomStorage = '0332';
const _owner = 'Uphantomowner';
const _otherViewer = 'Uphantomview1';
const _peer = 'Uphantompeer1';
const _otherPeer = 'Uphantompeer2';
const _tables = {
  'phantom',
  'phantom_merge',
  'phantom_merge_job',
  'phantom_link_hint_dismissal',
  'person_field_first_seen_init',
};

Future<Result> _sql(
  Session session,
  String statement,
  Map<String, Object?> parameters,
) => session.execute(Sql.named(statement), parameters: parameters);

Future<String> _insertUser(Session session, {String? id}) async {
  final userId = id ?? generateId('U');
  await _sql(
    session,
    '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
''',
    {'id': userId, 'key': 'pk-$userId'},
  );
  return userId;
}

Future<String> _insertInvitation(Session session) async {
  final rows = await _sql(
    session,
    '''
INSERT INTO public.invitation (user_id) VALUES (@issuer) RETURNING id
''',
    {'issuer': _peer},
  );
  return rows.single.single! as String;
}

Future<Result> _insertPhantom(
  Session session,
  String id,
  String owner, {
  String name = 'Anna',
  String? emoji,
}) => _sql(
  session,
  '''
INSERT INTO public.phantom
  (id, owner_id, display_name, emoji, created_at, updated_at, revision)
VALUES (@id, @owner, @name, @emoji, now(), now(), 0)
RETURNING id, owner_id, display_name, emoji
''',
  {'id': id, 'owner': owner, 'name': name, 'emoji': emoji},
);

Future<String> _insertMerge(
  Session session, {
  required String phantom,
  required String owner,
  required String user,
}) async {
  final rows = await _sql(
    session,
    '''
INSERT INTO public.phantom_merge
  (id, phantom_id, owner_id, user_id, origin, created_at, undo)
VALUES (@id, @phantom, @owner, @user, 2, now(), '{}'::jsonb)
RETURNING id
''',
    {'id': generateId('PM'), 'phantom': phantom, 'owner': owner, 'user': user},
  );
  return rows.single.single! as String;
}

Future<Result> _queueJob(
  Session session, {
  required String phantom,
  required String owner,
  required String user,
  required String invitation,
  bool ignoreConflict = false,
}) => _sql(
  session,
  '''
INSERT INTO public.phantom_merge_job
  (id, phantom_id, owner_id, user_id, origin, invitation_id, state,
   attempts, next_attempt_at, created_at)
VALUES (@id, @phantom, @owner, @user, 2, @invitation, 'queued', 0, now(), now())
${ignoreConflict ? 'ON CONFLICT DO NOTHING' : ''}
RETURNING invitation_id
''',
  {
    'id': generateId('PJ'),
    'phantom': phantom,
    'owner': owner,
    'user': user,
    'invitation': invitation,
  },
);

Future<Result> _dismissHint(Session session, String phantom, String user) =>
    _sql(
      session,
      '''
INSERT INTO public.phantom_link_hint_dismissal (phantom_id, user_id)
VALUES (@phantom, @user)
RETURNING user_id
''',
      {'phantom': phantom, 'user': user},
    );

Future<T> _withoutScope<T>(
  Connection writer,
  Future<T> Function(TxSession) action,
) => writer.runTx((tx) async {
  await tx.execute("SET LOCAL tentura.owner_scope_enforce = 'on'");
  return action(tx);
});

Future<void> _eraseUser(Connection writer, String id) async {
  final rows = await _withoutScope(
    writer,
    (tx) => _sql(
      tx,
      'DELETE FROM public."user" WHERE id = @id RETURNING id',
      {'id': id},
    ),
  );
  expect(rows.single.single, id);
}

Matcher _sqlState(String code) => throwsA(
  isA<ServerException>().having((error) => error.code, 'SQLSTATE', code),
);

Matcher _scopeRequired(String table) => throwsA(
  isA<ServerException>().having(
    (error) => error.message,
    'message',
    contains('Owner scope required for INSERT on public.$table'),
  ),
);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PHANTOM_STORAGE_TEST_DB',
    defaultNamePrefix: 'tentura_test_phantom_storage',
  );
  final skipReason = await pgSkipReason(target);

  group('Storage for people not on Tentura yet', () {
    late Connection writer;

    Future<String> createPhantom(String owner) async {
      final id = generateId('PH');
      final rows = await withPgOwnerScopes(
        writer,
        [owner],
        (tx) => _insertPhantom(tx, id, owner),
      );
      expect(rows.single.take(2), [id, owner]);
      return id;
    }

    Future<Result> phantomLinks(String phantom) => _sql(
      writer,
      '''
SELECT merged_user_id, current_merge_id, merged_at IS NOT NULL
FROM public.phantom WHERE id = @phantom
''',
      {'phantom': phantom},
    );

    Future<Result> mergesForPhantom(String phantom) => _sql(
      writer,
      '''
SELECT id FROM public.phantom_merge WHERE phantom_id = @phantom
''',
      {'phantom': phantom},
    );

    Future<Result> dismissalsForPhantom(String phantom) => _sql(
      writer,
      '''
SELECT user_id FROM public.phantom_link_hint_dismissal WHERE phantom_id = @phantom
''',
      {'phantom': phantom},
    );

    Future<Result> jobsForPhantom(String phantom) => _sql(
      writer,
      '''
SELECT invitation_id, state FROM public.phantom_merge_job
WHERE phantom_id = @phantom ORDER BY state
''',
      {'phantom': phantom},
    );

    setUpAll(() async {
      final session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: _beforePhantomStorage,
      );
      writer = session.writer;
      addTearDown(() => tearDownDisposablePgWriter(session: session));

      for (final id in [_owner, _otherViewer, _peer, _otherPeer]) {
        await _insertUser(writer, id: id);
      }
      await withPgOwnerScopes(writer, [_owner, _otherViewer], (tx) async {
        await _sql(
          tx,
          '''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id)
VALUES (@owner, @peer), (@owner, @otherPeer), (@otherViewer, @peer)
''',
          {
            'owner': _owner,
            'otherViewer': _otherViewer,
            'peer': _peer,
            'otherPeer': _otherPeer,
          },
        );
      });
      await migrateDbSchema(writer);
    });

    test(
      'saving new people generates distinct 14-character PH identifiers',
      () async {
        final db = openDisposablePgDatabase(target);
        addTearDown(db.close);
        final tables = db.allTables.where(
          (table) => table.actualTableName == 'phantom',
        );
        expect(
          tables,
          hasLength(1),
          reason: 'Drift must expose person storage',
        );

        const names = ['Klara', 'Miriam'];
        await OwnerGraphUnitOfWork(db).run({_owner}, _owner, (_) async {
          for (final name in names) {
            await db
                .into(db.phantoms)
                .insertReturning(
                  PhantomsCompanion.insert(ownerId: _owner, displayName: name),
                );
          }
        });
        final rows = await _sql(
          writer,
          '''
SELECT id, display_name FROM public.phantom
WHERE owner_id = @owner AND display_name IN (@first, @second)
''',
          {'owner': _owner, 'first': names.first, 'second': names.last},
        );
        expect(rows.map((row) => row[1]), unorderedEquals(names));
        final storedIds = rows.map((row) => row[0]);
        expect(storedIds.toSet(), hasLength(2));
        expect(storedIds, everyElement(matches(r'^PH[0-9a-f]{12}$')));
      },
    );

    test(
      'enforces the 3–32 character name limit after trimming spaces',
      () async {
        Future<Result> insert(String name) => withPgOwnerScopes(
          writer,
          [_owner],
          (tx) => _insertPhantom(tx, generateId('PH'), _owner, name: name),
        );

        for (final name in ['abc', '  ${'é' * 32}  ']) {
          final savedName = (await insert(name)).single[2]! as String;
          expect(savedName.trim(), name.trim());
        }
        for (final name in ['  ab  ', 'a' * 33]) {
          await expectLater(
            insert(name),
            _sqlState('23514'),
            reason: 'Name: $name',
          );
        }
      },
    );

    test(
      'stores up to eight emoji characters and permits a missing emoji',
      () async {
        Future<Result> insert(String? emoji) => withPgOwnerScopes(
          writer,
          [_owner],
          (tx) => _insertPhantom(
            tx,
            generateId('PH'),
            _owner,
            name: 'Emoji probe',
            emoji: emoji,
          ),
        );

        for (final emoji in [null, '🙂', '🙂' * 8]) {
          expect((await insert(emoji)).single[3], emoji);
        }
        await expectLater(insert('🙂' * 9), _sqlState('23514'));
      },
    );

    test('queues one job per person until the queued job completes', () async {
      final phantom = await createPhantom(_owner);
      final first = await _insertInvitation(writer);
      final second = await _insertInvitation(writer);

      Future<Result> queue(String invitation) => _queueJob(
        writer,
        phantom: phantom,
        owner: _owner,
        user: _otherPeer,
        invitation: invitation,
        ignoreConflict: true,
      );

      expect((await queue(first)).single.single, first);
      expect(await queue(second), isEmpty);
      expect((await jobsForPhantom(phantom)).single.toList(), [
        first,
        'queued',
      ]);

      final completed = await _sql(
        writer,
        '''
UPDATE public.phantom_merge_job SET state = 'done', done_at = now()
WHERE invitation_id = @invitation RETURNING state
''',
        {'invitation': first},
      );
      expect(completed.single.single, 'done');
      expect((await queue(second)).single.single, second);
      expect(
        (await jobsForPhantom(phantom)).map((row) => row.toList()),
        [
          [first, 'done'],
          [second, 'queued'],
        ],
      );
    });

    test('an invitation cannot create jobs for two people', () async {
      final first = await createPhantom(_owner);
      final second = await createPhantom(_owner);
      final invitation = await _insertInvitation(writer);
      Future<Result> queue(String phantom) => _queueJob(
        writer,
        phantom: phantom,
        owner: _owner,
        user: _otherPeer,
        invitation: invitation,
      );

      expect((await queue(first)).single.single, invitation);
      await expectLater(queue(second), _sqlState('23505'));
      expect(await jobsForPhantom(second), isEmpty);
    });

    test('merge jobs may reference a person who was already removed', () async {
      final phantom = generateId('PH');
      expect(await phantomLinks(phantom), isEmpty);
      final invitation = await _insertInvitation(writer);
      await _queueJob(
        writer,
        phantom: phantom,
        owner: _owner,
        user: _otherPeer,
        invitation: invitation,
      );
      expect(
        (await jobsForPhantom(phantom)).single.toList(),
        [invitation, 'queued'],
      );
    });

    test(
      'removing a person deletes merge history and dismissals but preserves queued jobs',
      () async {
        final phantom = await createPhantom(_owner);
        final merge = await withPgOwnerScopes(
          writer,
          [_owner],
          (tx) =>
              _insertMerge(tx, phantom: phantom, owner: _owner, user: _peer),
        );
        await _dismissHint(writer, phantom, _peer);
        final invitation = await _insertInvitation(writer);
        await _queueJob(
          writer,
          phantom: phantom,
          owner: _owner,
          user: _otherPeer,
          invitation: invitation,
        );
        expect((await mergesForPhantom(phantom)).single.single, merge);
        expect((await dismissalsForPhantom(phantom)).single.single, _peer);

        final deleted = await _sql(
          writer,
          '''
DELETE FROM public.phantom WHERE id = @phantom RETURNING id
''',
          {'phantom': phantom},
        );
        expect(deleted.single.single, phantom);
        expect(await phantomLinks(phantom), isEmpty);
        expect(await mergesForPhantom(phantom), isEmpty);
        expect(await dismissalsForPhantom(phantom), isEmpty);
        expect(
          (await jobsForPhantom(phantom)).single.toList(),
          [invitation, 'queued'],
        );
      },
    );

    test(
      'erasing an owner removes their people and the associated rows',
      () async {
        final owner = await _insertUser(writer);
        final phantoms = [
          await createPhantom(owner),
          await createPhantom(owner),
        ];
        final invitation = await _insertInvitation(writer);
        final phantom = phantoms.first;
        final merge = await withPgOwnerScopes(
          writer,
          [owner],
          (tx) => _insertMerge(tx, phantom: phantom, owner: owner, user: _peer),
        );
        await _dismissHint(writer, phantom, _peer);
        await _queueJob(
          writer,
          phantom: phantom,
          owner: owner,
          user: _otherPeer,
          invitation: invitation,
        );
        expect((await mergesForPhantom(phantom)).single.single, merge);
        expect((await dismissalsForPhantom(phantom)).single.single, _peer);
        expect((await jobsForPhantom(phantom)).single[0], invitation);

        await _eraseUser(writer, owner);

        for (final id in phantoms) {
          expect(await phantomLinks(id), isEmpty);
        }
        expect(await mergesForPhantom(phantom), isEmpty);
        expect(await dismissalsForPhantom(phantom), isEmpty);
        expect(await jobsForPhantom(phantom), isEmpty);
      },
    );

    test(
      'erasing a merged account preserves the person as an orphan and removes their merge history',
      () async {
        final phantom = await createPhantom(_owner);
        final user = await _insertUser(writer);
        final merge = await withPgOwnerScopes(writer, [_owner], (tx) async {
          final merge = await _insertMerge(
            tx,
            phantom: phantom,
            owner: _owner,
            user: user,
          );
          await _sql(
            tx,
            '''
UPDATE public.phantom
SET merged_user_id = @user, current_merge_id = @merge,
    merged_at = now(), merge_origin = 2
WHERE id = @phantom
''',
            {'user': user, 'merge': merge, 'phantom': phantom},
          );
          return merge;
        });
        expect((await phantomLinks(phantom)).single.toList(), [
          user,
          merge,
          true,
        ]);
        expect((await mergesForPhantom(phantom)).single.single, merge);

        await _eraseUser(writer, user);

        expect((await phantomLinks(phantom)).single.toList(), [
          null,
          null,
          true,
        ]);
        expect(await mergesForPhantom(phantom), isEmpty);
      },
    );

    test('erasing the joining account deletes its queued merge', () async {
      final phantom = await createPhantom(_owner);
      final user = await _insertUser(writer);
      final invitation = await _insertInvitation(writer);
      await _queueJob(
        writer,
        phantom: phantom,
        owner: _owner,
        user: user,
        invitation: invitation,
      );
      expect((await jobsForPhantom(phantom)).single[0], invitation);

      await _eraseUser(writer, user);

      expect(await jobsForPhantom(phantom), isEmpty);
      expect(await phantomLinks(phantom), hasLength(1));
    });

    test(
      'erasing a suggested account removes only its hint dismissal',
      () async {
        final phantom = await createPhantom(_owner);
        final user = await _insertUser(writer);
        await _dismissHint(writer, phantom, user);
        await _dismissHint(writer, phantom, _peer);
        expect(
          (await dismissalsForPhantom(phantom)).map((row) => row.single),
          unorderedEquals([user, _peer]),
        );

        await _eraseUser(writer, user);

        expect((await dismissalsForPhantom(phantom)).single.single, _peer);
      },
    );

    test(
      'the upgrade clears first-seen backfill only for existing viewers',
      () async {
        final markers = await writer.execute('''
SELECT viewer_id, backfill_pending FROM public.person_field_first_seen_init
''');
        expect(
          markers.map((row) => row.toList()),
          unorderedEquals([
            [_owner, false],
            [_otherViewer, false],
          ]),
        );
      },
    );

    test(
      'erasing a viewer removes their first-seen initialization marker',
      () async {
        final viewer = await _insertUser(writer);
        final marker = await _sql(
          writer,
          '''
INSERT INTO public.person_field_first_seen_init (viewer_id, at, backfill_pending)
VALUES (@viewer, now(), true) RETURNING viewer_id
''',
          {'viewer': viewer},
        );
        expect(marker.single.single, viewer);

        await _eraseUser(writer, viewer);

        expect(
          await _sql(
            writer,
            '''
SELECT viewer_id FROM public.person_field_first_seen_init
WHERE viewer_id = @viewer
''',
            {'viewer': viewer},
          ),
          isEmpty,
        );
      },
    );

    test(
      'saving a person requires a transaction scoped to their owner',
      () async {
        final id = generateId('PH');
        await expectLater(
          _withoutScope(writer, (tx) => _insertPhantom(tx, id, _owner)),
          _scopeRequired('phantom'),
        );
        final saved = await withPgOwnerScopes(writer, [_owner], (tx) async {
          await tx.execute("SET LOCAL tentura.owner_scope_enforce = 'on'");
          return _insertPhantom(tx, id, _owner);
        });
        expect(saved.single.take(2), [id, _owner]);
      },
    );

    test(
      'recording a merge requires a transaction scoped to its owner',
      () async {
        final phantom = await createPhantom(_owner);
        Future<String> insert(TxSession tx) =>
            _insertMerge(tx, phantom: phantom, owner: _owner, user: _peer);

        await expectLater(
          _withoutScope(writer, insert),
          _scopeRequired('phantom_merge'),
        );
        final merge = await withPgOwnerScopes(writer, [_owner], (tx) async {
          await tx.execute("SET LOCAL tentura.owner_scope_enforce = 'on'");
          return insert(tx);
        });
        expect((await mergesForPhantom(phantom)).single.single, merge);
      },
    );

    test(
      'merge jobs can be queued without an owner scope',
      () async {
        final phantom = await createPhantom(_owner);
        final invitation = await _insertInvitation(writer);
        final queued = await _withoutScope(
          writer,
          (tx) => _queueJob(
            tx,
            phantom: phantom,
            owner: _owner,
            user: _otherPeer,
            invitation: invitation,
          ),
        );
        expect(queued.single.single, invitation);
        expect((await jobsForPhantom(phantom)).single[1], 'queued');
      },
    );

    test(
      'the private storage tables exist without being tracked by Hasura',
      () async {
        final document =
            jsonDecode(
                  File('../../hasura/metadata.json').readAsStringSync(),
                )
                as Map<String, Object?>;
        final metadata = document['metadata']! as Map<String, Object?>;
        final sources = (metadata['sources']! as List<Object?>)
            .cast<Map<String, Object?>>();
        for (final source in sources) {
          final tables = (source['tables']! as List<Object?>)
              .cast<Map<String, Object?>>();
          final trackedNames = tables.map(
            (entry) => (entry['table']! as Map<String, Object?>)['name'],
          );
          expect(trackedNames.toSet().intersection(_tables), isEmpty);
        }

        final physicalTables = await writer.execute('''
SELECT tablename::text FROM pg_tables WHERE schemaname = 'public'
''');
        expect(physicalTables.map((row) => row.single), containsAll(_tables));
      },
    );

    test('Drift exposes all five private storage tables', () async {
      final db = openDisposablePgDatabase(target);
      addTearDown(db.close);
      expect(
        db.allTables.map((table) => table.actualTableName),
        containsAll(_tables),
      );
    });
  }, skip: skipReason);
}
