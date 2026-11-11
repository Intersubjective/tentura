@Tags(['pg'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_post.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Updaauthor01';
const _beacon = 'Bpdadraft0001';
const _pauseKey =
    "hashtextextended('test.post_draft_attachment.publish_pause', 0)";

const _addDoc = r'''
mutation AddDraftAttachment($beaconId: String!, $upload: Upload) {
  postDraftAttachmentAdd(beaconId: $beaconId, upload: $upload)
}
''';

const _removeDoc = r'''
mutation RemoveDraftAttachment($beaconId: String!, $attachmentId: String!) {
  postDraftAttachmentRemove(beaconId: $beaconId, attachmentId: $attachmentId)
}
''';

const _publishDoc = r'''
mutation PublishDraft($id: String!, $body: String!, $recipientIds: [String!]!) {
  postPublish(id: $id, body: $body, recipientIds: $recipientIds) {
    beaconId
    rootMessageId
  }
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_DRAFT_ATTACHMENT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_draft_attachment',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Post draft attachments', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late TenturaDb otherDatabase;
    late _Storage storage;
    late _Harness harness;
    late _Harness other;
    late Uint8List png;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      final base = target.databaseEnv;
      otherDatabase = _openDatabase(base);
      storage = _Storage();
      harness = _Harness.build(database, base, storage);
      other = _Harness.build(otherDatabase, base, storage);
      png = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 3)),
      );
    });

    setUp(() async {
      storage.puts.clear();
      storage.removed.clear();
      storage.objects.clear();
      await writer.execute('''
        TRUNCATE TABLE public.image_object_gc, public.upload_daily_usage,
          public.notification_outbox, public.attention_occurrence,
          public.beacon, public."user" CASCADE
      ''');
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {'id': _author, 'key': pgTestPublicKey('pdattach', 1)},
      );
      await writer.execute(
        Sql.named('''
          INSERT INTO public.beacon
            (id, user_id, title, description, status, kind, forward_policy,
             is_discoverable)
          VALUES (@id, @author, '', '', 3, 1, 1, false)
        '''),
        parameters: {'id': _beacon, 'author': _author},
      );
    });

    tearDown(() async {
      await writer.execute(
        'DROP TRIGGER IF EXISTS test_pause_post_publish ON public.beacon',
      );
      await writer.execute(
        'DROP TRIGGER IF EXISTS test_abort_beacon_delete ON public.beacon',
      );
      await writer.execute(
        'DROP TRIGGER IF EXISTS test_abort_attachment_transfer '
        'ON public.beacon_room_message_attachment',
      );
      await writer.execute('SELECT pg_advisory_unlock($_pauseKey)');
    });

    tearDownAll(() async {
      await otherDatabase.close();
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<Object?> execute(
      String document,
      Map<String, dynamic> variables, {
      Stream<Uint8List>? upload,
      GraphQL? schema,
    }) => (schema ?? harness.graphQL).parseAndExecute(
      document,
      variableValues: variables,
      globalVariables: {
        kGlobalInputQueryJwt: const JwtEntity(sub: _author),
        kGlobalInputQueryFile: ?upload,
      },
    );

    Future<void> addAttachment({
      required Uint8List bytes,
      required String filename,
      required String mime,
      GraphQL? schema,
      String beaconId = _beacon,
    }) async {
      final result = await execute(
        _addDoc,
        {
          'beaconId': beaconId,
          'upload': {'filename': filename, 'type': mime},
        },
        upload: Stream.value(bytes),
        schema: schema,
      );
      expect(
        (result! as Map<String, dynamic>)['postDraftAttachmentAdd'],
        isNotNull,
        reason: 'saving a draft attachment must succeed',
      );
    }

    Future<void> addImage({GraphQL? schema}) => addAttachment(
      bytes: png,
      filename: 'uploads/photo.png',
      mime: 'image/png',
      schema: schema,
    );

    Future<void> addFile(
      String filename,
      Uint8List bytes, {
      GraphQL? schema,
      String beaconId = _beacon,
    }) => addAttachment(
      bytes: bytes,
      filename: filename,
      mime: 'text/plain',
      schema: schema,
      beaconId: beaconId,
    );

    Future<List<List<Object?>>> draftRows([Session? session]) async {
      final rows = await (session ?? writer).execute(
        Sql.named('''
          SELECT kind, image_id::text, file_url, file_name, mime, size_bytes,
                 width, height, position
          FROM public.post_draft_attachment
          WHERE beacon_id = @id
          ORDER BY position, id
        '''),
        parameters: {'id': _beacon},
      );
      return [for (final row in rows) row.toList()];
    }

    Future<String> draftAttachmentId({required int position}) async {
      final rows = await writer.execute(
        Sql.named('''
          SELECT id FROM public.post_draft_attachment
          WHERE beacon_id = @id AND position = @position
        '''),
        parameters: {'id': _beacon, 'position': position},
      );
      return rows.single.single! as String;
    }

    Future<void> removeAttachment(String attachmentId) async {
      final result = await execute(_removeDoc, {
        'beaconId': _beacon,
        'attachmentId': attachmentId,
      });
      expect(
        (result! as Map<String, dynamic>)['postDraftAttachmentRemove'],
        isNotNull,
        reason: 'removing a draft attachment must succeed',
      );
    }

    Future<Map<String, dynamic>> publish({
      String body = 'Hello',
      GraphQL? schema,
    }) async {
      final result = await execute(_publishDoc, {
        'id': _beacon,
        'body': body,
        'recipientIds': <String>[],
      }, schema: schema);
      final published =
          (result! as Map<String, dynamic>)['postPublish']
              as Map<String, dynamic>?;
      expect(published, isNotNull);
      return published!;
    }

    Future<List<List<Object?>>> rootAttachments(String messageId) async {
      final rows = await writer.execute(
        Sql.named('''
          SELECT image_id::text, file_url, file_name, mime, size_bytes,
                 width, height, position
          FROM public.beacon_room_message_attachment
          WHERE message_id = @id
          ORDER BY position, id
        '''),
        parameters: {'id': messageId},
      );
      return [for (final row in rows) row.toList()];
    }

    Future<int> beaconCount() async =>
        (await writer.execute(
              Sql.named('SELECT count(*) FROM public.beacon WHERE id = @id'),
              parameters: {'id': _beacon},
            )).single.single!
            as int;

    Future<bool> imageQueued(String imageId) async =>
        (await writer.execute(
              Sql.named(
                'SELECT count(*) FROM public.image_object_gc '
                'WHERE image_id::text = @id',
              ),
              parameters: {'id': imageId},
            )).single.single!
            as int ==
        1;

    test(
      'post_draft_attachment has the message-attachment columns with '
      'beacon_id in place of message_id',
      () async {
        Future<Map<String, Map<String, Object?>>> columns(String table) async {
          final rows = await writer.execute(
            Sql.named('''
              SELECT column_name, data_type, udt_name, is_nullable,
                     column_default
              FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = @table
            '''),
            parameters: {'table': table},
          );
          return {
            for (final row in rows)
              row[0]! as String: {
                'data_type': row[1],
                'udt_name': row[2],
                'is_nullable': row[3],
                'column_default': row[4],
              },
          };
        }

        final message = await columns('beacon_room_message_attachment');
        final draft = await columns('post_draft_attachment');
        expect(message, isNotEmpty);
        final expected = {
          for (final entry in message.entries)
            entry.key == 'message_id' ? 'beacon_id' : entry.key: entry.value,
        };
        expect(draft, expected);

        final constraints = await writer.execute(
          Sql.named('''
            SELECT pg_get_constraintdef(con.oid)
            FROM pg_constraint con
            JOIN pg_class rel ON rel.oid = con.conrelid
            JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
            WHERE nsp.nspname = 'public' AND rel.relname = @table
          '''),
          parameters: {'table': 'post_draft_attachment'},
        );
        final defs = [for (final row in constraints) row[0]! as String];
        expect(defs, anyElement('PRIMARY KEY (id)'));
        expect(
          defs,
          anyElement(
            allOf(
              contains('FOREIGN KEY (beacon_id)'),
              contains('REFERENCES'),
              contains('beacon'),
              contains('ON DELETE CASCADE'),
            ),
          ),
        );
      },
    );

    test('deleting the Post removes its draft attachment rows', () async {
      final regclass = (await writer.execute(
        "SELECT to_regclass('public.post_draft_attachment')::text",
      )).single.single;
      expect(regclass, 'post_draft_attachment');

      await writer.execute(
        Sql.named('''
          INSERT INTO public.post_draft_attachment (id, beacon_id, kind)
          VALUES ('Apdacascad01', @beacon, @kind)
        '''),
        parameters: {
          'beacon': _beacon,
          'kind': BeaconRoomMessageAttachmentKind.file,
        },
      );
      await writer.execute(
        Sql.named('DELETE FROM public.beacon WHERE id = @id'),
        parameters: {'id': _beacon},
      );
      expect(await draftRows(), isEmpty);
    });

    test(
      'the author can save an image and then a file on a draft, in that order',
      () async {
        final putsBefore = storage.puts.length;
        await addImage();
        await addFile('uploads/notes.txt', Uint8List.fromList([9, 8, 7, 6]));

        final rows = await draftRows();
        expect(rows, hasLength(2));
        final image = rows[0];
        final file = rows[1];
        expect(image[0], BeaconRoomMessageAttachmentKind.image);
        expect(image[1], isNotNull);
        expect(image[2], isNull);
        expect(image[3], 'photo.png');
        expect(image[4], 'image/png');
        expect(image[5], png.length);
        // Like message attachments: dimensions live on the image row, which
        // the image-hash task fills in later.
        expect(image[6], isNull);
        expect(image[7], isNull);
        expect(image[8], 0);
        expect(file[0], BeaconRoomMessageAttachmentKind.file);
        expect(file[1], isNull);
        expect(file[3], 'notes.txt');
        expect(file[4], 'text/plain');
        expect(file[5], 4);
        expect(file[6], isNull);
        expect(file[7], isNull);
        expect(file[8], 1);
        final path = file[2]! as String;
        expect(storage.objects[path], Uint8List.fromList([9, 8, 7, 6]));
        expect(storage.puts.length, greaterThan(putsBefore));
      },
    );

    test(
      'attachments saved in one database session are read back and published '
      'from a new session without another upload',
      () async {
        Future<List<List<Object?>>> rowsWithIds(Session session) async {
          final rows = await session.execute(
            Sql.named('''
              SELECT id, kind, image_id::text, file_url, file_name, mime,
                     size_bytes, width, height, position
              FROM public.post_draft_attachment
              WHERE beacon_id = @id
              ORDER BY position, id
            '''),
            parameters: {'id': _beacon},
          );
          return [for (final row in rows) row.toList()];
        }

        // The device that saved the draft: its own pool, then closed.
        final first = _openDatabase(target.databaseEnv);
        var firstClosed = false;
        try {
          final firstSession = _Harness.build(
            first,
            target.databaseEnv,
            storage,
          );
          await addImage(schema: firstSession.graphQL);
          await addFile(
            'uploads/notes.txt',
            Uint8List.fromList([4, 5, 6, 7]),
            schema: firstSession.graphQL,
          );
          await first.close();
          firstClosed = true;
        } finally {
          if (!firstClosed) await first.close();
        }
        final puts = storage.puts.length;

        // Reload / another device: a brand-new connection and pool.
        final fresh = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        final List<List<Object?>> saved;
        try {
          saved = await rowsWithIds(fresh);
        } finally {
          await fresh.close();
        }
        final filePath = storage.puts.singleWhere(
          (path) => _sameBytes(storage.objects[path], [4, 5, 6, 7]),
        );
        expect(saved, hasLength(2));
        final imageId = saved[0][2];
        expect(imageId, isA<String>());
        expect(saved[0][0], isA<String>());
        expect(saved[1][0], isA<String>());
        expect(saved[0][0], isNot(saved[1][0]));
        // Every persisted field: id, kind, image_id, file_url, file_name,
        // mime, size_bytes, width, height, position.
        expect(saved[0].sublist(1), [
          BeaconRoomMessageAttachmentKind.image,
          imageId,
          null,
          'photo.png',
          'image/png',
          png.length,
          null,
          null,
          0,
        ]);
        expect(saved[1].sublist(1), [
          BeaconRoomMessageAttachmentKind.file,
          null,
          filePath,
          'notes.txt',
          'text/plain',
          4,
          null,
          null,
          1,
        ]);
        final image = (await writer.execute(
          Sql.named('SELECT author_id FROM public.image WHERE id::text = @id'),
          parameters: {'id': imageId},
        )).single.toList();
        expect(image, [_author], reason: 'the image row behind the attachment');

        final second = _openDatabase(target.databaseEnv);
        try {
          final secondSession = _Harness.build(
            second,
            target.databaseEnv,
            storage,
          );
          final published = await publish(
            body: 'Published from another device',
            schema: secondSession.graphQL,
          );
          expect(storage.puts, hasLength(puts));
          final moved = await rootAttachments(
            published['rootMessageId']! as String,
          );
          // image_id, file_url, file_name, mime, size_bytes, width, height,
          // position: exactly what was saved, in the saved order.
          expect(moved, [for (final row in saved) row.sublist(2)]);
        } finally {
          await second.close();
        }
      },
    );

    test(
      'the eleventh attachment is refused and the first ten remain',
      () async {
        for (var i = 0; i < 10; i++) {
          await addFile('file-$i.txt', Uint8List.fromList([i, 1, 2, 3]));
        }
        await expectLater(
          addFile('file-10.txt', Uint8List.fromList([10, 1, 2, 3])),
          throwsA(
            isA<BeaconCreateException>().having(
              (error) => error.description,
              'description',
              'Maximum attachments per message reached',
            ),
          ),
        );
        expect(await draftRows(), hasLength(10));
      },
    );

    test(
      'two additions that would pass the cap leave exactly ten attachments',
      () async {
        for (var i = 0; i < 9; i++) {
          await addFile('held-$i.txt', Uint8List.fromList([i, 2, 2, 2]));
        }
        final outcomes = await Future.wait<Object?>([
          _attempt(
            () => addFile(
              'race-a.txt',
              Uint8List.fromList([20, 2, 2, 2]),
            ),
          ),
          _attempt(
            () => addFile(
              'race-b.txt',
              Uint8List.fromList([21, 2, 2, 2]),
              schema: other.graphQL,
            ),
          ),
        ]);
        expect(outcomes.where((outcome) => outcome == null), hasLength(1));
        expect(outcomes.whereType<BeaconCreateException>(), hasLength(1));
        expect(
          outcomes.whereType<BeaconCreateException>().single.description,
          'Maximum attachments per message reached',
        );
        expect(await draftRows(), hasLength(10));
      },
    );

    test('a published Post refuses another draft attachment', () async {
      await publish();
      await expectLater(
        addFile('after.txt', Uint8List.fromList([1, 2, 3, 4])),
        throwsA(_refusedBecausePublished),
      );
      expect(await draftRows(), isEmpty);
    });

    test(
      'an attachment racing publication is on the root message or refused, '
      'and is not left on the draft',
      () async {
        await writer.execute('''
          CREATE OR REPLACE FUNCTION public.test_pause_post_publish()
          RETURNS trigger LANGUAGE plpgsql AS \$\$
          BEGIN
            IF NEW.id = '$_beacon' AND NEW.status = 0 AND OLD.status = 3 THEN
              PERFORM set_config('lock_timeout', '8s', true);
              PERFORM pg_advisory_lock($_pauseKey);
              PERFORM pg_advisory_unlock($_pauseKey);
            END IF;
            RETURN NEW;
          END
          \$\$
        ''');
        await writer.execute('''
          CREATE TRIGGER test_pause_post_publish
          BEFORE UPDATE OF status ON public.beacon
          FOR EACH ROW EXECUTE FUNCTION public.test_pause_post_publish()
        ''');
        await writer.execute('SELECT pg_advisory_lock($_pauseKey)');
        final publishFuture = publish(body: 'Going live');
        // Errors are captured at once so neither future fails unobserved.
        final publishOutcome = publishFuture.then<Object?>(
          (result) => result,
          onError: (Object error) => error,
        );
        final addOutcome = addFile(
          'racing.txt',
          Uint8List.fromList([3, 3, 3, 3]),
          schema: other.graphQL,
        ).then<Object?>((_) => null, onError: (Object error) => error);
        try {
          expect(
            await _waitForLockWaiter(writer),
            isTrue,
            reason: 'publication must be paused mid-way for the race',
          );
          await writer.execute('SELECT pg_advisory_unlock($_pauseKey)');
          final published = await publishOutcome.timeout(
            const Duration(seconds: 15),
          );
          expect(published, isA<Map<String, dynamic>>());
          final added = await addOutcome.timeout(const Duration(seconds: 15));
          expect(
            added,
            anyOf(isNull, _refusedBecausePublished),
            reason: 'the racing addition either succeeds or is refused',
          );

          // The invariant, whatever the interleaving: nothing is stranded as
          // a draft attachment of the now-published Post.
          final stranded =
              (await writer.execute(
                    Sql.named(
                      'SELECT count(*) FROM public.post_draft_attachment '
                      'WHERE beacon_id = @id',
                    ),
                    parameters: {'id': _beacon},
                  )).single.single!
                  as int;
          expect(stranded, 0);

          // A success could only have committed before publication, so it
          // is on the root message exactly once; a refusal left nothing.
          final racingOnRoot = (await rootAttachments(
            (published! as Map<String, dynamic>)['rootMessageId']! as String,
          )).where((row) => row[2] == 'racing.txt').length;
          expect(racingOnRoot, added == null ? 1 : 0);
        } finally {
          await writer.execute('SELECT pg_advisory_unlock($_pauseKey)');
          await publishOutcome.timeout(
            const Duration(seconds: 15),
            onTimeout: () => null,
          );
          await addOutcome.timeout(
            const Duration(seconds: 15),
            onTimeout: () => null,
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'publishing moves saved attachments onto the root message in order '
      'without uploading them again',
      () async {
        await addImage();
        await addFile('uploads/a.txt', Uint8List.fromList([1, 1, 1, 1]));
        await addFile('uploads/b.txt', Uint8List.fromList([2, 2, 2, 2]));
        final saved = await draftRows();
        final puts = storage.puts.length;

        final published = await publish(body: 'With files');
        expect(storage.puts, hasLength(puts));
        expect(await draftRows(), isEmpty);
        final moved = await rootAttachments(
          published['rootMessageId']! as String,
        );
        expect(moved, hasLength(3));
        for (var i = 0; i < saved.length; i++) {
          expect(moved[i][0], saved[i][1], reason: 'image id at position $i');
          expect(
            moved[i][1],
            saved[i][2],
            reason: 'storage path at position $i',
          );
          expect(moved[i][2], saved[i][3]);
          expect(moved[i][3], saved[i][4]);
          expect(moved[i][4], saved[i][5]);
          expect(moved[i][7], i);
        }
      },
    );

    test(
      'a draft with no text and one saved attachment can be published',
      () async {
        await addFile('uploads/only.txt', Uint8List.fromList([8, 8, 8, 8]));
        final saved = await draftRows();
        final puts = storage.puts.length;
        final published = await publish(body: '');
        expect(storage.puts, hasLength(puts));
        final moved = await rootAttachments(
          published['rootMessageId']! as String,
        );
        expect(moved, hasLength(1));
        expect(moved.single[1], saved.single[2]);
        expect(moved.single[2], 'only.txt');
      },
    );

    Future<void> expectEmptyPublishRefusedAndDraftKept() async {
      await expectLater(
        publish(body: '   '),
        throwsA(
          isA<BeaconCreateException>().having(
            (error) => error.description,
            'description',
            'A Post needs text or an attachment',
          ),
        ),
      );
      final state = (await writer.execute(
        Sql.named(
          'SELECT status, post_root_message_id FROM public.beacon '
          'WHERE id = @id',
        ),
        parameters: {'id': _beacon},
      )).single;
      expect(state[0], 3, reason: 'the Post stays a draft');
      expect(state[1], isNull);
      final messages =
          (await writer.execute(
                Sql.named(
                  'SELECT count(*) FROM public.beacon_room_message '
                  'WHERE beacon_id = @id',
                ),
                parameters: {'id': _beacon},
              )).single.single!
              as int;
      expect(messages, 0);
    }

    test(
      'a draft with no text and no saved attachments cannot be published',
      expectEmptyPublishRefusedAndDraftKept,
    );

    test(
      'a draft whose only attachment was removed cannot be published '
      'without text',
      () async {
        await addFile('uploads/removed.txt', Uint8List.fromList([7, 1, 7, 1]));
        await removeAttachment(await draftAttachmentId(position: 0));
        expect(await draftRows(), isEmpty);
        await expectEmptyPublishRefusedAndDraftKept();
      },
    );

    test(
      'a rolled-back delivery keeps the draft attachments and a retry '
      'moves them once',
      () async {
        await addImage();
        await addFile('uploads/a.txt', Uint8List.fromList([1, 4, 4, 4]));
        await addFile('uploads/b.txt', Uint8List.fromList([2, 4, 4, 4]));
        final saved = await draftRows();
        final puts = storage.puts.length;
        await writer.execute('''
          CREATE TABLE IF NOT EXISTS public.test_abort_attachment_transfer (
            id integer PRIMARY KEY
          )
        ''');
        await writer.execute(
          'INSERT INTO public.test_abort_attachment_transfer (id) VALUES (1) '
          'ON CONFLICT (id) DO NOTHING',
        );
        await writer.execute(r'''
          CREATE OR REPLACE FUNCTION public.test_abort_attachment_transfer()
          RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            IF EXISTS (
              SELECT 1 FROM public.test_abort_attachment_transfer
            ) THEN
              RAISE EXCEPTION 'attachment transfer aborted'
                USING ERRCODE = 'P0001';
            END IF;
            RETURN NEW;
          END
          $$
        ''');
        await writer.execute('''
          CREATE TRIGGER test_abort_attachment_transfer
          AFTER INSERT ON public.beacon_room_message_attachment
          FOR EACH ROW
          EXECUTE FUNCTION public.test_abort_attachment_transfer()
        ''');
        try {
          await expectLater(
            publish(body: 'First try'),
            throwsA(
              isA<Object>().having(
                (error) => '$error',
                'error',
                contains('attachment transfer aborted'),
              ),
            ),
            reason: 'the failure comes from the attachment transfer itself',
          );
          // Nothing of the delivery transaction is committed.
          expect(await draftRows(), saved);
          final messages =
              (await writer.execute(
                    Sql.named(
                      'SELECT count(*) FROM public.beacon_room_message '
                      'WHERE beacon_id = @id',
                    ),
                    parameters: {'id': _beacon},
                  )).single.single!
                  as int;
          expect(messages, 0);
          final rootPointer = (await writer.execute(
            Sql.named(
              'SELECT post_root_message_id FROM public.beacon WHERE id = @id',
            ),
            parameters: {'id': _beacon},
          )).single.single;
          expect(rootPointer, isNull);
          final transferred =
              (await writer.execute(
                    Sql.named('''
              SELECT count(*) FROM public.beacon_room_message_attachment a
              JOIN public.beacon_room_message m ON m.id = a.message_id
              WHERE m.beacon_id = @id
            '''),
                    parameters: {'id': _beacon},
                  )).single.single!
                  as int;
          expect(transferred, 0);
          expect(await imageQueued(saved[0][1]! as String), isFalse);
          expect(storage.removed, isEmpty);
          expect(storage.puts, hasLength(puts));

          await writer.execute(
            'DELETE FROM public.test_abort_attachment_transfer',
          );
          final published = await publish(body: 'First try');
          expect(storage.puts, hasLength(puts), reason: 'no re-upload');
          expect(storage.removed, isEmpty);
          expect(await draftRows(), isEmpty);
          final moved = await rootAttachments(
            published['rootMessageId']! as String,
          );
          // Each saved attachment exactly once, with all its metadata, in
          // its saved order: image_id, file_url, file_name, mime, size,
          // width, height, position.
          expect(moved, [
            for (var i = 0; i < saved.length; i++)
              [
                saved[i][1],
                saved[i][2],
                saved[i][3],
                saved[i][4],
                saved[i][5],
                saved[i][6],
                saved[i][7],
                i,
              ],
          ]);
          final allOnPost =
              (await writer.execute(
                    Sql.named('''
              SELECT count(*) FROM public.beacon_room_message_attachment a
              JOIN public.beacon_room_message m ON m.id = a.message_id
              WHERE m.beacon_id = @id
            '''),
                    parameters: {'id': _beacon},
                  )).single.single!
                  as int;
          expect(allOnPost, saved.length);
          expect(await imageQueued(saved[0][1]! as String), isFalse);
        } finally {
          await writer.execute(
            'DROP TRIGGER IF EXISTS test_abort_attachment_transfer '
            'ON public.beacon_room_message_attachment',
          );
          await writer.execute(
            'DROP TABLE IF EXISTS public.test_abort_attachment_transfer',
          );
        }
      },
    );

    test(
      'removing an image drops that draft row and queues the image '
      'for deletion',
      () async {
        await addImage();
        await addFile('uploads/keep.txt', Uint8List.fromList([5, 5, 5, 5]));
        final before = await draftRows();
        final imageId = before.first[1]! as String;
        final imageAttachmentId = await draftAttachmentId(position: 0);
        await removeAttachment(imageAttachmentId);
        final after = await draftRows();
        expect(after, hasLength(1));
        expect(after.single[2], before[1][2]);
        expect(after.single[3], 'keep.txt');
        expect(await imageQueued(imageId), isTrue);
      },
    );

    test(
      'removing a file drops that draft row and deletes the stored object '
      'after commit',
      () async {
        await addFile('uploads/gone.txt', Uint8List.fromList([6, 6, 6, 6]));
        await addFile('uploads/stay.txt', Uint8List.fromList([7, 7, 7, 7]));
        final before = await draftRows();
        final path = before.first[2]! as String;
        storage.removed.clear();
        await removeAttachment(await draftAttachmentId(position: 0));
        expect(await draftRows(), hasLength(1));
        expect((await draftRows()).single[3], 'stay.txt');
        expect(storage.removed, [path]);
      },
    );

    test(
      'rolling back a file removal keeps the row and does not delete '
      'the object',
      () async {
        await addFile('uploads/kept.txt', Uint8List.fromList([8, 1, 1, 1]));
        final before = await draftRows();
        final attachmentId = await draftAttachmentId(position: 0);
        await writer.execute(r'''
          CREATE OR REPLACE FUNCTION public.test_abort_draft_attachment_delete()
          RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            RAISE EXCEPTION 'draft attachment removal rolled back'
              USING ERRCODE = 'P0001';
          END
          $$
        ''');
        await writer.execute('''
          CREATE CONSTRAINT TRIGGER test_abort_draft_attachment_delete
          AFTER DELETE ON public.post_draft_attachment
          DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW
          EXECUTE FUNCTION public.test_abort_draft_attachment_delete()
        ''');
        storage.removed.clear();
        try {
          await expectLater(removeAttachment(attachmentId), throwsA(anything));
          expect(await draftRows(), before);
          expect(storage.removed, isEmpty);
        } finally {
          await writer.execute(
            'DROP TRIGGER IF EXISTS test_abort_draft_attachment_delete '
            'ON public.post_draft_attachment',
          );
        }
      },
    );

    test(
      'discarding a draft deletes its attachments, queues its images and '
      'removes its files',
      () async {
        const otherPost = 'Bpdaother0001';
        await writer.execute(
          Sql.named('''
            INSERT INTO public.beacon
              (id, user_id, title, description, status, kind, forward_policy,
               is_discoverable)
            VALUES (@id, @author, '', '', 3, 1, 1, false)
          '''),
          parameters: {'id': otherPost, 'author': _author},
        );
        await addFile(
          'uploads/unrelated.txt',
          Uint8List.fromList([9, 9, 3, 3]),
          beaconId: otherPost,
        );
        await addImage();
        await addFile('uploads/discard.txt', Uint8List.fromList([9, 9, 1, 1]));
        await addFile('uploads/second.txt', Uint8List.fromList([9, 9, 2, 2]));
        final saved = await draftRows();
        expect(saved, hasLength(3));
        final imageId = saved[0][1]! as String;
        final filePaths = [saved[1][2]! as String, saved[2][2]! as String];
        final otherRows = await writer.execute(
          Sql.named(
            'SELECT file_url FROM public.post_draft_attachment '
            'WHERE beacon_id = @id',
          ),
          parameters: {'id': otherPost},
        );
        final otherPath = otherRows.single.single! as String;
        storage.removed.clear();

        final deleted = await harness.beacons.deleteById(
          beaconId: _beacon,
          userId: _author,
        );
        expect(deleted, isTrue);
        expect(await beaconCount(), 0);
        expect(await draftRows(), isEmpty);
        expect(await imageQueued(imageId), isTrue);
        // Every attached file, each once, and nothing else.
        expect(storage.removed, unorderedEquals(filePaths));
        expect(storage.removed, isNot(contains(otherPath)));
        expect(storage.objects.containsKey(otherPath), isTrue);
        final otherLeft =
            (await writer.execute(
                  Sql.named(
                    'SELECT count(*) FROM public.post_draft_attachment '
                    'WHERE beacon_id = @id',
                  ),
                  parameters: {'id': otherPost},
                )).single.single!
                as int;
        expect(otherLeft, 1, reason: 'another draft keeps its attachment');
      },
    );

    test(
      'a rolled-back discard keeps the draft and does not remove its files',
      () async {
        await addImage();
        await addFile('uploads/safe.txt', Uint8List.fromList([9, 9, 2, 2]));
        final saved = await draftRows();
        await writer.execute('''
          CREATE OR REPLACE FUNCTION public.test_abort_beacon_delete()
          RETURNS trigger LANGUAGE plpgsql AS \$\$
          BEGIN
            IF OLD.id = '$_beacon' THEN
              RAISE EXCEPTION 'discard rolled back' USING ERRCODE = 'P0001';
            END IF;
            RETURN OLD;
          END
          \$\$
        ''');
        await writer.execute('''
          CREATE CONSTRAINT TRIGGER test_abort_beacon_delete
          AFTER DELETE ON public.beacon
          DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW
          EXECUTE FUNCTION public.test_abort_beacon_delete()
        ''');
        storage.removed.clear();
        try {
          await expectLater(
            harness.beacons.deleteById(beaconId: _beacon, userId: _author),
            throwsA(anything),
          );
          expect(await beaconCount(), 1);
          expect(await draftRows(), saved);
          expect(storage.removed, isEmpty);
        } finally {
          await writer.execute(
            'DROP TRIGGER IF EXISTS test_abort_beacon_delete ON public.beacon',
          );
        }
      },
    );
  });
}

TenturaDb _openDatabase(Env base) => TenturaDb(
  Env(
    environment: Environment.test,
    pgHost: base.pgHost,
    pgPort: base.pgPort,
    pgDatabase: base.pgDatabase,
    pgUsername: base.pgUsername,
    pgPassword: base.pgPassword,
    maxConnectionCount: 1,
    pgStatementTimeoutMs: 60000,
    printEnv: false,
    isDebugModeOn: false,
  ),
);

/// A refused draft attachment: a domain refusal about the Post (not the
/// per-message cap, not a crash or a missing field). The contract names no
/// specific code, so `BeaconCreateException` and `PostNotOpenException` both
/// qualify.
final Matcher _refusedBecausePublished = isA<ExceptionBase>()
    .having((error) => error.code, 'code', isA<BeaconExceptionCodes>())
    .having(
      (error) => error.description,
      'description',
      isNot('Maximum attachments per message reached'),
    );

bool _sameBytes(Uint8List? actual, List<int> expected) =>
    actual != null &&
    actual.length == expected.length &&
    Iterable<int>.generate(
      expected.length,
    ).every((i) => actual[i] == expected[i]);

Future<Object?> _attempt(Future<void> Function() body) async {
  try {
    await body();
    return null;
  } on BeaconCreateException catch (error) {
    return error;
  }
}

Future<bool> _waitForLockWaiter(Connection writer) async {
  for (var i = 0; i < 25; i++) {
    final waiting =
        (await writer.execute('''
      SELECT count(*) FROM pg_locks l
      JOIN pg_database d ON d.oid = l.database
      WHERE l.locktype = 'advisory'
        AND NOT l.granted
        AND d.datname = current_database()
    ''')).single.single!
            as int;
    if (waiting > 0) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

final class _Harness {
  const _Harness(this.beacons, this.graphQL);

  final BeaconCase beacons;
  final GraphQL graphQL;

  factory _Harness.build(TenturaDb db, Env env, _Storage storage) {
    final logger = Logger('PostDraftAttachmentPgTest');
    final uow = MutatingUnitOfWork(db);
    final attention = TransactionalAttentionCase(
      uow,
      AttentionDispatchRepository(db, logger),
    );
    final beaconRepository = BeaconRepository(db);
    final roomRepository = BeaconRoomRepository(db);
    final help = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final access = BeaconAccessRepository(db);
    final blocks = UserBlockRepository(env, db);
    final hierarchy = BeaconHierarchyRepository(db);
    final intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        roomRepository,
        db,
        help,
        commitments,
      ),
      UserRepository(
        env,
        db,
        _UnusedGenealogy(),
        InviteSeedPromptRepositoryMock(),
      ),
      access,
      blocks,
    );
    final commitmentQuery = CommitmentQueryCase(
      commitments,
      help,
      env: env,
      logger: logger,
    );
    final gc = ImageObjectGcRepository(db, storage);
    final images = ImageRepository(
      db,
      storage,
      UploadQuotaRepository(db),
      gc,
      env,
      logger,
    );
    final tasks = _Tasks();
    final beacons = BeaconCase(
      beaconRepository,
      images,
      gc,
      tasks,
      commitmentQuery,
      access,
      hierarchy,
      FakeBeaconChildCreatePort(),
      BeaconLifecycleEffectsCase(
        BeaconHierarchyOutboxRepository(db),
        env: env,
        logger: logger,
      ),
      attentionIntents: intents,
      attention: attention,
      remoteStorage: storage,
      env: env,
      logger: logger,
    );
    final forwards = ForwardCase(
      ForwardEdgeRepository(db),
      ForwardAttributionRepository(db),
      help,
      InboxRepository(db),
      CapabilityEvidenceRepository(db),
      beaconRepository,
      blocks,
      PersonVisibilityRepository(db),
      access,
      attentionIntents: intents,
      attention: attention,
      postLock: PostLockRepository(db),
      env: env,
      logger: logger,
    );
    final room = BeaconRoomCase(
      roomRepository,
      CoordinationItemRepository(db),
      _UnusedFactCards(),
      images,
      tasks,
      storage,
      _UnusedPolling(),
      UploadQuotaRepository(db),
      blocks,
      uow,
      hierarchy,
      const ProductionDiscussionProductPolicy(),
      beaconRepository: beaconRepository,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    );
    final posts = PostCase(
      beaconCase: beacons,
      forwardCase: forwards,
      roomCase: room,
      beaconRepository: beaconRepository,
      postLock: PostLockRepository(db),
      attention: attention,
    );
    final graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.add(
            GraphQLObjectField(
              '_health',
              graphQLBoolean.nonNullable(),
              resolve: (_, _) => true,
            ),
          ),
        mutationType: GraphQLObjectType('Mutation', 'Mutation root')
          ..fields.addAll(MutationPost(postCase: posts).all),
      ),
    );
    return _Harness(beacons, graphQL);
  }
}

final class _Storage extends Fake implements RemoteStoragePort {
  final puts = <String>[];
  final removed = <String>[];
  final objects = <String, Uint8List>{};

  @override
  Future<Uint8List> getObject(String path) async =>
      objects[path] ?? Uint8List(0);

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    final builder = BytesBuilder(copy: false);
    await bytes.forEach(builder.add);
    objects[path] = builder.takeBytes();
    puts.add(path);
    return path;
  }

  @override
  Future<void> removeObject(String path) async {
    removed.add(path);
    objects.remove(path);
  }
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedPolling extends Fake implements PollingRepositoryPort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task-id';
}
