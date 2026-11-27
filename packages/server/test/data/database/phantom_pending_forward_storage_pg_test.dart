@Tags(['pg', 'repo-files'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/owner_graph_unit_of_work.dart';
import 'package:tentura_server/data/repository/phantom_pending_forward_repository.dart';
import 'package:tentura_server/domain/entity/phantom_pending_forward.dart';
import 'package:tentura_server/utils/id.dart';

import '../../support/disposable_pg_target.dart';

const _table = 'phantom_pending_forward';
const _states = ['pending', 'claimed', 'delivered', 'lapsed', 'offered'];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PENDING_FORWARD_TEST_DB',
    defaultNamePrefix: 'tentura_test_pending_forward',
  );
  final skipReason = await pgSkipReason(target);

  group('Request forward storage for people outside Tentura', () {
    late Connection writer;
    late String owner;
    late String person;
    late String request;

    Future<Result> sql(
      String statement, [
      Map<String, Object?> parameters = const {},
    ]) => writer.execute(Sql.named(statement), parameters: parameters);

    Future<String> createUser() async {
      final id = generateId('U');
      await sql(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
        {'id': id, 'key': 'pk-$id'},
      );
      return id;
    }

    Future<String> createPerson() async {
      final id = generateId('PH');
      await writer.executeWithOwnerScopes(
        [owner],
        Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@id, @owner, 'Avery')
'''),
        parameters: {'id': id, 'owner': owner},
      );
      return id;
    }

    Future<String> createRequest({String? author}) async {
      final created = await sql(
        '''
INSERT INTO public.beacon (user_id, title, description)
VALUES (@owner, 'Help with the garden', '') RETURNING id
''',
        {'owner': author ?? owner},
      );
      return created.single.single! as String;
    }

    Future<String> createMerge(String recipient) async {
      final id = generateId('PM');
      await writer.executeWithOwnerScopes(
        [owner],
        Sql.named('''
INSERT INTO public.phantom_merge
  (id, phantom_id, owner_id, user_id, origin, undo)
VALUES (@id, @person, @owner, @recipient, 2, '{}'::jsonb)
'''),
        parameters: {
          'id': id,
          'person': person,
          'owner': owner,
          'recipient': recipient,
        },
      );
      return id;
    }

    Future<String> createForwardEdge(String recipient, {String? sender}) async {
      final created = await sql(
        '''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@request, @sender, @recipient) RETURNING id
''',
        {'request': request, 'sender': sender ?? owner, 'recipient': recipient},
      );
      return created.single.single! as String;
    }

    Future<String> insertForward({
      String state = 'pending',
      String? personId,
      String? requestId,
      String? sender,
      String? recipient,
      String? merge,
      String? edge,
      String? parentEdge,
    }) async {
      final id = generateId('PF');
      final rows = await writer.executeWithOwnerScopes(
        [owner, if (sender != null && sender != owner) sender],
        Sql.named('''
INSERT INTO public.$_table
  (id, phantom_id, sender_id, beacon_id, note, created_at, state,
   merge_id, recipient_id, forward_edge_id, parent_forward_edge_id)
VALUES
  (@id, @person, @sender, @request, 'Can you help?', now(), @state,
   @merge, @recipient, @edge, @parentEdge)
RETURNING id
'''),
        parameters: {
          'id': id,
          'person': personId ?? person,
          'sender': sender ?? owner,
          'request': requestId ?? request,
          'state': state,
          'merge': merge,
          'recipient': recipient,
          'edge': edge,
          'parentEdge': parentEdge,
        },
      );
      expect(rows.single.single, id);
      return id;
    }

    Future<Result> findForward(String id) =>
        sql('SELECT * FROM public.$_table WHERE id = @id', {'id': id});

    Future<void> deleteRow(
      String table,
      String id, {
      String? additionalOwner,
    }) async {
      final deleted = await writer.executeWithOwnerScopes(
        [owner, ?additionalOwner],
        Sql.named('DELETE FROM public.$table WHERE id = @id RETURNING id'),
        parameters: {'id': id},
      );
      expect(deleted.single.single, id);
    }

    setUpAll(() async {
      final session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      addTearDown(() => tearDownDisposablePgWriter(session: session));
    });

    setUp(() async {
      owner = await createUser();
      person = await createPerson();
      request = await createRequest();
    });

    for (final existing in ['pending', 'claimed']) {
      test('a $existing forward blocks a second pending forward', () async {
        final first = await insertForward(state: existing);
        await expectLater(insertForward(), _throwsSqlState('23505'));
        final rows = await sql(
          '''
SELECT id, state FROM public.$_table
WHERE phantom_id = @person AND beacon_id = @request
''',
          {'person': person, 'request': request},
        );
        expect(rows.map((row) => row.toList()), [
          [first, existing],
        ]);
      });
    }

    for (final resolved in ['delivered', 'lapsed', 'offered']) {
      test('a forward moved to $resolved frees the pending slot', () async {
        final original = await insertForward();
        final changed = await writer.executeWithOwnerScopes(
          [owner],
          Sql.named('''
UPDATE public.$_table SET state = @state WHERE id = @id RETURNING state
'''),
          parameters: {'state': resolved, 'id': original},
        );
        expect(changed.single.single, resolved);

        final next = await insertForward();
        final rows = await sql(
          '''
SELECT id, state FROM public.$_table
WHERE phantom_id = @person AND beacon_id = @request
''',
          {'person': person, 'request': request},
        );
        expect(
          rows.map((row) => row.toList()),
          unorderedEquals([
            [original, resolved],
            [next, 'pending'],
          ]),
        );
      });
    }

    test('each person and Request pair has its own pending slot', () async {
      final otherRequest = await createRequest();
      final otherPerson = await createPerson();
      final first = await insertForward();
      final second = await insertForward(requestId: otherRequest);
      final third = await insertForward(personId: otherPerson);

      final rows = await sql(
        '''
SELECT id, phantom_id, beacon_id, state
FROM public.$_table WHERE sender_id = @owner
''',
        {'owner': owner},
      );
      expect(
        rows.map((row) => row.toList()),
        unorderedEquals([
          [first, person, request, 'pending'],
          [second, person, otherRequest, 'pending'],
          [third, otherPerson, request, 'pending'],
        ]),
      );
    });

    test('storage accepts only the five forward states', () async {
      for (final state in _states) {
        final id = await insertForward(
          state: state,
          requestId: await createRequest(),
        );
        expect((await findForward(id)).single.toColumnMap()['state'], state);
      }
      await expectLater(
        insertForward(state: 'sent'),
        anyOf(_throwsSqlState('23514'), _throwsSqlState('22P02')),
      );
    });

    for (final hasParent in [false, true]) {
      final label = hasParent ? 'with a parent edge' : 'without a parent edge';
      test('PostgreSQL stores pending forward data $label', () async {
        String? parent;
        if (hasParent) {
          final originalSender = await createUser();
          request = await createRequest(author: originalSender);
          parent = await createForwardEdge(owner, sender: originalSender);
        }
        final id = await insertForward(parentEdge: parent);
        final row = (await findForward(id)).single.toColumnMap();
        expect(row, containsPair('phantom_id', person));
        expect(row, containsPair('sender_id', owner));
        expect(row, containsPair('beacon_id', request));
        expect(row, containsPair('parent_forward_edge_id', parent));
        expect(row, containsPair('note', 'Can you help?'));
        expect(row, containsPair('state', 'pending'));
        expect(row, containsPair('created_at', isA<DateTime>()));
        for (final field in [
          'merge_id',
          'recipient_id',
          'forward_edge_id',
          'lapse_reason',
          'resolved_at',
        ]) {
          expect(row, containsPair(field, null));
        }
      });
    }

    for (final hasParent in [false, true]) {
      final label = hasParent ? 'with a parent edge' : 'without a parent edge';
      test(
        'the repository records and reads a pending forward $label',
        () async {
          String? parent;
          if (hasParent) {
            final author = await createUser();
            request = await createRequest(author: author);
            parent = await createForwardEdge(owner, sender: author);
          }
          final db = openDisposablePgDatabase(target);
          addTearDown(db.close);
          final repository = PhantomPendingForwardRepository(db);
          final id = generateId('PF');
          const note = 'Can you help on Friday?';
          final beforeWrite = (await sql(
            'SELECT clock_timestamp()',
          )).single.single;
          if (beforeWrite is! DateTime) {
            fail('PostgreSQL did not return a timestamp.');
          }

          final recorded = await OwnerGraphUnitOfWork(db).run(
            {owner},
            owner,
            (scope) => repository.record(
              scope,
              id: id,
              phantomId: person,
              senderId: owner,
              beaconId: request,
              parentForwardEdgeId: parent,
              note: note,
            ),
          );

          expect(recorded, isTrue);
          final row = await repository.findById(senderId: owner, id: id);
          if (row == null) {
            fail('The repository could not read the recorded forward.');
          }
          expect(row.id, id);
          expect(row.phantomId, person);
          expect(row.senderId, owner);
          expect(row.beaconId, request);
          expect(row.parentForwardEdgeId, parent);
          expect(row.note, note);
          expect(row.state, PhantomPendingForwardState.pending);
          expect(row.createdAt.compareTo(beforeWrite), greaterThanOrEqualTo(0));
          expect(row.mergeId, isNull);
          expect(row.recipientId, isNull);
          expect(row.forwardEdgeId, isNull);
          expect(row.lapseReason, isNull);
          expect(row.resolvedAt, isNull);
        },
      );
    }

    test(
      'the repository rejects a forward for another sender’s person',
      () async {
        final sender = await createUser();
        final db = openDisposablePgDatabase(target);
        addTearDown(db.close);
        final repository = PhantomPendingForwardRepository(db);
        final id = generateId('PF');

        final recorded = await OwnerGraphUnitOfWork(db).run(
          {sender},
          sender,
          (scope) => repository.record(
            scope,
            id: id,
            phantomId: person,
            senderId: sender,
            beaconId: request,
            parentForwardEdgeId: null,
            note: 'Can you help on Friday?',
          ),
        );

        expect(recorded, isFalse);
        expect(await findForward(id), isEmpty);
      },
    );

    test('deleting the person deletes their pending forward', () async {
      final forward = await insertForward();
      final unrelated = await insertForward(personId: await createPerson());

      await deleteRow('phantom', person);

      expect(await findForward(forward), isEmpty);
      expect(await findForward(unrelated), hasLength(1));
    });

    test('deleting the Request deletes its pending forward', () async {
      final forward = await insertForward();
      final unrelated = await insertForward(requestId: await createRequest());

      await deleteRow('beacon', request);

      expect(await findForward(forward), isEmpty);
      expect(await findForward(unrelated), hasLength(1));
    });

    test('deleting the sender deletes their pending forward', () async {
      // Keep the person and Request owned by a surviving user so their own
      // cascade paths cannot hide a missing cascade on sender_id.
      final sender = await createUser();
      final forward = await insertForward(sender: sender);
      final unrelated = await insertForward(requestId: await createRequest());

      await deleteRow('"user"', sender, additionalOwner: sender);

      expect(await findForward(forward), isEmpty);
      expect(await findForward(unrelated), hasLength(1));
    });

    test(
      'deleting the recipient clears the link and preserves the forward',
      () async {
        final recipient = await createUser();
        final forward = await insertForward(
          state: 'claimed',
          recipient: recipient,
        );
        final before = (await findForward(forward)).single.toColumnMap();
        expect(before['recipient_id'], recipient);

        await deleteRow('"user"', recipient, additionalOwner: recipient);

        expect((await findForward(forward)).single.toColumnMap(), {
          ...before,
          'recipient_id': null,
        });
      },
    );

    test(
      'deleting the merge clears its link and preserves the claimed forward',
      () async {
        final recipient = await createUser();
        final merge = await createMerge(recipient);
        final forward = await insertForward(
          state: 'claimed',
          merge: merge,
          recipient: recipient,
        );
        final before = (await findForward(forward)).single.toColumnMap();
        expect(before['merge_id'], merge);

        await deleteRow('phantom_merge', merge);

        expect((await findForward(forward)).single.toColumnMap(), {
          ...before,
          'merge_id': null,
        });
      },
    );

    test(
      'deleting the delivery edge clears its link and preserves the forward',
      () async {
        final recipient = await createUser();
        final edge = await createForwardEdge(recipient);
        final forward = await insertForward(
          state: 'delivered',
          recipient: recipient,
          edge: edge,
        );
        final before = (await findForward(forward)).single.toColumnMap();
        expect(before['forward_edge_id'], edge);

        await deleteRow('beacon_forward_edge', edge);

        expect((await findForward(forward)).single.toColumnMap(), {
          ...before,
          'forward_edge_id': null,
        });
      },
    );

    test('Drift can read rows from pending forward storage', () async {
      final db = openDisposablePgDatabase(target);
      addTearDown(db.close);
      final tables = db.allTables.where(
        (table) => table.actualTableName == _table,
      );
      expect(tables, hasLength(1), reason: 'Drift must expose $_table');
      final query = db.select(tables.single);
      final before = await query.get();

      await insertForward();

      expect(await query.get(), hasLength(before.length + 1));
    });

    test(
      'pending forwards are stored privately outside Hasura tracking',
      () async {
        final document =
            jsonDecode(File('../../hasura/metadata.json').readAsStringSync())
                as Map<String, Object?>;
        final metadata = document['metadata']! as Map<String, Object?>;
        final sources = (metadata['sources']! as List)
            .cast<Map<String, Object?>>();
        final tables = [
          for (final source in sources)
            ...(source['tables'] as List? ?? const [])
                .cast<Map<String, Object?>>(),
        ];
        expect(tables, isNotEmpty);
        expect(
          tables.map((entry) => entry['table']),
          isNot(contains(containsPair('name', _table))),
        );

        final installed = await sql(
          "SELECT to_regclass('public.$_table') IS NOT NULL",
        );
        expect(
          installed.single.single,
          isTrue,
          reason: 'The migrated database must store pending forwards',
        );
      },
    );
  }, skip: skipReason);
}

Matcher _throwsSqlState(String code) => throwsA(
  isA<ServerException>().having((error) => error.code, 'SQLSTATE', code),
);
