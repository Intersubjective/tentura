@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:tentura_server/utils/id.dart';
import 'package:test/test.dart';

import '../../api/controllers/websocket/websocket_realtime_protocol_test.dart'
    show expectPrivatePhantomSocketDelivery;
import '../../support/disposable_pg_target.dart';
import '../../support/pg_notification_recorder.dart';
import '../../support/pg_test_public_keys.dart';

const _privateName = 'Zebra Confidants';
const _privateEmoji = '🦓';
const _renamed = 'Quokka Neighbours';
const _inviteExisting = 2;
const _manualLink = 3;

Future<Result> _sql(
  Session session,
  String statement,
  Map<String, Object?> parameters,
) => session.execute(Sql.named(statement), parameters: parameters);

Future<void> _insertPhantom(Session session, String id, String owner) async {
  final result = await _sql(
    session,
    '''
INSERT INTO public.phantom (id, owner_id, display_name, emoji)
VALUES (@id, @owner, @name, @emoji)
''',
    {'id': id, 'owner': owner, 'name': _privateName, 'emoji': _privateEmoji},
  );
  expect(result.affectedRows, 1);
}

Future<void> _renamePhantom(Session session, String id) async {
  final result = await _sql(
    session,
    '''
UPDATE public.phantom SET display_name = @name WHERE id = @id
''',
    {'id': id, 'name': _renamed},
  );
  expect(result.affectedRows, 1);
}

Future<void> _mergePhantom(
  Session session,
  String id,
  String owner,
  String user,
  int origin,
) async {
  final mergeId = generateId('PM');
  final history = await _sql(
    session,
    '''
INSERT INTO public.phantom_merge
  (id, phantom_id, owner_id, user_id, origin, created_at, undo)
VALUES (@merge, @id, @owner, @user, @origin, now(), '{}'::jsonb)
''',
    {
      'id': id,
      'owner': owner,
      'user': user,
      'origin': origin,
      'merge': mergeId,
    },
  );
  expect(history.affectedRows, 1);
  final result = await _sql(
    session,
    '''
UPDATE public.phantom
SET merged_user_id = @user, merged_at = now(),
    merge_origin = @origin, current_merge_id = @merge
WHERE id = @id
''',
    {'id': id, 'user': user, 'origin': origin, 'merge': mergeId},
  );
  expect(result.affectedRows, 1);
}

void _expectPhantomUpdates(
  Iterable<Map<String, dynamic>> messages,
  List<String> owners,
) {
  final updates = messages
      .where((message) => message['entity'] == 'phantom')
      .map((message) => [message['event'], message['user_ids']]);
  // Each committed change invalidates the owner's collection, including
  // insertion and deletion of one row within that collection.
  expect(
    updates,
    unorderedEquals([
      for (final owner in owners)
        [
          'update',
          [owner],
        ],
    ]),
    reason: 'Each owner should receive one private phantom update',
  );
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PHANTOM_REALTIME_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_phantom_realtime',
  );
  final skipReason = await pgSkipReason(target);

  group('Private realtime changes for people outside Tentura', () {
    late Connection writer;
    late Connection listener;
    late PgNotificationRecorder recorder;
    late String ownerA;
    late String ownerB;
    late String linkedUser;
    final rawPayloads = <String>[];

    Future<void> barrier(String token) => _sql(
      writer,
      "SELECT pg_notify('entity_changes', @payload)",
      {
        'payload': jsonEncode({'entity': 'barrier', 'id': token}),
      },
    );

    Future<List<Map<String, dynamic>>> record(
      Future<void> Function() write,
    ) async {
      await recorder.drain(sendBarrier: barrier);
      rawPayloads.clear();
      await write();
      await recorder.flush(sendBarrier: barrier);
      final phantomPayloads = rawPayloads.where(
        (payload) => (jsonDecode(payload) as Map)['entity'] == 'phantom',
      );
      for (final privateText in [_privateName, _renamed, _privateEmoji]) {
        expect(phantomPayloads, everyElement(isNot(contains(privateText))));
      }
      return List.of(recorder.messages);
    }

    Future<String> createUser(int keyIndex) async {
      final id = generateId('U');
      await _sql(
        writer,
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
''',
        {'id': id, 'key': pgTestPublicKey('phantomHints', keyIndex)},
      );
      return id;
    }

    Future<String> createPhantom(String owner) async {
      final id = generateId('PH');
      await withPgOwnerScopes(
        writer,
        [owner],
        (tx) => _insertPhantom(tx, id, owner),
      );
      return id;
    }

    setUpAll(() async {
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      writer = session.writer;
      ownerA = await createUser(1);
      ownerB = await createUser(2);
      linkedUser = await createUser(3);
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      addTearDown(listener.close);
      await listener.execute('LISTEN entity_changes');
      recorder = PgNotificationRecorder(
        listener.channels['entity_changes'].map((payload) {
          rawPayloads.add(payload);
          return payload;
        }),
      );
      addTearDown(recorder.cancel);
    });

    test(
      'creating a person notifies only their owner without private text',
      () async {
        final messages = await record(() async {
          await createPhantom(ownerA);
        });
        _expectPhantomUpdates(messages, [ownerA]);
        for (final message in messages) {
          expect(
            message['user_ids'] as List? ?? const [],
            everyElement(ownerA),
          );
        }
      },
    );

    test(
      'renaming a person notifies only their owner without either name',
      () async {
        final id = await createPhantom(ownerA);
        final messages = await record(
          () => withPgOwnerScopes(writer, [
            ownerA,
          ], (tx) => _renamePhantom(tx, id)),
        );
        _expectPhantomUpdates(messages, [ownerA]);
      },
    );

    for (final (description, origin) in [
      ('merging a person after invite acceptance', _inviteExisting),
      ('manually linking a person', _manualLink),
    ]) {
      test('$description notifies only their owner', () async {
        final id = await createPhantom(ownerA);
        final messages = await record(
          () => withPgOwnerScopes(
            writer,
            [ownerA],
            (tx) => _mergePhantom(tx, id, ownerA, linkedUser, origin),
          ),
        );
        _expectPhantomUpdates(messages, [ownerA]);
      });
    }

    test('undoing a link notifies only the owner', () async {
      final id = await createPhantom(ownerA);
      await withPgOwnerScopes(
        writer,
        [ownerA],
        (tx) => _mergePhantom(tx, id, ownerA, linkedUser, _manualLink),
      );

      final messages = await record(
        () => withPgOwnerScopes(writer, [ownerA], (tx) async {
          final result = await _sql(
            tx,
            '''
UPDATE public.phantom
SET merged_user_id = NULL, merged_at = NULL,
    merge_origin = NULL, current_merge_id = NULL
WHERE id = @id
''',
            {'id': id},
          );
          expect(result.affectedRows, 1);
        }),
      );
      _expectPhantomUpdates(messages, [ownerA]);
    });

    test('removing a saved person notifies only their owner', () async {
      final id = await createPhantom(ownerA);
      final messages = await record(
        () => withPgOwnerScopes(writer, [ownerA], (tx) async {
          final result = await _sql(
            tx,
            'DELETE FROM public.phantom WHERE id = @id',
            {'id': id},
          );
          expect(result.affectedRows, 1);
        }),
      );
      _expectPhantomUpdates(messages, [ownerA]);
    });

    test(
      'two additions and a rename in one commit notify their owner once',
      () async {
        final existing = await createPhantom(ownerA);
        final messages = await record(
          () => withPgOwnerScopes(writer, [ownerA], (tx) async {
            await _insertPhantom(tx, generateId('PH'), ownerA);
            await _insertPhantom(tx, generateId('PH'), ownerA);
            await _renamePhantom(tx, existing);
          }),
        );
        _expectPhantomUpdates(messages, [ownerA]);
      },
    );

    test(
      'one commit affecting two owners notifies each privately once',
      () async {
        final first = await createPhantom(ownerA);
        final second = await createPhantom(ownerB);
        final messages = await record(
          () => withPgOwnerScopes(writer, [ownerA, ownerB], (tx) async {
            await _renamePhantom(tx, first);
            await _renamePhantom(tx, second);
          }),
        );
        _expectPhantomUpdates(messages, [ownerA, ownerB]);
      },
    );

    test(
      'an insert and rename notify once on commit and never on rollback',
      () async {
        final existing = await createPhantom(ownerA);
        final added = generateId('PH');
        final rollback = StateError('Roll back the person changes');
        Future<void> changePeople(TxSession tx) async {
          await _insertPhantom(tx, added, ownerA);
          await _renamePhantom(tx, existing);
        }

        final rolledBack = await record(() async {
          await expectLater(
            withPgOwnerScopes(writer, [ownerA], (tx) async {
              await changePeople(tx);
              throw rollback;
            }),
            throwsA(same(rollback)),
          );
        });
        _expectPhantomUpdates(rolledBack, []);
        final committed = await record(
          () => withPgOwnerScopes(writer, [ownerA], changePeople),
        );
        _expectPhantomUpdates(committed, [ownerA]);
      },
    );

    test(
      'account erasure commits and removes saved people without phantom updates',
      () async {
        final erasedOwner = await createUser(4);
        late String savedPerson;
        final creation = await record(() async {
          savedPerson = await createPhantom(erasedOwner);
        });

        final erasure = await record(() async {
          final erased = await withPgOwnerScopes(
            writer,
            [erasedOwner],
            (tx) => _sql(
              tx,
              'DELETE FROM public."user" WHERE id = @id RETURNING id',
              {'id': erasedOwner},
            ),
          );
          expect(erased.single.single, erasedOwner);
        });
        // A separate connection observes the committed account and cascade.
        expect(
          await _sql(
            listener,
            '''
SELECT id FROM public."user" WHERE id = @owner
UNION ALL
SELECT id FROM public.phantom WHERE id = @phantom
''',
            {'owner': erasedOwner, 'phantom': savedPerson},
          ),
          isEmpty,
        );
        // Like account erasure for person tags, the cascade has no owner
        // left to notify.
        _expectPhantomUpdates(erasure, []);
        // Verify the control after erasure so a missing publisher cannot hide a
        // failing cascade, and a passing cascade alone cannot pass this test.
        _expectPhantomUpdates(creation, [erasedOwner]);
      },
    );

    test(
      'a committed change reaches only the owner tabs with actor echo off',
      () => expectPrivatePhantomSocketDelivery(
        databaseEnv: target.databaseEnv,
        writer: writer,
        owner: ownerA,
        otherAccount: ownerB,
        mutate: () => withPgOwnerScopes(writer, [ownerA], (tx) async {
          await _sql(
            tx,
            "SELECT set_config('tentura.mutating_user_id', @owner, true)",
            {'owner': ownerA},
          );
          await _insertPhantom(tx, generateId('PH'), ownerA);
        }),
      ),
    );
  }, skip: skipReason);
}
